import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/news_models.dart';
import '../services/news_service.dart';
import '../core/services/connectivity_service.dart';

class NewsRepository {
  static final NewsRepository _instance = NewsRepository._internal();
  factory NewsRepository() => _instance;
  NewsRepository._internal();

  final DatabaseHelper _db = DatabaseHelper();
  final ConnectivityService _connectivity = ConnectivityService();
  final NewsService _newsService = NewsService();

  // GET NEWS (offline-first with smart caching)
  Future<List<NewsArticle>> getNews({
    String? profession,
    String? location,
    List<String>? interests,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    try {
      // Check cache first if not forcing refresh
      if (!forceRefresh) {
        final cachedNews = await _getCachedNews(limit);
        final cacheExpired = await _isCacheExpired(); // FIX: Get bool value first

        if (cachedNews.isNotEmpty && !cacheExpired) {
          print('📱 Using cached news (${cachedNews.length} articles)');
          return cachedNews;
        }
      }

      // Try to fetch fresh news if online
      if (_connectivity.isOnline) {
        try {
          final response = await _newsService.getContextualNews(
            profession: profession,
            location: location,
            interests: interests,
            limit: limit,
            forceRefresh: forceRefresh,
          );

          // Cache the fresh news
          await _cacheNews(response.articles);
          return response.articles;
        } catch (e) {
          print('🌐 Online fetch failed, falling back to cache: $e');
        }
      }

      // Fallback to cached news
      final cachedNews = await _getCachedNews(limit);
      if (cachedNews.isNotEmpty) {
        print('📱 Using cached news as fallback (${cachedNews.length} articles)');
        return cachedNews;
      }

      // No cache available
      print('❌ No news available offline');
      return [];
    } catch (e) {
      print('❌ Error getting news: $e');
      return await _getCachedNews(limit);
    }
  }

  // CACHE METHODS
  Future<void> _cacheNews(List<NewsArticle> articles) async {
    final db = await _db.database;

    // Clear old cache
    await db.delete('news_cache');

    // Cache new articles
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 6)); // News expires in 6 hours

    for (final article in articles) {
      await db.insert(
        'news_cache',
        {
          'id': article.id,
          'title': article.title,
          'description': article.description,
          'summary': article.summary,
          'url': article.url,
          'image_url': article.imageUrl,
          'published_at': article.publishedAt.toIso8601String(),
          'source': article.source,
          'category': article.category.value,
          'relevance_score': article.relevanceScore,
          'tags': jsonEncode(article.tags),
          'cached_at': now.toIso8601String(),
          'expires_at': expiresAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    print('📦 Cached ${articles.length} news articles');
  }

  Future<List<NewsArticle>> _getCachedNews(int limit) async {
    final db = await _db.database;

    final maps = await db.query(
      'news_cache',
      orderBy: 'published_at DESC',
      limit: limit,
    );

    return maps.map((map) => _convertCachedNewsToArticle(map)).toList();
  }

  Future<bool> _isCacheExpired() async {
    final db = await _db.database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM news_cache WHERE expires_at > ?',
      [DateTime.now().toIso8601String()],
    );

    final validCount = result.first['count'] as int;
    return validCount == 0;
  }

  NewsArticle _convertCachedNewsToArticle(Map<String, dynamic> cached) {
    return NewsArticle(
      id: cached['id'],
      title: cached['title'],
      description: cached['description'],
      summary: cached['summary'],
      url: cached['url'],
      imageUrl: cached['image_url'],
      publishedAt: DateTime.parse(cached['published_at']),
      source: cached['source'],
      category: NewsCategory.fromString(cached['category']),
      relevanceScore: cached['relevance_score']?.toDouble() ?? 0.0,
      qualityScore: 0.8, // Default for cached news
      tags: List<String>.from(jsonDecode(cached['tags'] ?? '[]')),
      keywords: [],
      isLocalEvent: false,
      isUrgent: false,
      availableActions: [],
    );
  }

  // CLEANUP
  Future<void> cleanExpiredCache() async {
    final db = await _db.database;

    final deletedRows = await db.delete(
      'news_cache',
      where: 'expires_at < ?',
      whereArgs: [DateTime.now().toIso8601String()],
    );

    if (deletedRows > 0) {
      print('🧹 Cleaned $deletedRows expired news articles');
    }
  }
}
