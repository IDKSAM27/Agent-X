import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../agents/base/agent_interface.dart';
import '../agents/base/agent_coordinator.dart';

/// Hybrid orchestrator that prioritizes backend over local agents
class HybridOrchestrator {
  final Dio _dio;
  final AgentCoordinator _localCoordinator;

  HybridOrchestrator() :
        _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          headers: ApiConfig.defaultHeaders,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )),
        _localCoordinator = AgentCoordinator() {

    // Add request/response interceptor for debugging
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('🌐 Backend Request: ${options.method} ${options.path}');
        print('📤 Data: ${options.data}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        print('✅ Backend Response: ${response.statusCode}');
        handler.next(response);
      },
      onError: (error, handler) {
        print('❌ Backend Error: ${error.message}');
        handler.next(error);
      },
    ));
  }

  Future<AgentResponse> processRequest(String message, {String? profession}) async {
    print('🤖 Processing: "$message"');

    // 1. Always try backend first for these types of queries
    if (_shouldUseBackend(message)) {
      print('🌐 Routing to backend...');
      try {
        final backendResponse = await _processWithBackend(message, profession);
        print('✅ Backend response received');
        return backendResponse;
      } catch (e) {
        print('❌ Backend failed: $e');
        print('🔄 Falling back to local agents...');
      }
    }

    // 2. Use local agents only for simple queries
    if (_isSimpleLocalQuery(message)) {
      print('🏠 Using local agents...');
      return await _processWithLocalAgents(message, profession);
    }

    // 3. Final fallback to backend for everything else
    print('🌐 Final backend attempt...');
    try {
      return await _processWithBackend(message, profession);
    } catch (e) {
      print('❌ All attempts failed, returning error response');
      return _createErrorResponse(e.toString());
    }
  }

  bool _shouldUseBackend(String message) {
    final msg = message.toLowerCase();

    // Enhanced backend keywords - more comprehensive
    final backendKeywords = [
      // Calendar & Events
      'calendar', 'schedule', 'meeting', 'event', 'appointment',
      'book', 'reserve', 'plan', 'when', 'time', 'date',

      // Tasks & Productivity, added missing task keywords
      'task', 'todo', 'reminder', 'deadline', 'project',
      'complete', 'finish', 'due', 'priority', 'create task',
      'add task', 'make task', 'new task', 'task to',

      // Communication
      'email', 'mail', 'send', 'message', 'contact',

      // Learning & Information
      'news', 'update', 'learn', 'explain', 'how to', 'what is',
      'tell me about', 'help with', 'show me',

      // Memory & Data, added export keywords
      'remember', 'save', 'store', 'recall', 'history',
      'delete', 'clear', 'export', 'download', 'backup',
      'export chat', 'save chat', 'download chat'
    ];

    final hasBackendKeyword = backendKeywords.any((keyword) => msg.contains(keyword));

    // Enhanced backend patterns
    final backendPatterns = [
      RegExp(r'(create|add|make).+(task|event|meeting|appointment)'),
      RegExp(r'(show|list|view).+(tasks|events|calendar|schedule)'),
      RegExp(r'(what|when|how).+(my|is|do|can)'),
      RegExp(r'(remind|schedule|plan).+me'),
      RegExp(r'(export|download|save).+(chat|conversation|history)'), // Export pattern
      RegExp(r'task.+to.+(finish|complete|do)'), // "task to finish" pattern
    ];

    final hasBackendPattern = backendPatterns.any((pattern) => pattern.hasMatch(msg));

    print('📊 Backend check: keyword=$hasBackendKeyword, pattern=$hasBackendPattern');
    return hasBackendKeyword || hasBackendPattern;
  }

  bool _isSimpleLocalQuery(String message) {
    final msg = message.toLowerCase();

    // Only these very simple queries should use local agents
    final simpleKeywords = [
      'hi', 'hello', 'hey', 'good morning', 'good afternoon',
      'my name is', 'what is my name', 'who am i', 'call me'
    ];

    final isSimple = simpleKeywords.any((keyword) => msg.contains(keyword));
    print('🏠 Simple query check: $isSimple');
    return isSimple;
  }

  Future<AgentResponse> _processWithBackend(String message, String? profession) async {
    final requestData = {
      'message': message,
      'user_id': _getCurrentUserId(),
      'context': {
        'profession': profession ?? 'Unknown',
        'source': 'flutter_app',
        'timestamp': DateTime.now().toIso8601String(),
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    print('📤 Sending to backend: $requestData');

    final response = await _dio.post('/api/agents/process', data: requestData);

    // Convert backend response to AgentResponse
    final data = response.data;

    return AgentResponse(
      agentName: data['agent_name'] ?? 'BackendAgent',
      response: data['response'] ?? 'No response from backend',
      type: _parseResponseType(data['type']),
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
      suggestedActions: List<String>.from(data['suggested_actions'] ?? []),
      involvedAgents: [data['agent_name'] ?? 'BackendAgent'],
      confidence: (data['confidence'] ?? 1.0).toDouble(),
      requiresFollowUp: data['requires_follow_up'] ?? false,
    );
  }

  Future<AgentResponse> _processWithLocalAgents(String message, String? profession) async {
    final request = AgentRequest(
      message: message,
      userId: _getCurrentUserId(),
      profession: profession,
      context: {
        'profession': profession ?? 'Unknown',
        'source': 'local_agents',
      },
      timestamp: DateTime.now(),
      conversationHistory: [], // Could be populated from memory
    );

    return await _localCoordinator.processRequest(request);
  }

  AgentResponseType _parseResponseType(String? type) {
    switch (type?.toLowerCase()) {
      case 'calendar':
        return AgentResponseType.calendar;
      case 'task':
        return AgentResponseType.task;
      case 'news':
        return AgentResponseType.news;
      case 'learning':
        return AgentResponseType.learning;
      case 'suggestion':
        return AgentResponseType.suggestion;
      default:
        return AgentResponseType.text;
    }
  }

  AgentResponse _createErrorResponse(String error) {
    return AgentResponse(
      agentName: 'SystemAgent',
      response: 'I\'m having trouble connecting right now. Please check your internet connection and try again.',
      type: AgentResponseType.text,
      metadata: {'error': error, 'fallback': true},
      suggestedActions: [
        'Try again',
        'Check internet connection',
        'Ask a simple question',
      ],
      confidence: 0.1,
    );
  }

  String _getCurrentUserId() {
    // Replace with actual user ID from Firebase Auth or your auth system
    return 'user_123';
  }
}
