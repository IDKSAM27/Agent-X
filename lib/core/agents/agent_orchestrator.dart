// Update your existing AgentOrchestrator to use the new system
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../agents/base/agent_coordinator.dart';
import '../agents/base/agent_interface.dart';

class AgentOrchestrator {
  final Dio _dio;
  final AgentCoordinator _coordinator = AgentCoordinator();

  AgentOrchestrator() : _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    headers: ApiConfig.defaultHeaders,
  ));

  Future<AgentResponse> processRequest(String message, {String? profession}) async {
    try {
      // Build enhanced request
      final request = AgentRequest(
        message: message,
        userId: _getCurrentUserId(),
        profession: profession,
        context: await _buildEnhancedContext(profession),
        timestamp: DateTime.now(),
        conversationHistory: [], // Will be populated later
      );

      // Use coordinator to process
      final response = await _coordinator.processRequest(request);

      return response;
    } catch (e) {
      return AgentResponse(
        agentName: 'ErrorAgent',
        response: 'Sorry, I encountered an error. Please try again.',
        type: AgentResponseType.text,
        metadata: {'error': e.toString()},
      );
    }
  }

  Future<Map<String, dynamic>> _buildEnhancedContext(String? profession) async {
    return {
      'profession': profession ?? 'Unknown',
      'timestamp': DateTime.now().toIso8601String(),
      'capabilities': _coordinator.getAgentCapabilities(),
    };
  }

  String _getCurrentUserId() => 'user_123'; // Replace with actual user ID
}
