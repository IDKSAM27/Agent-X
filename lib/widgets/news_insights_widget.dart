import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/news_models.dart';
import '../core/constants/app_constants.dart';

class NewsInsightsWidget extends StatelessWidget {
  final NewsMetadata metadata;
  final VoidCallback? onViewAnalytics;

  const NewsInsightsWidget({
    super.key,
    required this.metadata,
    this.onViewAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppConstants.paddingM,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
            Theme.of(context).colorScheme.secondary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: AppConstants.spacingS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'News Insights',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Updated ${_getLastUpdateText()}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onViewAnalytics != null)
                TextButton(
                  onPressed: onViewAnalytics,
                  child: const Text('Details'),
                ),
            ],
          ),

          const SizedBox(height: AppConstants.spacingM),

          // Stats row
          Row(
            children: [
              _buildStatItem(
                context,
                icon: Icons.article,
                label: 'Articles',
                value: metadata.totalArticles.toString(),
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppConstants.spacingL),
              _buildStatItem(
                context,
                icon: Icons.source,
                label: 'Sources',
                value: metadata.sourcesUsed.toString(),
                color: Theme.of(context).colorScheme.secondary,
              ),
              const Spacer(),
              _buildStatItem(
                context,
                icon: Icons.speed,
                label: 'Match Rate',
                value: '${_calculateMatchRate()}%',
                color: _getMatchRateColor(context),
              ),
            ],
          ),

          // Profession insight
          if (metadata.userProfile['profession'] != null) ...[
            const SizedBox(height: AppConstants.spacingM),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person,
                    size: 14,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Curated for ${metadata.userProfile['profession']}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().slideY(begin: -0.2, duration: 400.ms).fadeIn();
  }

  Widget _buildStatItem(
      BuildContext context, {
        required IconData icon,
        required String label,
        required String value,
        required Color color,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _getLastUpdateText() {
    final now = DateTime.now();
    final diff = now.difference(metadata.lastUpdated);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  int _calculateMatchRate() {
    // Calculate based on raw articles vs processed articles
    if (metadata.rawArticlesFetched == 0) return 0;
    return ((metadata.totalArticles / metadata.rawArticlesFetched) * 100).round();
  }

  Color _getMatchRateColor(BuildContext context) {
    final rate = _calculateMatchRate();
    if (rate >= 80) return Colors.green;
    if (rate >= 60) return Colors.orange;
    return Colors.red;
  }
}
