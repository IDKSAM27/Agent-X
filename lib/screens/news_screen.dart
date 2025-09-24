import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/news_service.dart';
import '../models/news_models.dart';
import '../widgets/enhanced_news_card.dart';
import '../widgets/news_category_filter.dart';
import '../widgets/news_insights_widget.dart';
import '../core/constants/app_constants.dart';

// class NewsScreen extends StatefulWidget {
//   const NewsScreen({super.key});
//
//   @override
//   State<NewsScreen> createState() => _NewsScreenState();
// }

class NewsScreen extends StatefulWidget {
  final String? profession;
  final String? location;

  const NewsScreen({
    super.key,
    this.profession,
    this.location,
  });

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> with TickerProviderStateMixin {
  final NewsService _newsService = NewsService();
  final ScrollController _scrollController = ScrollController();

  List<NewsArticle> _articles = [];
  Map<String, List<NewsArticle>> _categories = {};
  NewsMetadata? _metadata;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  // Filters
  String _selectedCategory = 'all';
  final List<String> _availableCategories = [
    'all',
    'local_events',
    'professional_dev',
    'career_opportunities',
    'education',
    'technology',
    'productivity'
  ];

  @override
  void initState() {
    super.initState();
    _loadNews();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNews({bool forceRefresh = false}) async {
    if (!forceRefresh) setState(() => _isLoading = true);

    try {
      final response = await _newsService.getContextualNews(
        profession: widget.profession,
        location: widget.location,
        limit: 50,
        forceRefresh: forceRefresh,
      );

      setState(() {
        _articles = response.articles;
        _categories = response.categories;
        _metadata = response.metadata;
        _error = null;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      _loadMoreNews();
    }
  }

  Future<void> _loadMoreNews() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final response = await _newsService.getContextualNews(
        limit: 20,
        // In a real implementation, you'd pass offset parameter
      );

      setState(() {
        // Append new articles (avoiding duplicates)
        final newArticles = response.articles.where(
                (newArticle) => !_articles.any((existing) => existing.id == newArticle.id)
        ).toList();

        _articles.addAll(newArticles);
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  List<NewsArticle> get _filteredArticles {
    if (_selectedCategory == 'all') {
      return _articles;
    } else {
      return _categories[_selectedCategory] ?? [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('News Feed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchSheet,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadNews(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _articles.isEmpty) {
      return _buildLoadingState();
    }

    if (_error != null && _articles.isEmpty) {
      return _buildErrorState();
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Insights Card
        if (_metadata != null) ...[
          SliverPadding(
            padding: AppConstants.pagePadding,
            sliver: SliverToBoxAdapter(
              child: NewsInsightsWidget(
                metadata: _metadata!,
                onViewAnalytics: _showAnalytics,
              ).animate().slideY(begin: -0.2, duration: 400.ms),
            ),
          ),
        ],

        // Category Filter
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
          sliver: SliverToBoxAdapter(
            child: NewsCategoryFilter(
              categories: _availableCategories,
              selectedCategory: _selectedCategory,
              onCategorySelected: (category) {
                setState(() => _selectedCategory = category);
              },
            ).animate().slideX(begin: -0.2, duration: 500.ms),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingM)),

        // News Articles
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
          sliver: _filteredArticles.isEmpty
              ? _buildEmptyState()
              : SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final article = _filteredArticles[index];
                return EnhancedNewsCard(
                  article: article,
                  onTap: () => _showArticleDetails(article),
                  onActionTap: _handleNewsAction,
                ).animate(delay: (index * 100).ms)
                    .slideX(begin: 0.2, duration: 400.ms)
                    .fadeIn();
              },
              childCount: _filteredArticles.length,
            ),
          ),
        ),

        // Loading more indicator
        if (_isLoadingMore) ...[
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingM)),
          SliverToBoxAdapter(
            child: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingXXL)),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppConstants.spacingM),
          Text(
            'Loading latest news...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: AppConstants.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppConstants.spacingM),
            Text(
              'Failed to load news',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppConstants.spacingS),
            Text(
              _error ?? 'Something went wrong',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingL),
            FilledButton.icon(
              onPressed: () => _loadNews(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: AppConstants.pagePadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.article_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: AppConstants.spacingM),
              Text(
                'No news in this category',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              Text(
                'Try switching to a different category or refresh.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ).animate().fadeIn(),
    );
  }

  void _showArticleDetails(NewsArticle article) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildArticleDetailsSheet(article),
    );
  }

  Widget _buildArticleDetailsSheet(NewsArticle article) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusL),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppConstants.spacingM),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: AppConstants.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Article header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
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
                        Text(
                          article.timeAgo,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppConstants.spacingM),

                    // Title
                    Text(
                      article.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: AppConstants.spacingM),

                    // Source and relevance
                    Row(
                      children: [
                        Text(
                          article.source,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingM),
                        if (article.relevanceScore > 0.7) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
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
                        ],
                      ],
                    ),

                    const SizedBox(height: AppConstants.spacingL),

                    // Description
                    Text(
                      article.summary,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),

                    // Tags
                    if (article.tags.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.spacingL),
                      Text(
                        'Tags',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingS),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: article.tags.take(5).map((tag) =>
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                tag,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                              ),
                            )
                        ).toList(),
                      ),
                    ],

                    // Event info for local events
                    if (article.isLocalEvent) ...[
                      const SizedBox(height: AppConstants.spacingL),
                      Container(
                        padding: AppConstants.paddingM,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppConstants.radiusM),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: AppConstants.spacingS),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Local Event',
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (article.eventLocation != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      article.eventLocation!,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: AppConstants.spacingXL),

                    // Action buttons
                    if (article.availableActions.isNotEmpty) ...[
                      Text(
                        'Quick Actions',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingM),
                      ...article.availableActions.map((action) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppConstants.spacingS),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _handleNewsAction(action, article);
                                },
                                icon: Icon(action.iconData, size: 20),
                                label: Text(action.label),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: action.colorValue),
                                  foregroundColor: action.colorValue,
                                ),
                              ),
                            ),
                          )
                      ).toList(),

                      const SizedBox(height: AppConstants.spacingM),
                    ],

                    // Full article button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          // Open in browser or web view
                          // You can implement URL launching here
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Read Full Article'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNewsAction(NewsAction action, NewsArticle article) async {
    try {
      final result = await _newsService.executeNewsAction(
        actionType: action.type,
        articleId: article.id,
        metadata: {
          'article_title': article.title,
          'article_url': article.url,
          'task_title': 'Follow up: ${article.title}',
          'task_description': 'From news: ${article.summary}',
          'event_title': article.title,
          'event_date': article.eventDate?.toIso8601String(),
          'event_location': article.eventLocation,
          ...action.metadata,
        },
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Action completed successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Provide user feedback for the action
        await _newsService.submitFeedback(
          articleId: article.id,
          feedbackType: 'helpful',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete action: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSearchSheet() {
    // Implement search functionality
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusL),
          ),
        ),
        child: const Center(
          child: Text('Search functionality coming soon!'),
        ),
      ),
    );
  }

  void _showFilterSheet() {
    // Implement advanced filtering
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
        child: const Center(
          child: Text('Advanced filters coming soon!'),
        ),
      ),
    );
  }

  void _showAnalytics() {
    // Show news analytics
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('News Analytics'),
        content: const Text('Your news consumption analytics will be shown here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
