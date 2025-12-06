import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/config/api_config.dart';

class NotesService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<List<Map<String, dynamic>>> getNotes() async {
    try {
      final idToken = await _auth.currentUser?.getIdToken();
      if (idToken == null) throw Exception('Not authenticated');

      final response = await _dio.get(
        '/api/notes',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        return List<Map<String, dynamic>>.from(response.data['notes']);
      } else {
        throw Exception(response.data['message'] ?? 'Failed to get notes');
      }
    } catch (e) {
      throw Exception('Error fetching notes: $e');
    }
  }

  Future<void> createNote(String title, String content, {String category = 'general'}) async {
    try {
      final idToken = await _auth.currentUser?.getIdToken();
      if (idToken == null) throw Exception('Not authenticated');

      final response = await _dio.post(
        '/api/notes',
        data: {
          'title': title,
          'content': content,
          'category': category,
        },
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode != 200 || response.data['status'] != 'success') {
        throw Exception(response.data['message'] ?? 'Failed to create note');
      }
    } catch (e) {
      throw Exception('Error creating note: $e');
    }
  }

  Future<void> deleteNote(String noteId) async {
    try {
      final idToken = await _auth.currentUser?.getIdToken();
      if (idToken == null) throw Exception('Not authenticated');

      final response = await _dio.delete(
        '/api/notes/$noteId',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode != 200 || response.data['status'] != 'success') {
        throw Exception(response.data['message'] ?? 'Failed to delete note');
      }
    } catch (e) {
      throw Exception('Error deleting note: $e');
    }
  }
}
