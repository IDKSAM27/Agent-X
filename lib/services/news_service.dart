import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/config/api_config.dart';
import '../models/news_models.dart';
import '../core/database/database_helper.dart';

class NewsService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 90),
  ));

  Future<String?> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  Future<NewsResponse> getContextualNews({
    String? profession,
    String? location,
    List<String>? interests,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    // 1. Try to get local data first if not forcing refresh
    if (!forceRefresh) {
      final localNews = await getOfflineNews();
      if (localNews.articles.isNotEmpty) {
        // If we have local data, we can return it immediately or decide to refresh in background
        // For now, let's return it if the API call fails, or we can return it and let the UI decide.
        // But the pattern requested is: API first, fallback to local.
        // However, for "offline first" feel, we might want to return local, then refresh.
        // The plan says: Fetch API -> Success? Save & Return -> Fail? Return Local.
      }
    }

    try {
      print('📡 Making request to: ${ApiConfig.baseUrl}/api/news/contextual');
      print('📊 Params: limit=$limit, profession=$profession, location=$location');

      final token = await _getAuthToken();
      print('🔑 Token exists: ${token != null}');

      final queryParams = <String, dynamic>{
        'limit': limit,
        'force_refresh': forceRefresh,
      };

      if (profession != null) queryParams['profession'] = profession;
      if (location != null) queryParams['location'] = location;
      if (interests != null && interests.isNotEmpty) {
        queryParams['interests'] = interests.join(',');
      }

      final response = await _dio.get(
        '/api/news/contextual',
        queryParameters: queryParams,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final newsResponse = NewsResponse.fromJson(response.data);
        await saveNews(newsResponse.articles);
        return newsResponse;
      } else {
        throw Exception('Failed to fetch news: ${response.data['message']}');
      }
    } on DioException catch (e) {
      print('Dio error: ${e.response?.statusCode} - ${e.response?.data}');
      // Fallback to offline data
      print('⚠️ Network error, falling back to offline news');
      final localNews = await getOfflineNews();
      if (localNews.articles.isNotEmpty) {
        return localNews;
      }
      
      if (e.response?.statusCode == 500) {
        throw Exception('Server error. Please try again later.');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      print('Error fetching contextual news: $e');
      // Fallback to offline data
      print('⚠️ Error, falling back to offline news');
      final localNews = await getOfflineNews();
      if (localNews.articles.isNotEmpty) {
        return localNews;
      }
      rethrow;
    }
  }

  Future<void> saveNews(List<NewsArticle> articles) async {
    try {
      // We might want to clear old news or just upsert.
      // For simplicity and to avoid stale data buildup, let's clear old cache for now
      // or just replace.
      // A better approach is to keep them but maybe mark them.
      // Let's just upsert them.
      
      for (var article in articles) {
        await _dbHelper.insert('news', {
          'id': article.id,
          'title': article.title,
          'description': article.description,
          'summary': article.summary,
          'url': article.url,
          'source': article.source,
          'published_at': article.publishedAt.toIso8601String(),
          'category': article.category.value,
          'image_url': article.imageUrl,
          'relevance_score': article.relevanceScore,
          'quality_score': article.qualityScore,
          'tags': jsonEncode(article.tags),
          'keywords': jsonEncode(article.keywords),
          'is_local_event': article.isLocalEvent ? 1 : 0,
          'is_urgent': article.isUrgent ? 1 : 0,
          'event_date': article.eventDate?.toIso8601String(),
          'event_location': article.eventLocation,
          'available_actions': jsonEncode(article.availableActions.map((a) => {
            'type': a.type,
            'label': a.label,
            'icon': a.icon,
            'color': a.color,
            'metadata': a.metadata,
          }).toList()),
          'cached_at': DateTime.now().toIso8601String(),
        });
      }
      print('✅ Saved ${articles.length} news articles to local DB');
    } catch (e) {
      print('❌ Error saving news to local DB: $e');
    }
  }

  Future<NewsResponse> getOfflineNews() async {
    try {
      final rows = await _dbHelper.queryAllRows('news');
      final articles = rows.map((row) {
        return NewsArticle(
          id: row['id'],
          title: row['title'],
          description: row['description'] ?? '',
          summary: row['summary'],
          url: row['url'],
          imageUrl: row['image_url'],
          publishedAt: DateTime.parse(row['published_at']),
          source: row['source'],
          category: NewsCategory.fromString(row['category']),
          relevanceScore: (row['relevance_score'] as num).toDouble(),
          qualityScore: (row['quality_score'] as num?)?.toDouble() ?? 0.0,
          tags: row['tags'] != null ? List<String>.from(jsonDecode(row['tags'])) : [],
          keywords: row['keywords'] != null ? List<String>.from(jsonDecode(row['keywords'])) : [],
          isLocalEvent: row['is_local_event'] == 1,
          isUrgent: row['is_urgent'] == 1,
          eventDate: row['event_date'] != null ? DateTime.parse(row['event_date']) : null,
          eventLocation: row['event_location'],
          availableActions: row['available_actions'] != null 
              ? (jsonDecode(row['available_actions']) as List).map((a) => NewsAction.fromJson(a)).toList() 
              : [],
        );
      }).toList();

      // Sort by date descending
      articles.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      // Group by category
      final categories = <String, List<NewsArticle>>{};
      for (var article in articles) {
        final cat = article.category.value;
        if (!categories.containsKey(cat)) {
          categories[cat] = [];
        }
        categories[cat]!.add(article);
      }

      return NewsResponse(
        articles: articles,
        categories: categories,
        metadata: NewsMetadata(
          totalArticles: articles.length,
          rawArticlesFetched: articles.length,
          sourcesUsed: 0,
          lastUpdated: DateTime.now(),
          userProfile: {},
        ),
      );
    } catch (e) {
      print('❌ Error fetching offline news: $e');
      return NewsResponse(articles: [], categories: {}, metadata: NewsMetadata(
        totalArticles: 0,
        rawArticlesFetched: 0,
        sourcesUsed: 0,
        lastUpdated: DateTime.now(),
        userProfile: {},
      ));
    }
  }

  Future<NewsResponse> getNewsByCategory({
    required String category,
    int limit = 20,
  }) async {
    try {
      final token = await _getAuthToken();

      final response = await _dio.get(
        '/api/news/categories/$category',
        queryParameters: {'limit': limit},
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return NewsResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to fetch category news: ${response.data['message']}');
      }
    } catch (e) {
      print('Error fetching category news: $e');
      rethrow;
    }
  }

  Future<NewsResponse> getLocalEvents({
    String? location,
    int daysAhead = 30,
  }) async {
    try {
      final token = await _getAuthToken();

      final queryParams = <String, dynamic>{
        'days_ahead': daysAhead,
      };

      if (location != null) queryParams['location'] = location;

      final response = await _dio.get(
        '/api/news/local-events',
        queryParameters: queryParams,
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return NewsResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to fetch local events: ${response.data['message']}');
      }
    } catch (e) {
      print('Error fetching local events: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> executeNewsAction({
    required String actionType,
    required String articleId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final token = await _getAuthToken();

      final response = await _dio.post(
        '/api/news/action',
        data: {
          'action_type': actionType,
          'article_id': articleId,
          'metadata': metadata ?? {},
        },
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data;
      } else {
        throw Exception('Failed to execute action: ${response.data['message']}');
      }
    } catch (e) {
      print('Error executing news action: $e');
      rethrow;
    }
  }

  Future<void> submitFeedback({
    required String articleId,
    required String feedbackType,
  }) async {
    try {
      final token = await _getAuthToken();

      await _dio.post(
        '/api/news/feedback',
        data: {
          'article_id': articleId,
          'feedback_type': feedbackType,
        },
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } catch (e) {
      print('Error submitting feedback: $e');
      // Non-critical, don't rethrow
    }
  }

  Future<Map<String, dynamic>> getNewsContextForChat({int daysBack = 3}) async {
    try {
      final token = await _getAuthToken();

      final response = await _dio.get(
        '/api/news/context-for-chat',
        queryParameters: {'days_back': daysBack},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'];
      } else {
        throw Exception('Failed to get news context');
      }
    } catch (e) {
      print('Error getting news context for chat: $e');
      return {'error': e.toString(), 'total_articles': 0};
    }
  }
}
