import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/config/api_config.dart';

class BriefingService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 180),
    receiveTimeout: const Duration(seconds: 180),
  ));
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _cacheKey = 'daily_briefing_cache';
  static const String _cacheDateKey = 'daily_briefing_date';

  Future<Map<String, dynamic>> getBriefing({bool forceRefresh = false}) async {
    try {
      // Check cache first
      if (!forceRefresh) {
        final prefs = await SharedPreferences.getInstance();
        final cachedDate = prefs.getString(_cacheDateKey);
        final today = DateTime.now().toString().split(' ')[0];

        if (cachedDate == today) {
          final cachedData = prefs.getString(_cacheKey);
          if (cachedData != null) {
            return json.decode(cachedData);
          }
        }
      }

      final idToken = await _auth.currentUser?.getIdToken();
      if (idToken == null) throw Exception('Not authenticated');

      final response = await _dio.get(
        '/api/briefing',
        queryParameters: forceRefresh ? {'force_refresh': 'true'} : null,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        // Cache the result
        final prefs = await SharedPreferences.getInstance();
        final today = DateTime.now().toString().split(' ')[0];
        await prefs.setString(_cacheDateKey, today);
        await prefs.setString(_cacheKey, json.encode(response.data));
        
        return response.data;
      } else {
        throw Exception(response.data['message'] ?? 'Failed to get briefing');
      }
    } catch (e) {
      throw Exception('Error fetching briefing: $e');
    }
  }
}
