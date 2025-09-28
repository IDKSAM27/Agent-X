import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../core/models/offline_models.dart';
import '../core/services/connectivity_service.dart';
import '../core/config/api_config.dart';

class TaskRepository {
  static final TaskRepository _instance = TaskRepository._internal();
  factory TaskRepository() => _instance;
  TaskRepository._internal();

  final DatabaseHelper _db = DatabaseHelper();
  final ConnectivityService _connectivity = ConnectivityService();
  final Uuid _uuid = const Uuid();

  // Use Dio for HTTP calls (same as your screens)
  final Dio _dio = Dio();
  String? _baseUrl; // Will be set from your API config

  void initialize() {  // Remove baseUrl parameter
    _dio.options.baseUrl = ApiConfig.baseUrl;  // Use ApiConfig.baseUrl
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  // Get auth token (same as your existing screens)
  Future<String?> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  // MAIN METHOD: Get tasks (offline-first)
  Future<List<OfflineTask>> getTasks({bool forceRefresh = false}) async {
    try {
      if (_connectivity.isOnline && forceRefresh) {
        // Try to sync with server first
        await _syncTasksFromServer();
      }

      // Always return local data
      return await _getLocalTasks();
    } catch (e) {
      print('📱 Using offline tasks due to error: $e');
      return await _getLocalTasks();
    }
  }

  // CREATE TASK (works offline)
  Future<OfflineTask> createTask({
    required String title,
    String description = '',
    String priority = 'medium',
    String category = 'general',
    DateTime? dueDate,
  }) async {
    final task = OfflineTask(
      id: _uuid.v4(),
      serverId: null, // Will be set after sync
      title: title,
      description: description,
      priority: priority,
      category: category,
      dueDate: dueDate,
      isCompleted: false,
      progress: 0.0,
      tags: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
      isDeleted: false,
    );

    // Save locally immediately
    await _saveTaskLocally(task);

    // Queue for sync
    await _addToSyncQueue('task', task.id, SyncAction.create, task.toMap());

    // Try immediate sync if online
    if (_connectivity.isOnline) {
      _syncTaskToServer(task).catchError((e) {
        print('⏳ Task queued for sync: $e');
      });
    }

    return task;
  }

  // UPDATE TASK (works offline)
  Future<OfflineTask> updateTask(OfflineTask task) async {
    final updatedTask = task.copyWith(
      syncStatus: SyncStatus.pending,
    );

    // Save locally immediately
    await _saveTaskLocally(updatedTask);

    // Queue for sync
    await _addToSyncQueue('task', task.id, SyncAction.update, updatedTask.toMap());

    // Try immediate sync if online
    if (_connectivity.isOnline) {
      _syncTaskToServer(updatedTask).catchError((e) {
        print('⏳ Task update queued for sync: $e');
      });
    }

    return updatedTask;
  }

  // TOGGLE TASK COMPLETION (works offline)
  Future<OfflineTask> toggleTaskCompletion(String taskId) async {
    final task = await _getLocalTask(taskId);
    if (task == null) throw Exception('Task not found');

    final updatedTask = task.copyWith(
      isCompleted: !task.isCompleted,
      progress: !task.isCompleted ? 1.0 : 0.0,
      syncStatus: SyncStatus.pending,
    );

    // Save locally immediately
    await _saveTaskLocally(updatedTask);

    // Queue for sync
    await _addToSyncQueue('task', taskId, SyncAction.update, updatedTask.toMap());

    // Try immediate sync if online
    if (_connectivity.isOnline) {
      _syncTaskCompletionToServer(updatedTask).catchError((e) {
        print('⏳ Task completion queued for sync: $e');
      });
    }

    return updatedTask;
  }

  // DELETE TASK (works offline)
  Future<void> deleteTask(String taskId) async {
    final task = await _getLocalTask(taskId);
    if (task == null) return;

    final deletedTask = task.copyWith(
      isDeleted: true,
      syncStatus: SyncStatus.pending,
    );

    // Mark as deleted locally
    await _saveTaskLocally(deletedTask);

    // Queue for sync
    await _addToSyncQueue('task', taskId, SyncAction.delete, {'id': taskId});

    // Try immediate sync if online
    if (_connectivity.isOnline) {
      _syncTaskDeletion(taskId).catchError((e) {
        print('⏳ Task deletion queued for sync: $e');
      });
    }
  }

  // SYNC METHODS (Direct HTTP calls like your existing code)
  Future<void> _syncTasksFromServer() async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) return;

      // Same HTTP call as your tasks_screen.dart
      final response = await _dio.get(
        '/api/tasks/pending', // Adjust endpoint based on your backend
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final tasks = response.data['data'] as List;

        // Convert and save to local database
        for (final serverTask in tasks) {
          final offlineTask = _convertServerTaskToOfflineTask(serverTask);
          await _saveTaskLocally(offlineTask.copyWith(syncStatus: SyncStatus.synced));
        }
      }
    } catch (e) {
      print('🔄 Server sync failed: $e');
    }
  }

  Future<void> _syncTaskToServer(OfflineTask task) async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('No auth token');

      // Same HTTP call as your existing task creation
      final response = await _dio.post(
        '/api/tasks/create', // Adjust endpoint based on your backend
        data: {
          'title': task.title,
          'description': task.description,
          'priority': task.priority,
          'category': task.category,
          'due_date': task.dueDate?.toIso8601String(),
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        // Update local task with server ID and mark as synced
        final syncedTask = OfflineTask(
          id: task.id,
          serverId: response.data['data']['task_id']?.toString(),
          title: task.title,
          description: task.description,
          priority: task.priority,
          category: task.category,
          dueDate: task.dueDate,
          isCompleted: task.isCompleted,
          progress: task.progress,
          tags: task.tags,
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
          syncStatus: SyncStatus.synced,
          conflictData: null,
          isDeleted: task.isDeleted,
        );

        await _saveTaskLocally(syncedTask);
        await _removeFromSyncQueue('task', task.id, SyncAction.create);
      }
    } catch (e) {
      print('❌ Sync failed, keeping in queue: $e');
      rethrow;
    }
  }

  Future<void> _syncTaskCompletionToServer(OfflineTask task) async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('No auth token');

      // Same HTTP call as your existing task completion toggle
      final response = await _dio.put(
        '/api/tasks/${task.serverId ?? task.id}/completion', // Adjust endpoint
        data: {
          'is_completed': task.isCompleted,
          'progress': task.progress,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Mark as synced
        final syncedTask = task.copyWith(syncStatus: SyncStatus.synced);
        await _saveTaskLocally(syncedTask);
        await _removeFromSyncQueue('task', task.id, SyncAction.update);
      }
    } catch (e) {
      print('❌ Completion sync failed: $e');
      rethrow;
    }
  }

  Future<void> _syncTaskDeletion(String taskId) async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('No auth token');

      final task = await _getLocalTask(taskId);
      final serverTaskId = task?.serverId ?? taskId;

      // Same HTTP call as your existing task deletion
      final response = await _dio.delete(
        '/api/tasks/$serverTaskId', // Adjust endpoint
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Remove from local database
        final db = await _db.database;
        await db.delete('tasks', where: 'id = ?', whereArgs: [taskId]);

        await _removeFromSyncQueue('task', taskId, SyncAction.delete);
      }
    } catch (e) {
      print('❌ Delete sync failed: $e');
      rethrow;
    }
  }

  // LOCAL DATABASE METHODS
  Future<List<OfflineTask>> _getLocalTasks() async {
    final db = await _db.database;
    final maps = await db.query(
      'tasks',
      where: 'is_deleted = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => OfflineTask.fromMap(map)).toList();
  }

  Future<OfflineTask?> _getLocalTask(String taskId) async {
    final db = await _db.database;
    final maps = await db.query(
      'tasks',
      where: 'id = ? AND is_deleted = ?',
      whereArgs: [taskId, 0],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return OfflineTask.fromMap(maps.first);
    }
    return null;
  }

  Future<void> _saveTaskLocally(OfflineTask task) async {
    final db = await _db.database;
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // SYNC QUEUE METHODS
  Future<void> _addToSyncQueue(
      String entityType,
      String entityId,
      SyncAction action,
      Map<String, dynamic> data,
      ) async {
    final db = await _db.database;

    final syncItem = SyncQueueItem(
      entityType: entityType,
      entityId: entityId,
      action: action,
      data: data,
      createdAt: DateTime.now(),
      retryCount: 0,
    );

    await db.insert('sync_queue', syncItem.toMap());
  }

  Future<void> _removeFromSyncQueue(
      String entityType,
      String entityId,
      SyncAction action,
      ) async {
    final db = await _db.database;
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ? AND action = ?',
      whereArgs: [entityType, entityId, action.name],
    );
  }

  // CONVERSION HELPERS
  OfflineTask _convertServerTaskToOfflineTask(Map<String, dynamic> serverTask) {
    return OfflineTask(
      id: _uuid.v4(), // Generate new local ID
      serverId: serverTask['id']?.toString(),
      title: serverTask['title'] ?? '',
      description: serverTask['description'] ?? '',
      priority: serverTask['priority'] ?? 'medium',
      category: serverTask['category'] ?? 'general',
      dueDate: serverTask['due_date'] != null ? DateTime.parse(serverTask['due_date']) : null,
      isCompleted: serverTask['is_completed'] == 1 || serverTask['is_completed'] == true,
      progress: (serverTask['progress'] ?? 0.0).toDouble(),
      tags: serverTask['tags'] is List ? List<String>.from(serverTask['tags']) : [],
      createdAt: DateTime.parse(serverTask['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(serverTask['updated_at'] ?? DateTime.now().toIso8601String()),
      syncStatus: SyncStatus.synced,
      isDeleted: false,
    );
  }

  // PUBLIC SYNC METHOD
  Future<void> syncPendingTasks() async {
    if (!_connectivity.isOnline) {
      print('📱 Offline: Skipping task sync');
      return;
    }

    final db = await _db.database;
    final pendingSync = await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: ['task'],
    );

    for (final item in pendingSync) {
      final syncItem = SyncQueueItem.fromMap(item);

      try {
        switch (syncItem.action) {
          case SyncAction.create:
          case SyncAction.update:
            final taskData = syncItem.data;
            final task = OfflineTask.fromMap(taskData);
            await _syncTaskToServer(task);
            break;
          case SyncAction.delete:
            await _syncTaskDeletion(syncItem.entityId);
            break;
        }
      } catch (e) {
        print('❌ Failed to sync ${syncItem.action} for task ${syncItem.entityId}: $e');
      }
    }
  }

  // 📊 HELPER METHODS for UI
  Future<int> getPendingSyncCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue WHERE entity_type = ?',
      ['task'],
    );
    return result.first['count'] as int;
  }

  Stream<List<OfflineTask>> watchTasks() async* {
    // For real-time updates in UI
    while (true) {
      yield await _getLocalTasks();
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
