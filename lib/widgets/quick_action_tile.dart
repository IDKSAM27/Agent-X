import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_constants.dart';

class QuickActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const QuickActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor = color ?? Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spacingM,
            horizontal: AppConstants.spacingS,
          ),
          decoration: BoxDecoration(
            color: actionColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
            border: Border.all(
              color: actionColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: actionColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: actionColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: actionColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
