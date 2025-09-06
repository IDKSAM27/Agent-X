import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../core/constants/app_constants.dart';
import '../core/config/api_config.dart';
import '../core/agents/agent_orchestrator.dart';
import '../models/chat_message.dart';
import '../widgets/enhanced_chat_bubble.dart';

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

  bool _isTyping = false;
  late AnimationController _inputController;
  late Dio dio;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _inputController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        resizeToAvoidBottomInset: true, // Enable proper keyboard handling
        appBar: _buildAppBar(),
        body: SafeArea( // Wrap in SafeArea
          child: Column(
            children: [
              Expanded(
                child: RepaintBoundary(
                  child: _buildMessagesList(),
                ),
              ),
              RepaintBoundary(
                child: _buildInputSection(), // Remove the AnimatedPadding wrapper
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Agent X',
              style: TextStyle(fontWeight: FontWeight.bold), // optional, makes it bold
            ),
          ),
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
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
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

  // Get profession-specific icon
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

        final response = await dio.post('/api/clear_memory', data: {
          'user_id': _getCurrentUserId(),
        });

        if (response.statusCode == 200 && response.data['status'] == 'success') {
          _addWelcomeMessage();
          _showSuccessSnackBar('All data cleared successfully');
        } else {
          _showErrorMessage('Failed to clear backend data: ${response.data['message']}');
        }
      } catch (e) {
        _showErrorMessage('Failed to clear data: ${e.toString()}');
      }
    }
  }

  Future<void> _exportChat() async {
    try {
      _showInfoSnackBar('Preparing chat export...');

      final response = await dio.post('/api/export_chat', data: {
        'user_id': _getCurrentUserId(),
      });

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final exportData = response.data['data'];
        await _showExportDialog(exportData);
      } else {
        _showErrorMessage('Failed to export: ${response.data['message']}');
      }
    } catch (e) {
      _showErrorMessage('Export failed: ${e.toString()}');
    }
  }

  Future<void> _showMemoryStatus() async {
    try {
      final response = await dio.get('/api/memory/debug/${_getCurrentUserId()}');

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
                  _buildInfoRow('User ID', _getCurrentUserId()),
                  _buildInfoRow('Profession', widget.profession), // Shows current profession
                  _buildInfoRow('Total Conversations', '${data['total_conversations'] ?? 0}'),
                  _buildInfoRow('Stored Profession', '${data['user_context']?['profession'] ?? 'Unknown'}'),
                  _buildInfoRow('Database Path', '${data['database_path'] ?? 'Unknown'}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Recent Conversations:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...((data['conversations'] as List<dynamic>?) ?? [])
                      .take(3)
                      .map((conv) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${conv['content']?.substring(0, 50) ?? 'No content'}...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ))
                      .toList(),
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
      _showErrorMessage('Failed to load memory status: ${e.toString()}');
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isTyping) return;

    HapticFeedback.lightImpact();

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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

    try {
      final orchestrator = AgentOrchestrator();
      // Pass profession context to the orchestrator
      final agentResponse = await orchestrator.processRequest(
        text,
        profession: widget.profession, // Pass profession for context-aware responses
      );

      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: agentResponse.response,
        type: MessageType.assistant,
        timestamp: DateTime.now(),
        metadata: agentResponse.metadata,
      );

      setState(() {
        _messages.add(assistantMessage);
        _isTyping = false;
      });

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
            _buildInfoRow('Profession', widget.profession), // Include profession in export
            _buildInfoRow('Total Messages', '${exportData['total_messages']}'),
            _buildInfoRow('Export Date', exportData['export_date']),
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
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(Map<String, dynamic> data) {
    final text = '''
Agent X Chat Export - ${widget.profession} Assistant
====================================================
User ID: ${data['user_id']}
Profession: ${widget.profession}
Export Date: ${data['export_date']}
Total Messages: ${data['total_messages']}

Conversations:
${(data['conversations'] as List<dynamic>).map((conv) =>
    'User: ${conv['user_message']}\nAgent: ${conv['agent_response']}\nTime: ${conv['timestamp']}\n---'
    ).join('\n')}
    ''';

    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnackBar('Chat data copied to clipboard');
  }

  String _getCurrentUserId() {
    return 'user_${widget.profession.toLowerCase()}_123'; // Include profession in user ID
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
