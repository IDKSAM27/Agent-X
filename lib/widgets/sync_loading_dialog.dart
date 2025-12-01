import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SyncLoadingDialog extends StatelessWidget {
  final String message;

  const SyncLoadingDialog({super.key, this.message = 'Syncing data...'});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cool animated icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_sync,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ).animate(onPlay: (controller) => controller.repeat())
                  .rotate(duration: 2000.ms, curve: Curves.easeInOut),
            ),
            const SizedBox(height: 24),
            Text(
              'Syncing',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              borderRadius: BorderRadius.circular(8),
            ).animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 1500.ms, color: Colors.white.withOpacity(0.5)),
          ],
        ),
      ).animate()
          .scale(duration: 400.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 300.ms),
    );
  }
}
