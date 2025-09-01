import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants/app_constants.dart';

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Agent X is typing',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          ...List.generate(3, (index) {
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .scale(
              duration: 600.ms,
              delay: (200 * index).ms,
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.5, 1.5),
            )
                .then()
                .scale(
              duration: 600.ms,
              begin: const Offset(1.5, 1.5),
              end: const Offset(1.0, 1.0),
            );
          }),
        ],
      ),
    );
  }
}
