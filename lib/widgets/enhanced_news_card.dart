import 'package:flutter/material.dart';

import '../models/news_models.dart';
import '../core/constants/app_constants.dart';

class EnhancedNewsCard extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback? onTap;
  final Function(NewsAction, NewsArticle)? onActionTap;
  final bool showActions;

  const EnhancedNewsCard({
    super.key,
    required this.article,
    this.onTap,
    this.onActionTap,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            _buildContent(context),
            if (showActions && article.availableActions.isNotEmpty)
              _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: AppConstants.paddingM,
      child: Row(
        children: [
          // Category indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: article.categoryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  article.categoryIcon,
                  size: 14,
                  color: article.categoryColor,
                ),
                const SizedBox(width: 4),
                Text(
                  article.category.displayName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: article.categoryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Relevance indicator
          if (article.relevanceScore > 0.7)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 12, color: Colors.green),
                  const SizedBox(width: 2),
                  Text(
                    'High Match',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          if (article.relevanceScore > 0.7) const SizedBox(width: 8),

          // Time ago
          Text(
            article.timeAgo,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            article.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: AppConstants.spacingS),

          // Description/Summary
          Text(
            article.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),

          // Source and tags
          const SizedBox(height: AppConstants.spacingM),
          Row(
            children: [
              // Source
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  article.source,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Tags
              if (article.tags.isNotEmpty)
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    children: article.tags.take(2).map((tag) =>
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                    ).toList(),
                  ),
                ),
            ],
          ),

          // Event info for local events
          if (article.isLocalEvent) ...[
            const SizedBox(height: AppConstants.spacingS),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: article.isUrgent ? Colors.orange : Colors.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  article.eventLocation ?? 'Local Event',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: article.isUrgent ? Colors.orange : Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (article.eventDate != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.event,
                    size: 16,
                    color: article.isUrgent ? Colors.orange : Colors.blue,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${article.eventDate!.day}/${article.eventDate!.month}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: article.isUrgent ? Colors.orange : Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: AppConstants.spacingM),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Container(
      padding: AppConstants.paddingM,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Quick Actions:',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: article.availableActions.take(2).map((action) =>
                  ActionChip(
                    avatar: Icon(action.iconData, size: 16, color: action.colorValue),
                    label: Text(action.label),
                    onPressed: () => onActionTap?.call(action, article),
                    backgroundColor: action.colorValue.withOpacity(0.1),
                    labelStyle: TextStyle(
                      color: action.colorValue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
