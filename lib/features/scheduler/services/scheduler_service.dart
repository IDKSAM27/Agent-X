import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/api_config.dart';
import '../models/scheduler_model.dart';

class SchedulerService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 90),
  ));

  Future<String?> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  Future<Schedule> parseScheduleFromFile(File file) async {
    try {
      final token = await _getAuthToken();
      
      String fileName = file.path.split('/').last;
      
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: fileName,
        ),
      });

      final response = await _dio.post(
        '/api/scheduler/parse',
        data: formData,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            // Content-Type is set automatically by Dio for FormData
          },
        ),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        return Schedule.fromJson(response.data['data']);
      } else {
        throw Exception('Failed to parse schedule: ${response.data['detail'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('Error parsing schedule from file: $e');
      rethrow;
    }
  }

  Future<Schedule> parseScheduleFromText(String text) async {
    try {
      final token = await _getAuthToken();
      
      final response = await _dio.post(
        '/api/scheduler/parse',
        data: {'text': text},
        options: Options(
          headers: {
             if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        return Schedule.fromJson(response.data['data']);
      } else {
        throw Exception('Failed to parse schedule: ${response.data['detail'] ?? 'Unknown error'}');
      }
    } catch (e) {
       print('Error parsing schedule from text: $e');
      rethrow;
    }
  }

  Future<Schedule> createSchedule(Schedule schedule) async {
    try {
      final token = await _getAuthToken();
      
      final response = await _dio.post(
        '/api/scheduler/schedules',
        data: schedule.toJson(),
        options: Options(
          headers: {
             if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        return Schedule.fromJson(response.data);
      } else {
         throw Exception('Failed to create schedule: ${response.data['detail'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('Error creating schedule: $e');
      rethrow;
    }
  }

  Future<List<Schedule>> getSchedules() async {
    try {
      final token = await _getAuthToken();

      final response = await _dio.get(
        '/api/scheduler/schedules',
        options: Options(
          headers: {
             if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final List<dynamic> schedulesJson = response.data['schedules'];
        return schedulesJson.map((json) => Schedule.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch schedules');
      }
    } catch (e) {
       print('Error fetching schedules: $e');
      rethrow;
    }
  }

  Future<void> deleteSchedule(int id) async {
    try {
      final token = await _getAuthToken();

      await _dio.delete(
        '/api/scheduler/schedules/$id',
        options: Options(
          headers: {
             if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } catch (e) {
      print('Error deleting schedule: $e');
      rethrow;
    }
  }
}
