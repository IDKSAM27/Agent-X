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

  // --- Message Handling ---

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
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: _createNewChat,
          tooltip: 'New Chat',
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_auth.currentUser?.displayName ?? 'User'),
            accountEmail: Text(_auth.currentUser?.email ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundImage: _auth.currentUser?.photoURL != null
                  ? CachedNetworkImageProvider(_auth.currentUser!.photoURL!)
                  : null,
              child: _auth.currentUser?.photoURL == null
                  ? Text((_auth.currentUser?.displayName ?? 'U')[0].toUpperCase())
                  : null,
            ),
          ),
          Expanded(
            child: _isLoadingSessions
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final isSelected = session['id'] == _currentSessionId;
                      return ListTile(
                        selected: isSelected,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(session['title'] ?? 'New Chat'),
                        onTap: () {
                          Navigator.pop(context);
                          _loadSession(session['id']);
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
