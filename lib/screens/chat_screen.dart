import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/app_constants.dart';
import '../core/config/api_config.dart';
import '../models/chat_message.dart';
import '../widgets/enhanced_chat_bubble.dart';
import '../widgets/app_logo.dart';
import '../core/agents/hybrid_orchestrator.dart';
import '../core/database/database_helper.dart';
import '../services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final String profession; // Restored profession parameter

  const ChatScreen({super.key, required this.profession});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Chat Session State
  List<Map<String, dynamic>> _sessions = [];
  int? _currentSessionId;
  bool _isLoadingSessions = false;

  bool _isTyping = false;
  late AnimationController _inputController;
  late Dio dio;
  
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _onlineStatusSubscription;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _inputController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      headers: ApiConfig.defaultHeaders,
    ));

    _addWelcomeMessage();
    
    _syncService.initialize();
    _isOnline = _syncService.isOnline;
    _onlineStatusSubscription = _syncService.onlineStatusStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        if (isOnline) {
          _fetchSessions(); // Refresh sessions when online
        }
      }
    });

    _fetchSessions(); // Fetch sessions on init
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _inputController.dispose();
    _onlineStatusSubscription?.cancel();
    super.dispose();
  }

  void _addWelcomeMessage() {
    final welcomeMessage = ChatMessage(
      id: '0',
      content: "Hello! I'm Agent X, your AI assistant. I'm here to help you with anything related to your profession as a ${widget.profession}. How can I assist you today?", // Uses profession
      type: MessageType.assistant,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(welcomeMessage);
    });
  }

  /// Get Firebase ID token for authentication
  Future<String?> _getFirebaseIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
      return null;
    } catch (e) {
      print('Error getting Firebase ID token: $e');
      return null;
    }
  }

  /// Get current Firebase user ID
  String _getCurrentUserId() {
    return _auth.currentUser?.uid ?? 'anonymous';
  }

  /// Get current user email
  String _getCurrentUserEmail() {
    return _auth.currentUser?.email ?? 'unknown@email.com';
  }

  @override
  Widget build(BuildContext context) {
    final messagesList = _buildMessagesList();
    final inputSection = _buildInputSection();
    final appBar = _buildAppBar();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        resizeToAvoidBottomInset: true, // Enable proper keyboard handling
        drawer: _buildDrawer(), // Added Drawer
        appBar: appBar,
        body: SafeArea( // Wrap in SafeArea
          child: Column(
            children: [
              Expanded(
                child: RepaintBoundary(
                  child: messagesList,
                ),
              ),
              AnimatedContainer( // Tried to make it smoother by using AnimatedContainer
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding: EdgeInsets.all(AppConstants.spacingXXS),
                child: RepaintBoundary(
                    child: inputSection
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }



  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Custom Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                  const AppLogo(size: 40, showShadow: true),
                    const SizedBox(width: 12),
                    Text(
                      'Agent X',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _createNewChat();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Chat'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),

          // Session List
          Expanded(
            child: _isLoadingSessions
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _sessions.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final isSelected = session['id'] == _currentSessionId;
                      return ListTile(
                        leading: Icon(
                          Icons.chat_bubble_outline, 
                          size: 20,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(
                          session['title'] ?? 'New Chat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected ? Theme.of(context).colorScheme.primary : null,
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        onTap: () {
                          Navigator.pop(context);
                          _loadSession(session['id']);
                        },
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, size: 18),
                          onSelected: (value) {
                            if (value == 'rename') {
                              // Close drawer first? No, keep it open or close it?
                              // Better to close drawer to show dialog clearly
                              Navigator.pop(context); 
                              _renameSession(session['id'], session['title'] ?? 'New Chat');
                            } else if (value == 'delete') {
                              Navigator.pop(context);
                              _deleteSession(session['id']);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Rename'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const Divider(height: 1),

          // User Profile Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  backgroundImage: _auth.currentUser?.photoURL != null
                      ? CachedNetworkImageProvider(_auth.currentUser!.photoURL!)
                      : null,
                  child: _auth.currentUser?.photoURL == null
                      ? Text(
                          (_auth.currentUser?.displayName ?? 'U')[0].toUpperCase(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _auth.currentUser?.displayName ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _auth.currentUser?.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,  // Center the entire title content
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,  // Center the Column horizontally
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,  // Center the content vertically
            crossAxisAlignment: CrossAxisAlignment.center, // Center the text horizontally within the column
            children: [
              // "Agent X" Text
              const Text(
                'Agent X',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (!_isOnline) ...[
                const SizedBox(height: 4), // Add spacing between the text and the icon
                Icon(
                  Icons.wifi_off,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
              const SizedBox(height: 4), // Add a little space before the next line
              // AI Assistant Text
              Align(
                alignment: Alignment.center,
                child: Text(
                  '${widget.profession} AI Assistant',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onOpened: () => FocusScope.of(context).unfocus(), // Unfocus when opened
          onCanceled: () {
            // Don't automatically refocus - let user tap input if they want
          },
          onSelected: _handleMenuSelection,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 20),
                  SizedBox(width: 12),
                Text('Clear Chat'),
              ],
            ),
          ),
            const PopupMenuItem(
              value: 'clear_data',
              child: Row(
                children: [
                  Icon(Icons.delete_forever, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Clear Data', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
            const PopupMenuItem(
              value: 'export_chat',
              child: Row(
                children: [
                  Icon(Icons.download, size: 20),
                  SizedBox(width: 12),
                Text('Export Chat'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'memory_debug',
              child: Row(
                children: [
                  Icon(Icons.memory, size: 20),
                  SizedBox(width: 12),
                  Text('Memory Status'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getProfessionIcon(),
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Your ${widget.profession} AI Assistant',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything related to ${widget.profession.toLowerCase()} work, studies, or general questions!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip('Draft an email'),
                _buildSuggestionChip('Explain a concept'),
                _buildSuggestionChip('Debug code'),
                _buildSuggestionChip('Brainstorm ideas'),
              ],
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingM),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return EnhancedChatBubble(
          message: _messages[index],
          showAvatar: index == 0 ||
              _messages[index].type != _messages[index - 1].type,
        );
      },
    );
  }

  Widget _buildSuggestionChip(String label) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.lightbulb_outline, size: 16),
      onPressed: () {
        _controller.text = label;
        _sendMessage();
      },
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
  }

  IconData _getProfessionIcon() {
    switch (widget.profession.toLowerCase()) {
      case 'student':
        return Icons.school;
      case 'engineer':
        return Icons.engineering;
      case 'doctor':
        return Icons.local_hospital;
      case 'teacher':
        return Icons.cast_for_education;
      case 'lawyer':
        return Icons.gavel;
      case 'developer':
        return Icons.code;
      case 'designer':
        return Icons.design_services;
      default:
        return Icons.work;
    }
  }

  Widget _buildInputSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppConstants.spacingM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ask me about ${widget.profession.toLowerCase()} topics...', // Profession-specific hint
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                style: Theme.of(context).textTheme.bodyMedium,
                enabled: !_isTyping,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          _buildSendButton(),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: _isTyping ? null : _sendMessage,
        icon: Icon(
          _isTyping ? Icons.hourglass_empty : Icons.send_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  void _handleMenuSelection(String value) async {
    switch (value) {
      case 'clear_chat':
        await _clearChat();
        break;
      case 'clear_data':
        await _clearAllData();
        break;
      case 'export_chat':
        await _exportChat();
        break;
      case 'memory_debug':
        await _showMemoryStatus();
        break;
    }
  }

  Future<void> _clearChat() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear Chat',
      content: 'This will clear all messages in this chat session. Your memory data will be preserved.',
      confirmText: 'Clear',
      isDestructive: false,
    );

    if (confirmed) {
      setState(() {
        _messages.clear();
        _addWelcomeMessage();
      });

      _showSuccessSnackBar('Chat cleared successfully');
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear All Data',
      content: 'This will permanently delete:\n\n• All chat messages\n• All memory data\n• User preferences\n• Agent context\n\nThis action cannot be undone!',
      confirmText: 'Delete All',
      isDestructive: true,
    );

    if (confirmed) {
      try {
        setState(() {
          _messages.clear();
          _isTyping = false;
        });

        // Get Firebase ID token for authentication
        final idToken = await _getFirebaseIdToken();
        if (idToken == null) {
          _showErrorMessage('Authentication required. Please sign in again.');
          return;
        }

        final response = await dio.post(
          '/api/clear_memory',
          options: Options(
            headers: {
              'Authorization': 'Bearer $idToken',
            },
          ),
        );

        if (response.statusCode == 200 && response.data['status'] == 'success') {
          _addWelcomeMessage();
          _showSuccessSnackBar('All data cleared successfully');
          print('✅ Cleared data: ${response.data['deleted_counts']}');
        } else {
          _showErrorMessage('Failed to clear backend data: ${response.data['message']}');
        }
      } catch (e) {
        print('❌ Clear data error: $e');
        if (e is DioException && e.response?.statusCode == 403) {
          _showErrorMessage('Authentication failed. Please sign in again.');
        } else {
          _showErrorMessage('Failed to clear data: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _exportChat() async {
    try {
      _showInfoSnackBar('Preparing chat export...');

      // Get Firebase ID token for authentication
      final idToken = await _getFirebaseIdToken();
      if (idToken == null) {
        _showErrorMessage('Authentication required. Please sign in again.');
        return;
      }

      final response = await dio.post(
        '/api/export_chat',
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final exportData = response.data['data'];
        await _showExportDialog(exportData);
      } else {
        _showErrorMessage('Failed to export: ${response.data['message']}');
      }
    } catch (e) {
      print('❌ Export error: $e');
      if (e is DioException && e.response?.statusCode == 403) {
        _showErrorMessage('Authentication failed. Please sign in again.');
      } else {
        _showErrorMessage('Export failed: ${e.toString()}');
      }
    }
  }

  Future<void> _showMemoryStatus() async {
    try {
      final currentUserId = _getCurrentUserId();

      // Get Firebase ID token for authentication (if the endpoint requires it)
      final idToken = await _getFirebaseIdToken();
      final options = idToken != null ? Options(
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      ) : null;

      final response = await dio.get(
        '/api/memory/debug/$currentUserId',
        options: options,
      );

      if (response.statusCode == 200) {
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
                  _buildInfoRow('Firebase UID', currentUserId),
                  _buildInfoRow('Email', _getCurrentUserEmail()),
                  _buildInfoRow('Profession', widget.profession),
                  _buildInfoRow('Total Conversations', '${data['total_conversations'] ?? 0}'),
                  _buildInfoRow('Latest Conversation', '${data['latest_conversation'] ?? 'None'}'),
                  _buildInfoRow('Latest Intent', '${data['latest_intent'] ?? 'None'}'),
                  _buildInfoRow('Memory Status', '${data['memory_status'] ?? 'Unknown'}'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Firebase Integration:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text('✅ User authenticated', style: Theme.of(context).textTheme.bodySmall),
                        Text('✅ Firebase UID in use', style: Theme.of(context).textTheme.bodySmall),
                        Text('✅ Conversation memory active', style: Theme.of(context).textTheme.bodySmall),
                      ],
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
            ],
          ),
        );
      } else {
        _showErrorMessage('Failed to load memory status');
      }
    } catch (e) {
      print('❌ Memory status error: $e');
      _showErrorMessage('Failed to load memory status: ${e.toString()}');
    }
  }

  // --- Session Management Methods ---

  Future<void> _fetchSessions() async {
    setState(() => _isLoadingSessions = true);
    
    // Load from local DB first
    final localSessions = await _dbHelper.queryAllRows('chat_sessions');
    if (localSessions.isNotEmpty) {
      setState(() {
        _sessions = localSessions.map((s) => {
          'id': s['id'],
          'title': s['title'],
          'created_at': s['created_at'],
        }).toList();
      });
    }

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
        setState(() {
          _sessions = sessions;
        });
        
        // Update local DB
        // For simplicity, we might want to clear and re-insert or upsert
        // Here we just insert/update
        for (var session in sessions) {
           await _dbHelper.insert('chat_sessions', {
            'id': session['id'],
            'title': session['title'],
            'created_at': session['created_at'],
            'profession': widget.profession,
          });
        }
      }
    } catch (e) {
      print('❌ Error fetching sessions: $e');
    } finally {
      setState(() => _isLoadingSessions = false);
    }
  }

  Future<void> _loadSession(int sessionId) async {
    if (_currentSessionId == sessionId) return;

    setState(() {
      _currentSessionId = sessionId;
      _messages.clear();
      _isLoadingSessions = true; // Reusing loading state for message loading
    });
    
    // Load messages from local DB
    final localMessages = await _dbHelper.queryAllRows('chat_messages');
    // Filter by session ID (assuming we store it, which we added to schema)
    final sessionMessages = localMessages.where((m) => m['session_id'] == sessionId).toList();
    
    if (sessionMessages.isNotEmpty) {
      final List<ChatMessage> loadedMessages = sessionMessages.map((m) => ChatMessage(
        id: m['id'],
        content: m['content'],
        type: m['type'] == 'user' ? MessageType.user : MessageType.assistant,
        timestamp: DateTime.parse(m['timestamp']),
        status: m['is_synced'] == 1 ? MessageStatus.sent : MessageStatus.sending,
      )).toList();
      
      // Sort by timestamp
      loadedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      setState(() {
        _messages.addAll(loadedMessages);
      });
      
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    if (!_isOnline) {
      setState(() => _isLoadingSessions = false);
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
        final List<ChatMessage> loadedMessages = [];

        for (var msg in messagesData) {
          // Add user message
          final userMsg = ChatMessage(
            id: '${msg['id']}_user',
            content: msg['user_message'],
            type: MessageType.user,
            timestamp: DateTime.parse(msg['timestamp']),
          );
          loadedMessages.add(userMsg);
          
          // Save to local DB
          await _dbHelper.insert('chat_messages', {
            'id': userMsg.id,
            'session_id': sessionId,
            'content': userMsg.content,
            'type': 'user',
            'timestamp': userMsg.timestamp.toIso8601String(),
            'is_synced': 1,
          });

          // Add assistant response
          final assistantMsg = ChatMessage(
            id: '${msg['id']}_assistant',
            content: msg['assistant_response'],
            type: MessageType.assistant,
            timestamp: DateTime.parse(msg['timestamp']), // Or add small offset
            metadata: msg['metadata'],
          );
          loadedMessages.add(assistantMsg);
          
          // Save to local DB
          await _dbHelper.insert('chat_messages', {
            'id': assistantMsg.id,
            'session_id': sessionId,
            'content': assistantMsg.content,
            'type': 'assistant',
            'timestamp': assistantMsg.timestamp.toIso8601String(),
            'is_synced': 1,
          });
        }
        
        // Re-render with latest data (merging logic could be better but this is simple)
        setState(() {
          _messages.clear();
          _messages.addAll(loadedMessages);
        });
        
        // Scroll to bottom after loading
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      print('❌ Error loading session: $e');
      _showErrorMessage('Failed to load chat history');
    } finally {
      setState(() => _isLoadingSessions = false);
    }
  }

  void _createNewChat() {
    setState(() {
      _currentSessionId = null;
      _messages.clear();
      _addWelcomeMessage();
    });
  }

  Future<void> _deleteSession(int sessionId) async {
    // Confirm dialog
    final confirmed = await _showConfirmDialog(
      title: 'Delete Chat',
      content: 'Are you sure you want to delete this chat?',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (!confirmed) return;

    // Soft delete locally
    // We don't have is_deleted in chat_sessions schema yet, but we can just delete row or add column
    // For now, let's delete the row locally as we don't want to show it anymore
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
        sessionId.toString(), // ID is int, but queue expects string ID or we convert
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
         // Revert local change? Or just keep it deleted locally.
      }
    } catch (e) {
      print('❌ Error deleting session: $e');
      // If network error, we might want to queue it, but we already checked isOnline.
      // If it's another error, maybe show error.
      _showErrorMessage('Failed to delete chat');
    }
  }

  Future<void> _renameSession(int sessionId, String currentTitle) async {
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

    // Update locally
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
    
    // Handle new session creation (offline or online)
    if (_currentSessionId == null) {
      if (!_isOnline) {
        // Generate temporary negative ID for offline session
        final tempId = -DateTime.now().millisecondsSinceEpoch;
        _currentSessionId = tempId;
        
        // Create local session
        await _dbHelper.insert('chat_sessions', {
          'id': tempId,
          'title': 'New Chat', // Will be updated by backend later or user
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
      // If online, we wait for backend response to get ID
    }

    // Save to local DB (if session exists or we just created temp one)
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
        // Mark as queued/sent locally
        final index = _messages.indexWhere((m) => m.id == userMessage.id);
        if (index != -1) {
          _messages[index] = userMessage.copyWith(status: MessageStatus.sent);
        }
        
        // Add offline response
        _messages.add(ChatMessage(
          id: const Uuid().v4(),
          content: "I'm offline right now. I'll process your message when I'm back online.",
          type: MessageType.assistant,
          timestamp: DateTime.now(),
        ));
      });
      _scrollToBottom();
      
      // Queue message for sync
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
      
      // Update current session ID if it was null (new chat created)
      if (_currentSessionId == null && data['session_id'] != null) {
        setState(() {
          _currentSessionId = data['session_id'];
        });
        _fetchSessions(); // Refresh list to show new chat title
        
        // Now save the user message with the new session ID
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

      setState(() {
        _messages.add(assistantMessage);
        _isTyping = false;
      });
      
      // Save assistant response to local DB
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
      setState(() {
        _isTyping = false;
        final index = _messages.indexWhere((m) => m.id == userMessage.id);
        if (index != -1) {
          _messages[index] = userMessage.copyWith(status: MessageStatus.failed);
        }
      });

      _showErrorMessage('Failed to send message. Please try again.');
      print('Send message error: $e');
    }
  }


  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppConstants.fastAnimation,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    required bool isDestructive,
  }) async {
    final result = await showDialog<bool>(
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
            style: isDestructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _showExportDialog(Map<String, dynamic> exportData) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Chat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Export Data:'),
            const SizedBox(height: 8),
            _buildInfoRow('Firebase UID', exportData['firebase_uid'] ?? 'Unknown'),
            _buildInfoRow('Profession', widget.profession),
            _buildInfoRow('Total Messages', '${exportData['total_messages']}'),
            _buildInfoRow('Export Date', exportData['export_date']),
            _buildInfoRow('Memory Enabled', '${exportData['memory_enabled']}'),
            const SizedBox(height: 16),
            const Text(
              'Choose export format:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _copyToClipboard(exportData);
            },
            child: const Text('Copy to Clipboard'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(Map<String, dynamic> data) {
    final text = '''
Agent X Chat Export - ${widget.profession} Assistant
====================================================
Firebase UID: ${data['firebase_uid']}
Email: ${_getCurrentUserEmail()}
Profession: ${widget.profession}
Export Date: ${data['export_date']}
Total Messages: ${data['total_messages']}
Memory Enabled: ${data['memory_enabled']}

Conversations:
${(data['conversations'] as List<dynamic>).map((conv) =>
    'User: ${conv['user_message']}\nAgent: ${conv['assistant_response']}\nAgent: ${conv['agent_name']}\nIntent: ${conv['intent']}\nTime: ${conv['timestamp']}\n---'
    ).join('\n')}
    ''';

    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnackBar('Chat data copied to clipboard');
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        margin: AppConstants.paddingM,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        margin: AppConstants.paddingM,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onError,
              size: 20,
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        margin: AppConstants.paddingM,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
