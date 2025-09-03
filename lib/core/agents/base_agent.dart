import 'package:equatable/equatable.dart';

abstract class BaseAgent {
  String get agentName;
  String get description;
  List<String> get capabilities;

  Future<AgentResponse> processRequest(AgentRequest request);
  bool canHandle(String intent);
}

class AgentRequest extends Equatable {
  final String message;
  final String userId;
  final Map<String, dynamic> context;
  final DateTime timestamp;

  const AgentRequest({
    required this.message,
    required this.userId,
    required this.context,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'message': message,
    'user_id': userId,
    'context': context,
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  List<Object?> get props => [message, userId, context, timestamp];
}

class AgentResponse extends Equatable {
  final String agentName;
  final String response;
  final AgentResponseType type;
  final Map<String, dynamic> metadata;
  final bool requiresFollowUp;
  final List<String>? suggestedActions;

  const AgentResponse({
    required this.agentName,
    required this.response,
    required this.type,
    this.metadata = const {},
    this.requiresFollowUp = false,
    this.suggestedActions,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      agentName: json['agent_name'] ?? 'Unknown',
      response: json['response'] ?? '',
      type: AgentResponseType.values.firstWhere(
            (e) => e.toString() == 'AgentResponseType.${json['type']}',
        orElse: () => AgentResponseType.text,
      ),
      metadata: json['metadata'] ?? {},
      requiresFollowUp: json['requires_follow_up'] ?? false,
      suggestedActions: json['suggested_actions']?.cast<String>(),
    );
  }

  @override
  List<Object?> get props => [agentName, response, type, metadata, requiresFollowUp, suggestedActions];
}

enum AgentResponseType {
  text,
  action,
  card,
  media,
  calendar,
  email,
}
