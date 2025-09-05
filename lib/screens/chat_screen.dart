import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chat_service.dart';
import '../widgets/enhanced_chat_bubble.dart';
import '../models/chat_message.dart';
import '../core/constants/app_constants.dart';
import '../widgets/app_logo.dart';
import '../core/agents/agent_orchestrator.dart';

class ChatScreen extends StatefulWidget {
  final String profession;

  const ChatScreen({super.key, required this.profession});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isTextEmpty = true;

  late AnimationController _sendButtonController;
  late AnimationController _inputController;

  @override
  void initState() {
    super.initState();

    _sendButtonController = AnimationController(
      duration: AppConstants.fastAnimation,
      vsync: this,
    );

    _inputController = AnimationController(
      duration: AppConstants.normalAnimation,
      vsync: this,
    );

    _controller.addListener(_onTextChanged);
    _inputController.forward();

    // Add welcome message
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    final welcomeMessage = ChatMessage(
      id: 'welcome',
      content: 'Hello! I\'m Agent X, your AI assistant. I\'m here to help you with anything related to your profession as a ${widget.profession}. How can I assist you today?',
      type: MessageType.assistant,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(welcomeMessage);
    });
  }

  void _onTextChanged() {
    final isEmpty = _controller.text.trim().isEmpty;
    if (isEmpty != _isTextEmpty) {
      setState(() => _isTextEmpty = isEmpty);
      if (isEmpty) {
        _sendButtonController.reverse();
      } else {
        _sendButtonController.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _sendButtonController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _buildMessagesList(),
          ),
          _buildInputSection(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios),
        onPressed: () => Navigator.pop(context),
        splashRadius: 24,
      ),
      title: Row(
        children: [
          // Replace the old Container with AppLogo
          const AppLogo(
            size: 40,
            showShadow: true,
            useGradientBackground: false, // Set to true if you want gradient background
          ),
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agent X',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _isTyping ? 'typing...' : 'AI Assistant',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showOptionsMenu,
          splashRadius: 24,
        ),
      ],
    );
  }


  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingM),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final showAvatar = index == _messages.length - 1 ||
            _messages[index + 1].type != message.type;

        return EnhancedChatBubble(
          message: message,
          showAvatar: showAvatar,
          onRetry: message.status == MessageStatus.failed
              ? () => _retryMessage(message)
              : null,
        );
      },
    );
  }

  Widget _buildInputSection() {
    return AnimatedBuilder(
      animation: _inputController,
      builder: (context, child) {
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
          padding: EdgeInsets.fromLTRB(
            AppConstants.spacingM,
            AppConstants.spacingM,
            AppConstants.spacingM,
            AppConstants.spacingM,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200), // Faster transition
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
                    decoration: const InputDecoration(
                      hintText: 'Ask me anything...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
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
      },
    );
  }


  Widget _buildSendButton() {
    return AnimatedBuilder(
      animation: _sendButtonController,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * _sendButtonController.value),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: _isTextEmpty || _isTyping
                  ? null
                  : LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
              color: _isTextEmpty || _isTyping
                  ? Theme.of(context).colorScheme.outline.withOpacity(0.3)
                  : null,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _isTextEmpty || _isTyping ? null : _sendMessage,
                child: Icon(
                  Icons.send_rounded,
                  color: _isTextEmpty || _isTyping
                      ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)
                      : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        );
      },
    );
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
      // Use the new orchestrator instead of ChatService
      final orchestrator = AgentOrchestrator();
      final agentResponse = await orchestrator.processRequest(text);

      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: agentResponse.response,
        type: MessageType.assistant,
        timestamp: DateTime.now(),
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

  void _retryMessage(ChatMessage message) {
    // Implementation for retry functionality
    HapticFeedback.lightImpact();
    _sendMessage();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppConstants.normalAnimation,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusL),
          ),
        ),
        padding: AppConstants.paddingL,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear Chat'),
              onTap: _clearChat,
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Export Chat'),
              onTap: _exportChat,
            ),
          ],
        ),
      ),
    );
  }

  void _clearChat() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Are you sure you want to clear all messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _messages.clear();
              });
              _addWelcomeMessage();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _exportChat() {
    Navigator.pop(context);
    // Implementation for export functionality
    _showErrorMessage('Export feature coming soon!');
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        margin: AppConstants.paddingM,
      ),
    );
  }
}
