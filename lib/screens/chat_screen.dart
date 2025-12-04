import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/app_constants.dart';
import '../core/config/api_config.dart';
import '../widgets/enhanced_chat_bubble.dart';
import '../models/chat_message.dart';
import '../core/database/database_helper.dart';
import '../services/sync_service.dart';

class ChatScreen extends StatefulWidget {
  final String profession;

  const ChatScreen({
    super.key,
    this.profession = 'General',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  final Dio dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _sessions = [];
  dynamic _currentSessionId; // Can be int (backend) or int (local negative)
  
  bool _isLoading = false;
  bool _isLoadingSessions = false;
  bool _isTyping = false;
  bool _isOnline = false;
  StreamSubscription<bool>? _onlineStatusSubscription;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _onlineStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    _syncService.initialize();
    _isOnline = _syncService.isOnline;
    
    _onlineStatusSubscription = _syncService.onlineStatusStream.listen((isOnline) {
      if (mounted) {
        setState(() => _isOnline = isOnline);
        if (isOnline) {
          _fetchSessions();
        }
      }
    });

    await _fetchSessions();
    
    // If we have sessions, load the most recent one
    if (_sessions.isNotEmpty) {
      await _loadSession(_sessions.first['id']);
    } else {
      _createNewChat();
    }
  }

  // --- Session Management ---

  Future<void> _fetchSessions() async {
    setState(() => _isLoadingSessions = true);
    
    // 1. Load from local DB first
    await _loadSessionsFromLocal();

    if (!_isOnline) {
      setState(() => _isLoadingSessions = false);
      return;
    }

    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.get(
        '/api/chats',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final sessions = List<Map<String, dynamic>>.from(response.data['sessions']);
        
        // 2. Update local DB with remote data
        for (var session in sessions) {
           await _dbHelper.insert('chat_sessions', {
            'id': session['id'],
            'title': session['title'],
            'created_at': session['created_at'],
            'profession': widget.profession,
          });
        }
        
        // 3. Reload from local DB
        await _loadSessionsFromLocal();
      }
    } catch (e) {
      print('❌ Error fetching sessions: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSessions = false);
    }
  }

  Future<void> _loadSessionsFromLocal() async {
    final localSessions = await _dbHelper.queryAllRows('chat_sessions');
    if (!mounted) return;
    
    setState(() {
      _sessions = localSessions.map((s) => {
        'id': s['id'],
        'title': s['title'],
        'created_at': s['created_at'],
      }).toList();
      
      _sessions.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at'].toString()) ?? DateTime.now();
        final bDate = DateTime.tryParse(b['created_at'].toString()) ?? DateTime.now();
        return bDate.compareTo(aDate);
      });
    });
  }

  Future<void> _loadSession(dynamic sessionId) async {
    if (_currentSessionId == sessionId) return;

    setState(() {
      _currentSessionId = sessionId;
      _messages.clear();
      _isLoading = true;
    });
    
    await _loadMessagesFromLocal(sessionId);

    if (!_isOnline) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.get(
        '/api/chats/$sessionId/messages',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final List<dynamic> messagesData = response.data['messages'];
        
        await _dbHelper.deleteSyncedSessionMessages(sessionId);

        for (var msg in messagesData) {
          final userMsg = ChatMessage(
            id: '${msg['id']}_user',
            content: msg['user_message'],
            type: MessageType.user,
            timestamp: DateTime.parse(msg['timestamp']),
          );
          
          await _dbHelper.insert('chat_messages', {
            'id': userMsg.id,
            'session_id': sessionId,
            'content': userMsg.content,
            'type': 'user',
            'timestamp': userMsg.timestamp.toIso8601String(),
            'is_synced': 1,
          });

          final assistantMsg = ChatMessage(
            id: '${msg['id']}_assistant',
            content: msg['assistant_response'],
            type: MessageType.assistant,
            timestamp: DateTime.parse(msg['timestamp']),
            metadata: msg['metadata'],
          );
          
          await _dbHelper.insert('chat_messages', {
            'id': assistantMsg.id,
            'session_id': sessionId,
            'content': assistantMsg.content,
            'type': 'assistant',
            'timestamp': assistantMsg.timestamp.toIso8601String(),
            'is_synced': 1,
          });
        }
        
        await _loadMessagesFromLocal(sessionId);
      }
    } catch (e) {
      print('❌ Error loading session: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMessagesFromLocal(dynamic sessionId) async {
    final localMessages = await _dbHelper.queryAllRows('chat_messages');
    final sessionMessages = localMessages.where((m) => m['session_id'] == sessionId).toList();
    
    if (sessionMessages.isNotEmpty) {
      final List<ChatMessage> loadedMessages = sessionMessages.map((m) => ChatMessage(
        id: m['id'].toString(),
        content: m['content'],
        type: m['type'] == 'user' ? MessageType.user : MessageType.assistant,
        timestamp: DateTime.parse(m['timestamp']),
        status: m['is_synced'] == 1 ? MessageStatus.sent : MessageStatus.sending,
      )).toList();
      
      loadedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      if (mounted) {
        setState(() {
          _messages = loadedMessages;
        });
        _scrollToBottom();
      }
    } else if (mounted) {
      setState(() => _messages.clear());
      _addWelcomeMessage();
    }
  }

  void _createNewChat() {
    setState(() {
      _currentSessionId = null;
      _messages.clear();
      _addWelcomeMessage();
    });
  }

  Future<void> _deleteSession(dynamic sessionId) async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete Chat',
      content: 'Are you sure you want to delete this chat?',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (!confirmed) return;

    await _dbHelper.delete('chat_sessions', sessionId.toString());
    
    setState(() {
      _sessions.removeWhere((s) => s['id'] == sessionId);
      if (_currentSessionId == sessionId) {
        _createNewChat();
      }
    });

    if (!_isOnline) {
      await _dbHelper.addToSyncQueue(
        'chat_session',
        'delete',
        sessionId.toString(),
        jsonEncode({'id': sessionId}),
      );
      _showInfoSnackBar('Chat deleted offline. Will sync when online.');
      return;
    }

    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.delete(
        '/api/chats/$sessionId',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode != 200 || response.data['status'] != 'success') {
         _showErrorMessage('Failed to delete chat on server');
      }
    } catch (e) {
      print('❌ Error deleting session: $e');
      _showErrorMessage('Failed to delete chat');
    }
  }

  Future<void> _renameSession(dynamic sessionId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter new chat name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == currentTitle) return;

    await _dbHelper.update('chat_sessions', {
      'id': sessionId,
      'title': newTitle,
    }, 'id');

    setState(() {
      final index = _sessions.indexWhere((s) => s['id'] == sessionId);
      if (index != -1) {
        _sessions[index]['title'] = newTitle;
      }
    });

    if (!_isOnline) {
      await _dbHelper.addToSyncQueue(
        'chat_session',
        'update',
        sessionId.toString(),
        jsonEncode({'id': sessionId, 'title': newTitle}),
      );
      _showInfoSnackBar('Chat renamed offline. Will sync when online.');
      return;
    }

    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.patch(
        '/api/chats/$sessionId',
        data: {'title': newTitle},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        _showSuccessSnackBar('Chat renamed successfully');
      }
    } catch (e) {
      print('❌ Error renaming session: $e');
      _showErrorMessage('Failed to rename chat');
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isTyping) return;

    HapticFeedback.lightImpact();

    final userMessage = ChatMessage(
      id: const Uuid().v4(),
      content: text,
      type: MessageType.user,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
    });

    _controller.clear();
    _scrollToBottom();
    
    // Handle new session creation
    if (_currentSessionId == null) {
      if (!_isOnline) {
        final tempId = -DateTime.now().millisecondsSinceEpoch;
        _currentSessionId = tempId;
        
        await _dbHelper.insert('chat_sessions', {
          'id': tempId,
          'title': 'New Chat',
          'created_at': DateTime.now().toIso8601String(),
          'profession': widget.profession,
        });
        
        setState(() {
          _sessions.insert(0, {
            'id': tempId,
            'title': 'New Chat',
            'created_at': DateTime.now().toIso8601String(),
          });
        });
      }
    }

    if (_currentSessionId != null) {
      await _dbHelper.insert('chat_messages', {
        'id': userMessage.id,
        'session_id': _currentSessionId,
        'content': userMessage.content,
        'type': 'user',
        'timestamp': userMessage.timestamp.toIso8601String(),
        'is_synced': _isOnline ? 1 : 0,
      });
    }

    if (!_isOnline) {
      setState(() {
        _isTyping = false;
        final index = _messages.indexWhere((m) => m.id == userMessage.id);
        if (index != -1) {
          _messages[index] = userMessage.copyWith(status: MessageStatus.sent);
        }
        
        _messages.add(ChatMessage(
          id: const Uuid().v4(),
          content: "I'm offline right now. I'll process your message when I'm back online.",
          type: MessageType.assistant,
          timestamp: DateTime.now(),
        ));
      });
      _scrollToBottom();
      
      await _dbHelper.addToSyncQueue(
        'message',
        'create',
        userMessage.id,
        jsonEncode({
          'content': text,
          'user_id': _getCurrentUserId(),
          'context': {'profession': widget.profession},
          'timestamp': userMessage.timestamp.toIso8601String(),
          'session_id': _currentSessionId,
        }),
      );
      return;
    }

    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) throw Exception('Not authenticated');

      final response = await dio.post(
        '/api/agents/process',
        data: {
          'message': text,
          'user_id': _getCurrentUserId(),
          'context': {'profession': widget.profession},
          'timestamp': DateTime.now().toIso8601String(),
          'session_id': _currentSessionId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      final data = response.data;
      
      if (_currentSessionId == null && data['session_id'] != null) {
        setState(() {
          _currentSessionId = data['session_id'];
        });
        _fetchSessions();
        
        await _dbHelper.insert('chat_messages', {
          'id': userMessage.id,
          'session_id': _currentSessionId,
          'content': userMessage.content,
          'type': 'user',
          'timestamp': userMessage.timestamp.toIso8601String(),
          'is_synced': 1,
        });
      }

      final assistantMessage = ChatMessage(
        id: const Uuid().v4(),
        content: data['response'],
        type: MessageType.assistant,
        timestamp: DateTime.now(),
        metadata: data['metadata'],
      );

      if (mounted) {
        setState(() {
          _messages.add(assistantMessage);
          _isTyping = false;
        });
      }
      
      if (_currentSessionId != null) {
        await _dbHelper.insert('chat_messages', {
          'id': assistantMessage.id,
          'session_id': _currentSessionId,
          'content': assistantMessage.content,
          'type': 'assistant',
          'timestamp': assistantMessage.timestamp.toIso8601String(),
          'is_synced': 1,
        });
      }

      _scrollToBottom();

    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          final index = _messages.indexWhere((m) => m.id == userMessage.id);
          if (index != -1) {
            _messages[index] = userMessage.copyWith(status: MessageStatus.failed);
          }
        });
        _showErrorMessage('Failed to send message. Please try again.');
      }
      print('Send message error: $e');
    }
  }

  void _addWelcomeMessage() {
    if (_messages.isEmpty) {
      _messages.add(ChatMessage(
        id: 'welcome',
        content: "Hello! I'm your ${widget.profession} assistant. How can I help you today?",
        type: MessageType.assistant,
        timestamp: DateTime.now(),
      ));
    }
  }

  // --- Helpers ---

  Future<String?> _getFirebaseIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }

  String _getCurrentUserId() {
    return _auth.currentUser?.uid ?? 'unknown';
  }

  String _getCurrentUserEmail() {
    return _auth.currentUser?.email ?? 'unknown';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    required bool isDestructive,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDestructive ? TextButton.styleFrom(foregroundColor: Colors.red) : null,
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showExportDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat Export'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total Messages: ${data['total_messages']}'),
              const SizedBox(height: 8),
              const Text('Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  jsonEncode(data['conversations'].take(2).toList()),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              // In a real app, this would save to file or share
              Navigator.pop(context);
              _showSuccessSnackBar('Export saved to Downloads (simulated)');
            },
            icon: const Icon(Icons.download),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- Memory & Options ---

  Future<void> _showMemoryStatus() async {
    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.get(
        '/debug/data_status/${_auth.currentUser!.uid}',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (mounted && response.statusCode == 200) {
        final data = response.data;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Memory Status'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInfoRow('Total Conversations', '${data['conversations_count']}'),
                  _buildInfoRow('Total Tasks', '${data['tasks_count']}'),
                  _buildInfoRow('Total Events', '${data['events_count']}'),
                  const SizedBox(height: 16),
                  const Text('Recent Activity:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    jsonEncode(data['recent_activity']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorMessage('Failed to fetch memory status');
    }
  }

  Future<void> _clearMemory() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear All Data',
      content: 'This will permanently delete ALL your conversations, tasks, and events. This action cannot be undone.',
      confirmText: 'Clear All Data',
      isDestructive: true,
    );

    if (!confirmed) return;

    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.post(
        '/api/clear_memory',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200) {
        // Clear local DB
        await _dbHelper.clearAllTables();
        
        setState(() {
          _messages.clear();
          _sessions.clear();
          _currentSessionId = null;
        });
        
        _showSuccessSnackBar('All data cleared successfully');
        _createNewChat();
      }
    } catch (e) {
      _showErrorMessage('Failed to clear data');
    }
  }

  Future<void> _exportChat() async {
    try {
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) return;

      final response = await dio.post(
        '/api/export_chat',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (mounted && response.statusCode == 200) {
        final data = response.data['data'];
        _showExportDialog(data);
      }
    } catch (e) {
      _showErrorMessage('Failed to export chat');
    }
  }

  Future<void> _clearCurrentChat() async {
    if (_currentSessionId == null) return;

    final confirmed = await _showConfirmDialog(
      title: 'Clear Chat',
      content: 'This will clear all messages in the current session.',
      confirmText: 'Clear',
      isDestructive: true,
    );

    if (!confirmed) return;

    // Clear locally
    await _dbHelper.deleteSyncedSessionMessages(_currentSessionId);
    
    setState(() {
      _messages.clear();
      _addWelcomeMessage();
    });

    // If online, we might want to sync this clearing, but backend doesn't have "clear messages" endpoint yet.
    // We can just rely on local clear for now or implement backend support later.
    // For now, this is a local-first action.
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildMessagesList(),
          ),
          const Divider(height: 1),
          _buildInputSection(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: Column(
        children: [
          const Text('Agent X', style: TextStyle(fontWeight: FontWeight.bold)),
          if (!_isOnline)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 12, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 4),
                Text('Offline', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
              ],
            ),
          Text(
            '${widget.profession} Assistant',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'memory':
                _showMemoryStatus();
                break;
              case 'export':
                _exportChat();
                break;
              case 'clear_chat':
                _clearCurrentChat();
                break;
              case 'clear_all':
                _clearMemory();
                break;
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'memory',
              child: Row(
                children: [
                  Icon(Icons.memory, size: 20),
                  SizedBox(width: 8),
                  Text('Memory Status'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.download, size: 20),
                  SizedBox(width: 8),
                  Text('Export Chat'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.cleaning_services, size: 20),
                  SizedBox(width: 8),
                  Text('Clear Chat'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'clear_all',
              child: Row(
                children: [
                  Icon(Icons.delete_forever, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Clear All Data', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showChatOptions(BuildContext context, dynamic sessionId, String currentTitle) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _renameSession(sessionId, currentTitle);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteSession(sessionId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerTextColor = isDark ? Colors.black87 : Colors.white;

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              _auth.currentUser?.displayName ?? 'User',
              style: TextStyle(color: headerTextColor, fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(
              _auth.currentUser?.email ?? '',
              style: TextStyle(color: headerTextColor),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundImage: _auth.currentUser?.photoURL != null
                  ? CachedNetworkImageProvider(_auth.currentUser!.photoURL!)
                  : null,
              child: _auth.currentUser?.photoURL == null
                  ? Text((_auth.currentUser?.displayName ?? 'U')[0].toUpperCase())
                  : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.blue),
            title: const Text('New Chat', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              _createNewChat();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoadingSessions
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final isSelected = session['id'] == _currentSessionId;
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        selected: isSelected,
                        title: Text(
                          session['title'] ?? 'New Chat',
                          style: const TextStyle(fontSize: 15),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _loadSession(session['id']);
                        },
                        onLongPress: () {
                          _showChatOptions(context, session['id'], session['title'] ?? 'New Chat');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Start a conversation!',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return EnhancedChatBubble(
          message: _messages[index],
          showAvatar: index == 0 || _messages[index].type != _messages[index - 1].type,
        );
      },
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _isTyping 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
            onPressed: _isTyping ? null : _sendMessage,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
