import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/config/api_config.dart';
import '../models/news_models.dart';

class NewsService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
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
    try {
      print('📡 Making request to: ${ApiConfig.baseUrl}/api/news/contextual');
      print('📊 Params: limit=$limit, profession=$profession, location=$location');

      final token = await _getAuthToken();
      print('🔑 Token exists: ${token != null}');

      final queryParams = <String, dynamic>{
        'limit': limit,
        'force_refresh': forceRefresh,  // MATCH the backend parameter name
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
            if (token != null) 'Authorization': 'Bearer $token',  // Better error handling
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return NewsResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to fetch news: ${response.data['message']}');
      }
    } on DioException catch (e) {
      print('Dio error: ${e.response?.statusCode} - ${e.response?.data}');
      if (e.response?.statusCode == 500) {
        throw Exception('Server error. Please try again later.');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      print('Error fetching contextual news: $e');
      rethrow;
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
