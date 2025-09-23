import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/news_service.dart';
import '../models/news_models.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/news_card.dart';
import '../widgets/app_logo.dart';
import '../core/constants/app_constants.dart';
import '../services/news_service.dart';
import '../models/news_models.dart';
import 'chat_screen.dart';
import 'clock_screen.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';
import 'news_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _profession;
  String? _userName;
  List<NewsArticle> _newsArticles = [];
  bool _isLoadingNews = true;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadNews();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists) {
        setState(() {
          _profession = doc.data()?['profession'] ?? 'Professional';
          _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      setState(() {
        _profession = 'Professional';
        _userName = 'User';
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _loadNews() async {
    try {
      if (_profession != null) {
        // Use the new news service method
        final newsService = NewsService();
        final response = await newsService.getContextualNews(
          profession: _profession,
          location: 'India', // I can make this dynamic based on user location
          limit: 6, // Just for home screen preview
        );

        setState(() {
          _newsArticles = response.articles;
          _isLoadingNews = false;
        });
      }
    } catch (e) {
      print('Error loading news: $e');
      setState(() {
        _isLoadingNews = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([_loadUserData(), _loadNews()]);
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Custom App Bar
              _buildAppBar(),

              // Main Content
              SliverPadding(
                padding: AppConstants.pagePadding,
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Welcome Section
                    _buildWelcomeSection(),

                    const SizedBox(height: AppConstants.spacingXL),

                    // Main Feature Cards
                    _buildMainFeatureCards(),

                    const SizedBox(height: AppConstants.spacingXL),

                    // Quick Actions
                    _buildQuickActions(),

                    const SizedBox(height: AppConstants.spacingXL),

                    // News Section
                    _buildNewsSection(),

                    const SizedBox(height: AppConstants.spacingXL),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
                Theme.of(context).colorScheme.secondary.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: AppConstants.pagePadding.copyWith(top: AppConstants.spacingL),
            child: Row(
              children: [
                const AppLogo(size: 48, showShadow: true),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Agent X',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Your AI Assistant Dashboard',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  onPressed: _showProfileMenu,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    if (_isLoadingProfile) {
      return Card(
        child: Padding(
          padding: AppConstants.cardPadding,
          child: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: AppConstants.spacingM),
              Text(
                'Loading your profile...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: AppConstants.cardPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      _userName ?? 'User',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingS),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _profession ?? 'Professional',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.waving_hand,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().slideY(begin: -0.2, duration: 600.ms).fadeIn(duration: 600.ms);
  }

  Widget _buildMainFeatureCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Main Features',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Row(
          children: [
            Expanded(
              child: DashboardCard(
                title: 'AI Chat',
                subtitle: 'Talk with Agent X',
                icon: Icons.smart_toy_rounded,
                gradientColors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
                onTap: () => _navigateToChat(),
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: DashboardCard(
                title: 'News Feed',
                subtitle: '${_newsArticles.length} updates',
                icon: Icons.article_rounded,
                gradientColors: [
                  Theme.of(context).colorScheme.tertiary,
                  Theme.of(context).colorScheme.primary,
                ],
                isLoading: _isLoadingNews,
                onTap: _isLoadingNews ? null : () => _navigateToNews(),
              ),
            ),
          ],
        ),
      ],
    ).animate(delay: 200.ms).slideX(begin: -0.2, duration: 600.ms).fadeIn();
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Row(
          children: [
            Expanded(
              child: QuickActionTile(
                label: 'Calendar',
                icon: Icons.calendar_month,
                onTap: () => _navigateToCalendar(),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: QuickActionTile(
                label: 'Tasks', // Changed from Clock to Tasks
                icon: Icons.task_alt, // Changed icon
                onTap: () => _navigateToTasks(), // New navigation
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: QuickActionTile(
                label: 'Clock', // Moved clock here, or remove entirely
                icon: Icons.access_time,
                onTap: () => _navigateToClock(),
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ],
        ),
      ],
    ).animate(delay: 400.ms).slideX(begin: 0.2, duration: 600.ms).fadeIn();
  }

  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Latest News',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: _isLoadingNews ? null : () => _navigateToNews(),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingM),
        if (_isLoadingNews)
          Card(
            child: Padding(
              padding: AppConstants.cardPadding,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (_newsArticles.isEmpty)
          Card(
            child: Padding(
              padding: AppConstants.cardPadding,
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppConstants.spacingM),
                    Text(
                      'No news available',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...(_newsArticles.take(3).map((article) => NewsCard(
            article: article,
            onTap: () => _showArticleDetails(article),
          )).toList()),
      ],
    ).animate(delay: 600.ms).slideY(begin: 0.2, duration: 600.ms).fadeIn();
  }

  // Navigation methods
  void _navigateToChat() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
          profession: _profession ?? 'General',
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOutCubic)),
            ),
            child: child,
          );
        },
        transitionDuration: AppConstants.normalAnimation,
      ),
    );
  }

  void _navigateToCalendar() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const CalendarScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: AppConstants.normalAnimation,
      ),
    );
  }

  void _navigateToTasks() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const TasksScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOutCubic)),
            ),
            child: child,
          );
        },
        transitionDuration: AppConstants.normalAnimation,
      ),
    );
  }

  void _navigateToNews() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const NewsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOutCubic)),
            ),
            child: child,
          );
        },
        transitionDuration: AppConstants.normalAnimation,
      ),
    );
  }

  void _navigateToClock() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const ClockScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return ScaleTransition(
            scale: animation.drive(
              Tween(begin: 0.8, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
            ),
            child: child,
          );
        },
        transitionDuration: AppConstants.normalAnimation,
      ),
    );
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusL)),
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
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () {
                Navigator.pop(context);
                _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showArticleDetails(NewsArticle article) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(article.title),
        content: Text(article.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusL)),
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
              leading: const Icon(Icons.palette),
              title: const Text('Theme'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Notifications'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.help),
              title: const Text('Help & Support'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }
}
