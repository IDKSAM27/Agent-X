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

  /// Factory constructor for JSON deserialization
  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      agentName: json['agent_name'] ?? 'UnknownAgent',
      response: json['response'] ?? 'No response',
      type: _parseResponseType(json['type']),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      suggestedActions: List<String>.from(json['suggested_actions'] ?? []),
      involvedAgents: json['involved_agents'] != null
          ? List<String>.from(json['involved_agents'])
          : (json['agent_name'] != null ? [json['agent_name']] : ['UnknownAgent']),
      confidence: (json['confidence'] is double)
          ? json['confidence']
          : (json['confidence'] ?? 1.0).toDouble(),
      requiresFollowUp: json['requires_follow_up'] ?? false,
    );
  }

  /// Helper method to parse response type from string
  static AgentResponseType _parseResponseType(String? type) {
    switch (type?.toLowerCase()) {
      case 'task':
        return AgentResponseType.task;
      case 'calendar':
        return AgentResponseType.calendar;
      case 'news':
        return AgentResponseType.news;
      case 'learning':
        return AgentResponseType.learning;
      case 'multiagent':
        return AgentResponseType.multiAgent;
      case 'suggestion':
        return AgentResponseType.suggestion;
      case 'text':
      default:
        return AgentResponseType.text;
    }
  }
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
