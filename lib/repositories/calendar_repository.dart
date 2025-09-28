import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../core/models/offline_models.dart';
import '../core/services/connectivity_service.dart';
import '../core/config/api_config.dart';

class CalendarRepository {
  static final CalendarRepository _instance = CalendarRepository._internal();
  factory CalendarRepository() => _instance;
  CalendarRepository._internal();

  final DatabaseHelper _db = DatabaseHelper();
  final ConnectivityService _connectivity = ConnectivityService();
  final Uuid _uuid = const Uuid();
  final Dio _dio = Dio();

  void initialize() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  Future<String?> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  // GET EVENTS (offline-first)
  Future<List<OfflineEvent>> getEvents({bool forceRefresh = false}) async {
    try {
      if (_connectivity.isOnline && forceRefresh) {
        await _syncEventsFromServer();
      }

      return await _getLocalEvents();
    } catch (e) {
      print('📱 Using offline events due to error: $e');
      return await _getLocalEvents();
    }
  }

  // GET EVENTS FOR DATE RANGE
  Future<List<OfflineEvent>> getEventsForDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final maps = await db.query(
      'events',
      where: 'start_time >= ? AND start_time <= ? AND is_deleted = ?',
      whereArgs: [
        startDate.toIso8601String(),
        endDate.toIso8601String(),
        0,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => OfflineEvent.fromMap(map)).toList();
  }

  // CREATE EVENT (works offline)
  Future<OfflineEvent> createEvent({
    required String title,
    String description = '',
    required DateTime startTime,
    DateTime? endTime,
    String category = 'general',
    String priority = 'medium',
    String? location,
  }) async {
    final event = OfflineEvent(
      id: _uuid.v4(),
      serverId: null,
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      category: category,
      priority: priority,
      location: location,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
      isDeleted: false,
    );

    await _saveEventLocally(event);
    await _addToSyncQueue('event', event.id, SyncAction.create, event.toMap());

    if (_connectivity.isOnline) {
      _syncEventToServer(event).catchError((e) {
        print('⏳ Event queued for sync: $e');
      });
    }

    return event;
  }

  // UPDATE EVENT (works offline)
  Future<OfflineEvent> updateEvent(OfflineEvent event) async {
    final updatedEvent = event.copyWith(syncStatus: SyncStatus.pending);

    await _saveEventLocally(updatedEvent);
    await _addToSyncQueue('event', event.id, SyncAction.update, updatedEvent.toMap());

    if (_connectivity.isOnline) {
      _syncEventToServer(updatedEvent).catchError((e) {
        print('⏳ Event update queued for sync: $e');
      });
    }

    return updatedEvent;
  }

  // DELETE EVENT (works offline)
  Future<void> deleteEvent(String eventId) async {
    final event = await _getLocalEvent(eventId);
    if (event == null) return;

    final deletedEvent = event.copyWith(
      isDeleted: true,
      syncStatus: SyncStatus.pending,
    );

    await _saveEventLocally(deletedEvent);
    await _addToSyncQueue('event', eventId, SyncAction.delete, {'id': eventId});

    if (_connectivity.isOnline) {
      _syncEventDeletion(eventId).catchError((e) {
        print('⏳ Event deletion queued for sync: $e');
      });
    }
  }

  // SYNC METHODS
  Future<void> _syncEventsFromServer() async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) return;

      final response = await _dio.get(
        '/api/events', // Adjust endpoint based on your backend
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final events = response.data['data'] as List;

        for (final serverEvent in events) {
          final offlineEvent = _convertServerEventToOfflineEvent(serverEvent);
          await _saveEventLocally(offlineEvent.copyWith(syncStatus: SyncStatus.synced));
        }
      }
    } catch (e) {
      print('🔄 Event sync failed: $e');
    }
  }

  Future<void> _syncEventToServer(OfflineEvent event) async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('No auth token');

      final response = await _dio.post(
        '/api/events/create', // Adjust endpoint
        data: {
          'title': event.title,
          'description': event.description,
          'start_time': event.startTime.toIso8601String(),
          'end_time': event.endTime?.toIso8601String(),
          'category': event.category,
          'priority': event.priority,
          'location': event.location,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final syncedEvent = OfflineEvent(
          id: event.id,
          serverId: response.data['data']['event_id']?.toString(),
          title: event.title,
          description: event.description,
          startTime: event.startTime,
          endTime: event.endTime,
          category: event.category,
          priority: event.priority,
          location: event.location,
          createdAt: event.createdAt,
          updatedAt: event.updatedAt,
          syncStatus: SyncStatus.synced,
          conflictData: null,
          isDeleted: event.isDeleted,
        );

        await _saveEventLocally(syncedEvent);
        await _removeFromSyncQueue('event', event.id, SyncAction.create);
      }
    } catch (e) {
      print('❌ Event sync failed: $e');
      rethrow;
    }
  }

  Future<void> _syncEventDeletion(String eventId) async {
    if (!_connectivity.isOnline) return;

    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('No auth token');

      final event = await _getLocalEvent(eventId);
      final serverEventId = event?.serverId ?? eventId;

      final response = await _dio.delete(
        '/api/events/$serverEventId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final db = await _db.database;
        await db.delete('events', where: 'id = ?', whereArgs: [eventId]);
        await _removeFromSyncQueue('event', eventId, SyncAction.delete);
      }
    } catch (e) {
      print('❌ Event delete sync failed: $e');
      rethrow;
    }
  }

  // LOCAL DATABASE METHODS
  Future<List<OfflineEvent>> _getLocalEvents() async {
    final db = await _db.database;
    final maps = await db.query(
      'events',
      where: 'is_deleted = ?',
      whereArgs: [0],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => OfflineEvent.fromMap(map)).toList();
  }

  Future<OfflineEvent?> _getLocalEvent(String eventId) async {
    final db = await _db.database;
    final maps = await db.query(
      'events',
      where: 'id = ? AND is_deleted = ?',
      whereArgs: [eventId, 0],
      limit: 1,
    );

    return maps.isNotEmpty ? OfflineEvent.fromMap(maps.first) : null;
  }

  Future<void> _saveEventLocally(OfflineEvent event) async {
    final db = await _db.database;
    await db.insert(
      'events',
      event.toMap(),
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
  OfflineEvent _convertServerEventToOfflineEvent(Map<String, dynamic> serverEvent) {
    return OfflineEvent(
      id: _uuid.v4(),
      serverId: serverEvent['id']?.toString(),
      title: serverEvent['title'] ?? '',
      description: serverEvent['description'] ?? '',
      startTime: DateTime.parse(serverEvent['start_time']),
      endTime: serverEvent['end_time'] != null ? DateTime.parse(serverEvent['end_time']) : null,
      category: serverEvent['category'] ?? 'general',
      priority: serverEvent['priority'] ?? 'medium',
      location: serverEvent['location'],
      createdAt: DateTime.parse(serverEvent['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(serverEvent['updated_at'] ?? DateTime.now().toIso8601String()),
      syncStatus: SyncStatus.synced,
      isDeleted: false,
    );
  }

  // PUBLIC SYNC METHOD
  Future<void> syncPendingEvents() async {
    if (!_connectivity.isOnline) {
      print('📱 Offline: Skipping event sync');
      return;
    }

    final db = await _db.database;
    final pendingSync = await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: ['event'],
    );

    for (final item in pendingSync) {
      final syncItem = SyncQueueItem.fromMap(item);

      try {
        switch (syncItem.action) {
          case SyncAction.create:
          case SyncAction.update:
            final eventData = syncItem.data;
            final event = OfflineEvent.fromMap(eventData);
            await _syncEventToServer(event);
            break;
          case SyncAction.delete:
            await _syncEventDeletion(syncItem.entityId);
            break;
        }
      } catch (e) {
        print('❌ Failed to sync ${syncItem.action} for event ${syncItem.entityId}: $e');
      }
    }
  }
}
