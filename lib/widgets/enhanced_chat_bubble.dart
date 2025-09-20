import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/chat_message.dart';
import '../core/constants/app_constants.dart';
import 'typing_indicator.dart';
import 'calendar_response_card.dart';
import '../screens/tasks_screen.dart';
import '../screens/calendar_screen.dart';

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
                  bottomLeft:
                  Radius.circular(isUser ? AppConstants.radiusL : AppConstants.radiusS),
                  bottomRight:
                  Radius.circular(isUser ? AppConstants.radiusS : AppConstants.radiusL),
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
                    _buildMessageContent(context, isUser), // Chat content + calendar support

                  // ACTION BUTTONS: View in Tasks/Calendar (below the message content)
                  if (!isUser && message.metadata != null) ..._buildActionButtons(context, message.metadata!),

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
            CalendarResponseCard(metadata: message.metadata!),
        ],
      );
    }

    // Default: just show text
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

  // --- ACTION BUTTON GENERATOR ---
  List<Widget> _buildActionButtons(BuildContext context, Map<String, dynamic> meta) {
    List<Widget> buttons = [];
    if (meta['show_action_button'] == true) {
      // Task navigation
      if (meta['type'] == 'task' && (meta['action'] == 'task_created' || meta['action'] == 'tasks_listed')) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TasksScreen())
                );
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('View in Tasks'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                minimumSize: const Size.fromHeight(40),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                elevation: 0,
              ),
            ),
          ),
        );
      }
      // Calendar navigation
      if (meta['type'] == 'calendar' && (meta['action'] == 'event_created' || meta['action'] == 'events_listed')) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CalendarScreen())
                );
              },
              icon: const Icon(Icons.calendar_today),
              label: const Text('View in Calendar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                minimumSize: const Size.fromHeight(40),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                elevation: 0,
              ),
            ),
          ),
        );
      }
    }
    return buttons;
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
