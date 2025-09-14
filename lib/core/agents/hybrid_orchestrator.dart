import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/api_config.dart';
import '../agents/base/agent_interface.dart';
import '../agents/base/agent_coordinator.dart';

/// Hybrid orchestrator that prioritizes backend over local agents
/// Integrated with Firebase Authentication and with boat load of emojis
class HybridOrchestrator {
  final Dio _dio;
  final AgentCoordinator _localCoordinator;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Add retry tracking
  final Map<String, int> _retryCount = {};

  HybridOrchestrator() :
        _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          headers: ApiConfig.defaultHeaders,
          connectTimeout: const Duration(seconds: 90), //TODO: og was 10 sec, change it afterwards
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        )),
        _localCoordinator = AgentCoordinator() {

    // FIXED: Single interceptor with retry limit and proper error handling
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Generate unique request ID for retry tracking
        final requestId = '${options.method}_${options.path}_${DateTime.now().millisecondsSinceEpoch}';
        options.extra['requestId'] = requestId;

        print('🌐 Backend Request: ${options.method} ${options.path}');
        print('📤 Data: ${options.data}');

        // Add Firebase ID token to requests
        try {
          final idToken = await _getFirebaseIdToken();
          if (idToken != null) {
            options.headers['Authorization'] = 'Bearer $idToken';
            print('🔑 Added Firebase ID token to request');
          } else {
            print('⚠️ No Firebase ID token available');
          }
        } catch (e) {
          print('❌ Error getting Firebase ID token: $e');
        }

        handler.next(options);
      },
      onResponse: (response, handler) {
        print('✅ Backend Response: ${response.statusCode}');

        // Clear retry count on successful response
        final requestId = response.requestOptions.extra['requestId'];
        if (requestId != null) {
          _retryCount.remove(requestId);
        }

        handler.next(response);
      },
      onError: (error, handler) async {
        print('❌ Backend Error: ${error.message}');
        print('❌ Status Code: ${error.response?.statusCode}');

        // Handle 401 Unauthorized with retry limit
        if (error.response?.statusCode == 401) {
          final requestId = error.requestOptions.extra['requestId'] as String?;
          if (requestId != null) {
            final currentRetryCount = _retryCount[requestId] ?? 0;

            // Limit retries to prevent infinite loop
            if (currentRetryCount < 1) { // Allow only 1 retry
              print('🔄 Token might be expired, attempting to refresh... (Retry ${currentRetryCount + 1}/1)');
              _retryCount[requestId] = currentRetryCount + 1;

              try {
                final newToken = await _refreshFirebaseToken();
                if (newToken != null) {
                  // Retry the original request with new token
                  final options = error.requestOptions;
                  options.headers['Authorization'] = 'Bearer $newToken';

                  print('🔄 Retrying request with refreshed token...');
                  final response = await _dio.fetch(options);

                  // Clear retry count on successful retry
                  _retryCount.remove(requestId);
                  return handler.resolve(response);
                } else {
                  print('❌ Failed to get new token');
                }
              } catch (refreshError) {
                print('❌ Token refresh failed: $refreshError');
              }
            } else {
              print('❌ Max retries exceeded for request $requestId');
              _retryCount.remove(requestId); // Clean up
            }
          }
        }

        handler.next(error);
      },
    ));

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

  /// Get Firebase ID token for current user
  Future<String?> _getFirebaseIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
      return null;
    } catch (e) {
      print('Error getting Firebase ID token: $e');
      return null;
    }
  }

  /// Refresh Firebase ID token
  Future<String?> _refreshFirebaseToken() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        return await user.getIdToken(true); // Force refresh
      }
      return null;
    } catch (e) {
      print('Error refreshing Firebase ID token: $e');
      return null;
    }
  }

  /// Check if user is authenticated
  bool get isUserAuthenticated => _auth.currentUser != null;

  /// Get current Firebase user
  User? get currentUser => _auth.currentUser;

  /// Get current user ID (Firebase UID)
  String? get currentUserId => _auth.currentUser?.uid;

  Future<AgentResponse> processRequest(String message, {String? profession}) async {
    print('🤖 Processing: "$message"');

    // Check authentication first
    if (!isUserAuthenticated) {
      print('❌ User not authenticated');
      return _createAuthErrorResponse();
    }

    // 1. Always try backend first for these types of queries
    if (_shouldUseBackend(message)) {
      print('🌐 Routing to backend...');
      try {
        final backendResponse = await _processWithBackend(message, profession);
        print('✅ Backend response received');
        return backendResponse;
      } catch (e) {
        print('❌ Backend failed: $e');

        // If it's an auth error, don't fall back to local
        if (e is DioException && e.response?.statusCode == 401) {
          return _createAuthErrorResponse();
        }

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
      // If it's an auth error, return auth error
      if (e is DioException && e.response?.statusCode == 401) {
        return _createAuthErrorResponse();
      }

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

    // Enhanced simple query detection
    final simplePatterns = [
      RegExp(r'^(hi|hello|hey)(\s|$)'),
      RegExp(r'good (morning|afternoon|evening)'),
      RegExp(r'(my name is|i am|call me)\s+\w+'), // Name setting
      RegExp(r'(what is my name|who am i)(\?)?$'), // Name asking
    ];

    final isSimple = simplePatterns.any((pattern) => pattern.hasMatch(msg));
    print('🏠 Simple query check: $isSimple');
    return isSimple;
  }

  Future<AgentResponse> _processWithBackend(String message, String? profession) async {
    // Get current user info from Firebase
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final requestData = {
      'message': message,
      // Remove user_id as it will be extracted from Firebase token in backend
      'context': {
        'profession': profession ?? await _getUserProfession() ?? 'Unknown',
        'source': 'flutter_app',
        'timestamp': DateTime.now().toIso8601String(),
        'user_email': user.email,
        'user_display_name': user.displayName,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    print('📤 Sending to backend: $requestData');

    final response = await _dio.post('/api/agents/process', data: requestData);

    // Add debug logging
    print('🔍 Raw backend response: ${response.data}');
    print('🔍 Response type: ${response.data.runtimeType}');

    // Ensure it's a Map before processing
    if (response.data is! Map<String, dynamic>) {
      print('❌ Backend returned non-JSON response: ${response.data}');
      return _createErrorResponse('Backend returned invalid format');
    }

    // Use the new factory constructor
    return AgentResponse.fromJson(response.data);
  }

  Future<AgentResponse> _processWithLocalAgents(String message, String? profession) async {
    final request = AgentRequest(
      message: message,
      userId: currentUserId ?? 'unknown',
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

  /// Get user profession from Firestore or local storage
  Future<String?> _getUserProfession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      // You can fetch this from Firestore if you're storing it there
      // For now, return null and let backend handle the default
      // TODO: Implement Firestore fetch if needed
      return null;
    } catch (e) {
      print('Error getting user profession: $e');
      return null;
    }
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

  AgentResponse _createAuthErrorResponse() {
    return AgentResponse(
      agentName: 'AuthAgent',
      response: 'You need to be signed in to use this feature. Please sign in and try again.',
      type: AgentResponseType.text,
      metadata: {'error': 'authentication_required', 'auth_error': true},
      suggestedActions: [
        'Sign in to your account',
        'Create a new account',
        'Try a simple question',
      ],
      confidence: 0.0,
    );
  }

  String _getCurrentUserId() {
    // Return Firebase UID
    return currentUserId ?? 'anonymous';
  }

  /// Additional methods for Firebase Auth integration

  /// Sign out user
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Error signing out: $e');
      rethrow;
    }
  }

  /// Listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if current user's email is verified
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Send email verification
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Clear all data (for when user signs out)
  Future<void> clearUserData() async {
    try {
      // Call backend to clear user data
      await _dio.post('/api/clear_memory');
      print('✅ User data cleared from backend');
    } catch (e) {
      print('❌ Error clearing user data: $e');
    }
  }
}
