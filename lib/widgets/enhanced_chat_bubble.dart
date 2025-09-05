import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/chat_message.dart';
import '../core/constants/app_constants.dart';
import 'typing_indicator.dart';
import 'calendar_response_card.dart';

class EnhancedChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAvatar;
  final VoidCallback? onRetry;

  const EnhancedChatBubble({
    super.key,
    required this.message,
    this.showAvatar = true,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.type == MessageType.user;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser && showAvatar) _buildAvatar(context),
          if (!isUser && showAvatar) const SizedBox(width: AppConstants.spacingS),

          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                gradient: isUser
                    ? LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                    : null,
                color: isUser
                    ? null
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppConstants.radiusL),
                  topRight: const Radius.circular(AppConstants.radiusL),
                  bottomLeft: Radius.circular(isUser ? AppConstants.radiusL : AppConstants.radiusS),
                  bottomRight: Radius.circular(isUser ? AppConstants.radiusS : AppConstants.radiusL),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isTyping)
                    const TypingIndicator()
                  else
                    _buildMessageContent(context, isUser), // Fixed method

                  _buildMessageFooter(context, isUser),
                ],
              ),
            ),
          ),

          if (isUser && showAvatar) const SizedBox(width: AppConstants.spacingS),
          if (isUser && showAvatar) _buildUserAvatar(context),
        ],
      ),
    )
        .animate()
        .slideY(begin: 0.3, duration: 300.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 300.ms);
  }

  Widget _buildAvatar(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.secondary,
            Theme.of(context).colorScheme.tertiary,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.smart_toy_rounded,
        size: 18,
        color: Colors.white,
      ),
    );
  }

  Widget _buildUserAvatar(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.person,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // Fixed message content method with calendar support
  Widget _buildMessageContent(BuildContext context, bool isUser) {
    if (!isUser && message.metadata != null && message.metadata!['type'] == 'calendar') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingM,
              AppConstants.spacingM,
              AppConstants.spacingM,
              AppConstants.spacingS,
            ),
            child: SelectableText(
              message.content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          if (message.metadata!['show_calendar'] == true)
            CalendarResponseCard(metadata: message.metadata!), // Now works, it was a bitchful of debugging
        ],
      );
    }

    // Default text content
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingM,
        AppConstants.spacingM,
        AppConstants.spacingM,
        AppConstants.spacingS,
      ),
      child: SelectableText(
        message.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isUser
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildMessageFooter(BuildContext context, bool isUser) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingM,
        0,
        AppConstants.spacingM,
        AppConstants.spacingS,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTimestamp(message.timestamp),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isUser
                  ? Colors.white.withOpacity(0.7)
                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AppConstants.spacingS),
            _buildStatusIcon(context),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    IconData icon;
    Color color;

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        color = Colors.white.withOpacity(0.5);
        break;
      case MessageStatus.sent:
        icon = Icons.done;
        color = Colors.white.withOpacity(0.7);
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white.withOpacity(0.7);
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red.shade300;
        break;
    }

    return Icon(
      icon,
      size: 12,
      color: color,
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }
}
