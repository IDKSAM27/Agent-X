import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/database/database_helper.dart';
import '../core/config/api_config.dart';
import '../widgets/sync_loading_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));
  
  // Stream controller for connectivity status
  final StreamController<bool> _onlineStatusController = StreamController<bool>.broadcast();
  Stream<bool> get onlineStatusStream => _onlineStatusController.stream;
  
  bool _isOnline = false;
  bool get isOnline => _isOnline;
  bool _isSyncing = false;
  
  // Map to track temporary session IDs to real backend IDs during sync
  final Map<int, int> _tempSessionIdMap = {};

  void initialize() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // Check if any result is not none
      bool isConnected = results.any((result) => result != ConnectivityResult.none);
      _updateConnectionStatus(isConnected);
    });
    
    // Initial check
    Connectivity().checkConnectivity().then((results) {
       bool isConnected = results.any((result) => result != ConnectivityResult.none);
      _updateConnectionStatus(isConnected);
    });
  }

  void _updateConnectionStatus(bool isConnected) {
    if (_isOnline != isConnected) {
      _isOnline = isConnected;
      _onlineStatusController.add(_isOnline);
      if (_isOnline) {
        // Auto-sync when coming online
        syncData();
      }
    }
  }

  Future<void> syncData({BuildContext? context}) async {
    if (!_isOnline || _isSyncing) return;

    _isSyncing = true;
    
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const SyncLoadingDialog(),
      );
    }

    try {
      await _processSyncQueue();
      // After pushing local changes, pull latest data
      // Note: In a real app, you might want to be more selective or use a sync timestamp
      // For now, we'll rely on the screens to refresh data, or we could trigger a refresh here
      
    } catch (e) {
      print('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
      if (context != null && context.mounted) {
        Navigator.of(context).pop(); // Close dialog
      }
    }
  }

  Future<void> _processSyncQueue() async {
    _tempSessionIdMap.clear(); // Clear map at start of sync cycle
    final queue = await _dbHelper.getSyncQueue();
    if (queue.isEmpty) return;

    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return;

    for (final item in queue) {
      try {
        final entityType = item['entity_type'];
        final operation = item['operation'];
        final payload = jsonDecode(item['payload']);
        final id = item['id'];

        bool success = false;

        if (entityType == 'task') {
          success = await _syncTask(operation, payload, token);
        } else if (entityType == 'event') {
          success = await _syncEvent(operation, payload, token);
        } else if (entityType == 'message') {
          success = await _syncMessage(operation, payload, token);
        } else if (entityType == 'chat_session') {
          success = await _syncSession(operation, payload, token);
        }

        if (success) {
          await _dbHelper.removeFromSyncQueue(id);
        }
      } catch (e) {
        print('❌ Error processing sync item ${item['id']}: $e');
        // Continue to next item
      }
    }
  }

  Future<bool> _syncTask(String operation, Map<String, dynamic> data, String token) async {
    try {
      if (operation == 'create') {
        // Remove local ID before sending to server if server assigns IDs
        // But here we might want to keep the UUID if backend supports it, 
        // or update local DB with server ID after response.
        // For simplicity, let's assume we send the data and backend handles it.
        // We might need to handle ID mapping if backend generates a new ID.
        
        // Adjust payload for backend
        final backendPayload = {
          'title': data['title'],
          'description': data['description'],
          'priority': data['priority'],
          'category': data['category'],
          'due_date': data['due_date'],
          // 'id': data['id'] // If backend accepts client-generated IDs
        };

        await _dio.post(
          '/api/tasks',
          data: backendPayload,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return true;
      }
      // Implement update/delete similarly
      return true;
    } catch (e) {
      print('Failed to sync task: $e');
      return false;
    }
  }

  Future<bool> _syncEvent(String operation, Map<String, dynamic> data, String token) async {
    try {
      if (operation == 'create') {
         final backendPayload = {
          'title': data['title'],
          'description': data['description'],
          'start_time': data['start_time'],
          'end_time': data['end_time'],
          'category': data['category'],
          'is_all_day': data['is_all_day'] == 1,
        };
        
        await _dio.post(
          '/api/events',
          data: backendPayload,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return true;
      }
      return true;
    } catch (e) {
      print('Failed to sync event: $e');
      return false;
    }
  }
  Future<bool> _syncMessage(String operation, Map<String, dynamic> data, String token) async {
    try {
      if (operation == 'create') {
        // Handle temporary session IDs
        int? sessionId = data['session_id'];
        if (sessionId != null && sessionId < 0) {
          if (_tempSessionIdMap.containsKey(sessionId)) {
            sessionId = _tempSessionIdMap[sessionId];
          } else {
            sessionId = null; // Let backend create new session
          }
        }

        final response = await _dio.post(
          '/api/agents/process',
          data: {
            'message': data['content'],
            'user_id': data['user_id'],
            'context': data['context'],
            'timestamp': data['timestamp'],
            'session_id': sessionId,
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );

        if (response.statusCode == 200) {
          final responseData = response.data;
          
          // Handle new session creation from backend
          final int? newSessionId = responseData['session_id'];
          final int? originalTempId = data['session_id'];
          
          if (newSessionId != null && originalTempId != null && originalTempId < 0) {
            _tempSessionIdMap[originalTempId] = newSessionId;
            
            // Update local DB: Replace temp session with real session
            // 1. Create new session row with real ID (if not exists)
            // We need to fetch the temp session details first to copy them
            final tempSessions = await _dbHelper.queryAllRows('chat_sessions');
            final tempSession = tempSessions.firstWhere((s) => s['id'] == originalTempId, orElse: () => {});
            
            if (tempSession.isNotEmpty) {
              await _dbHelper.insert('chat_sessions', {
                'id': newSessionId,
                'title': tempSession['title'],
                'created_at': tempSession['created_at'],
                'profession': tempSession['profession'],
                'is_synced': 1,
              });
              
              // 2. Update all messages (including this one and others) to use new session ID
              // We can't easily update all messages in one go if we don't have a batch update helper
              // But we can execute raw SQL or iterate.
              // For now, let's just update the messages we know about or all messages with temp ID
              // Since we don't have a direct method to execute raw SQL for update, we might need to add one or use what we have.
              // _dbHelper.update uses ID.
              // We need to update by session_id.
              // Let's assume we can't easily do bulk update without adding a method.
              // But we can query messages with temp ID and update them one by one.
              final messages = await _dbHelper.queryAllRows('chat_messages');
              final tempMessages = messages.where((m) => m['session_id'] == originalTempId).toList();
              
              for (var msg in tempMessages) {
                await _dbHelper.update('chat_messages', {
                  'id': msg['id'],
                  'session_id': newSessionId,
                  'is_synced': 1, // Mark as synced as well if this was the sync action
                }, 'id');
              }
              
              // 3. Delete temp session
              await _dbHelper.delete('chat_sessions', originalTempId.toString());
            }
          }

          final assistantMessage = ChatMessage(
            id: const Uuid().v4(),
            content: responseData['response'],
            type: MessageType.assistant,
            timestamp: DateTime.now(),
            metadata: responseData['metadata'],
          );

          // Save assistant response to local DB
          await _dbHelper.insert('chat_messages', {
            'id': assistantMessage.id,
            'session_id': newSessionId ?? sessionId ?? data['session_id'],
            'content': assistantMessage.content,
            'type': 'assistant',
            'timestamp': assistantMessage.timestamp.toIso8601String(),
            'is_synced': 1,
          });
          
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Failed to sync message: $e');
      return false;
    }
  }

  Future<bool> _syncSession(String operation, Map<String, dynamic> data, String token) async {
    try {
      if (operation == 'update') {
        await _dio.patch(
          '/api/chats/${data['id']}',
          data: {'title': data['title']},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return true;
      } else if (operation == 'delete') {
        await _dio.delete(
          '/api/chats/${data['id']}',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return true;
      }
      return true;
    } catch (e) {
      print('Failed to sync session: $e');
      return false;
    }
  }
}
