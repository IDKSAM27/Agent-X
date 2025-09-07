import 'agent_interface.dart';
import '../specialized/task_agent.dart';

/// Coordinates multiple agents following Open/Closed Principle
class AgentCoordinator {
  final Map<String, IAgent> _agents = {};
  final List<String> _agentPriority = [];

  AgentCoordinator() {
    _initializeAgents();
  }

  void _initializeAgents() {
    // Register agents
    registerAgent(TaskAgent());
    // More agents will be added in subsequent days
  }

  /// Register a new agent (Open for extension)
  void registerAgent(IAgent agent) {
    _agents[agent.agentName] = agent;
    if (!_agentPriority.contains(agent.agentName)) {
      _agentPriority.add(agent.agentName);
    }
  }

  /// Find the best agent(s) for handling a request
  Future<List<IAgent>> selectBestAgents(AgentRequest request) async {
    final candidateAgents = <IAgent>[];
    final scores = <IAgent, double>{};

    // Evaluate all agents
    for (final agent in _agents.values) {
      if (agent.canHandle(request)) {
        final score = agent.getConfidenceScore(request);
        candidateAgents.add(agent);
        scores[agent] = score;
      }
    }

    // Sort by confidence score
    candidateAgents.sort((a, b) =>
        (scores[b] ?? 0.0).compareTo(scores[a] ?? 0.0));

    // Return top agents (for now, just the best one)
    return candidateAgents.take(1).toList();
  }

  /// Process request with the best agent
  Future<AgentResponse> processRequest(AgentRequest request) async {
    final selectedAgents = await selectBestAgents(request);

    if (selectedAgents.isEmpty) {
      return _fallbackResponse(request);
    }

    // For now, use single agent processing
    // Multi-agent collaboration will be added later
    final primaryAgent = selectedAgents.first;

    try {
      final response = await primaryAgent.processRequest(request);

      // Update context with agent information
      final enhancedResponse = AgentResponse(
        agentName: response.agentName,
        response: response.response,
        type: response.type,
        metadata: {
          ...response.metadata,
          'coordinator_used': true,
          'selected_agents': selectedAgents.map((a) => a.agentName).toList(),
        },
        suggestedActions: response.suggestedActions,
        involvedAgents: [response.agentName],
        confidence: response.confidence,
        requiresFollowUp: response.requiresFollowUp,
      );

      return enhancedResponse;
    } catch (e) {
      return _errorResponse(request, e.toString());
    }
  }

  AgentResponse _fallbackResponse(AgentRequest request) {
    return const AgentResponse(
      agentName: 'GeneralAgent',
      response: 'I understand your message, but I\'m not sure how to help with that specific request. Could you provide more details or try rephrasing?',
      type: AgentResponseType.text,
      confidence: 0.3,
      suggestedActions: [
        'Ask about tasks',
        'Ask about calendar',
        'Ask for help',
      ],
    );
  }

  AgentResponse _errorResponse(AgentRequest request, String error) {
    return AgentResponse(
      agentName: 'SystemAgent',
      response: 'I encountered an issue processing your request. Please try again.',
      type: AgentResponseType.text,
      metadata: {'error': error},
      confidence: 0.0,
    );
  }

  /// Get list of available agents and their capabilities
  Map<String, List<String>> getAgentCapabilities() {
    return _agents.map((name, agent) =>
        MapEntry(name, agent.capabilities));
  }
}
