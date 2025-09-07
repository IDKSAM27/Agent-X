import 'agent_interface.dart';

/// Base agent implementation following Single Responsibility Principle
abstract class BaseAgent implements IAgent {
  @override
  String get agentName;

  @override
  String get agentDescription;

  @override
  List<String> get capabilities;

  /// Template method pattern for processing requests
  @override
  Future<AgentResponse> processRequest(AgentRequest request) async {
    // Validate request
    if (!canHandle(request)) {
      throw UnsupportedError('$agentName cannot handle this request');
    }

    // Pre-processing hook
    await preProcess(request);

    // Main processing
    final response = await handleRequest(request);

    // Post-processing hook
    final finalResponse = await postProcess(request, response);

    return finalResponse;
  }

  /// Abstract method for actual request handling
  Future<AgentResponse> handleRequest(AgentRequest request);

  /// Hook for pre-processing
  Future<void> preProcess(AgentRequest request) async {
    // Default implementation - can be overridden
  }

  /// Hook for post-processing
  Future<AgentResponse> postProcess(
      AgentRequest request,
      AgentResponse response
      ) async {
    // Default implementation - can be overridden
    return response;
  }

  /// Utility method for extracting keywords from message
  List<String> extractKeywords(String message) {
    return message
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(' ')
        .where((word) => word.length > 2)
        .toList();
  }

  /// Utility method for checking keyword matches
  bool hasKeywords(String message, List<String> keywords) {
    final messageWords = extractKeywords(message);
    return keywords.any((keyword) =>
        messageWords.any((word) => word.contains(keyword)));
  }
}
