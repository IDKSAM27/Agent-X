import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'base_agent.dart';
import '../config/api_config.dart';

class AgentOrchestrator {
  static final AgentOrchestrator _instance = AgentOrchestrator._internal();
  factory AgentOrchestrator() => _instance;
  AgentOrchestrator._internal();

  final Dio _dio = Dio();
  final Map<String, BaseAgent> _agents = {};

  // Initialize orchestrator
  Future<void> initialize() async {
    _setupDio();
    // Register available agents (will expand in later phases)
    _registerAgents();
  }

  void _setupDio() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    // Add request interceptor for authentication
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        print('API Error: ${error.message}');
        handler.next(error);
      },
    ));
  }

  void _registerAgents() {
    // Will be expanded with more agents
    // _agents['chat'] = ChatAgent();
    // _agents['calendar'] = CalendarAgent();
  }

  // Main orchestration method
  Future<AgentResponse> processRequest(String message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final request = AgentRequest(
        message: message,
        userId: user.uid,
        context: await _buildContext(),
        timestamp: DateTime.now(),
      );

      // Send to Python backend for intelligent routing
      final response = await _dio.post(
        '/api/agents/process',
        data: request.toJson(),
      );

      return AgentResponse.fromJson(response.data);
    } catch (e) {
      print('Orchestrator Error: $e');
      return AgentResponse(
        agentName: 'Error',
        response: 'Sorry, I encountered an error processing your request. Please try again.',
        type: AgentResponseType.text,
      );
    }
  }

  Future<Map<String, dynamic>> _buildContext() async {
    // Build context from user profile and app state
    final user = FirebaseAuth.instance.currentUser;
    return {
      'user_id': user?.uid,
      'timestamp': DateTime.now().toIso8601String(),
      'app_version': '1.0.0',
      // Add more context as needed
    };
  }

  // Get available agents
  List<String> getAvailableAgents() {
    return _agents.keys.toList();
  }

  // Health check
  Future<bool> isHealthy() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
