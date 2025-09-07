import '../../../models/chat_message.dart';

/// Base interface for all agents following Interface Segregation Principle
abstract class IAgent {
  String get agentName;
  String get agentDescription;
  List<String> get capabilities;

  /// Process a request and return a response
  Future<AgentResponse> processRequest(AgentRequest request);

  /// Check if this agent can handle the given request
  bool canHandle(AgentRequest request);

  /// Get confidence score for handling this request (0.0 to 1.0)
  double getConfidenceScore(AgentRequest request);
}

/// Enhanced request model for multi-agent system
class AgentRequest {
  final String message;
  final String userId;
  final String? profession;
  final Map<String, dynamic> context;
  final DateTime timestamp;
  final List<ChatMessage> conversationHistory;
  final AgentRequestType type;

  const AgentRequest({
    required this.message,
    required this.userId,
    this.profession,
    required this.context,
    required this.timestamp,
    required this.conversationHistory,
    this.type = AgentRequestType.general,
  });

  AgentRequest copyWith({
    String? message,
    String? userId,
    String? profession,
    Map<String, dynamic>? context,
    DateTime? timestamp,
    List<ChatMessage>? conversationHistory,
    AgentRequestType? type,
  }) {
    return AgentRequest(
      message: message ?? this.message,
      userId: userId ?? this.userId,
      profession: profession ?? this.profession,
      context: context ?? this.context,
      timestamp: timestamp ?? this.timestamp,
      conversationHistory: conversationHistory ?? this.conversationHistory,
      type: type ?? this.type,
    );
  }
}

enum AgentRequestType {
  general,
  task,
  learning,
  news,
  productivity,
  multiAgent,
}

/// Enhanced response model
class AgentResponse {
  final String agentName;
  final String response;
  final AgentResponseType type;
  final Map<String, dynamic> metadata;
  final List<String> suggestedActions;
  final List<String> involvedAgents;
  final double confidence;
  final bool requiresFollowUp;

  const AgentResponse({
    required this.agentName,
    required this.response,
    required this.type,
    this.metadata = const {},
    this.suggestedActions = const [],
    this.involvedAgents = const [],
    this.confidence = 1.0,
    this.requiresFollowUp = false,
  });
}

enum AgentResponseType {
  text,
  task,
  calendar,
  news,
  learning,
  multiAgent,
  suggestion,
}
