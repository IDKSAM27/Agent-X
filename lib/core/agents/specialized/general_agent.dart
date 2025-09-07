import '../base/base_agent.dart';
import '../base/agent_interface.dart';

/// General Agent - Handles greetings, personal info, and fallback queries
class GeneralAgent extends BaseAgent {
  @override
  String get agentName => 'GeneralAgent';

  @override
  String get agentDescription =>
      'Handles greetings, personal information, and general conversation';

  @override
  List<String> get capabilities => [
    'Greetings and pleasantries',
    'Personal information management',
    'General conversation',
    'Fallback responses',
    'User profile management',
  ];

  final List<String> _greetingKeywords = [
    'hi', 'hello', 'hey', 'good morning', 'good afternoon',
    'good evening', 'greetings', 'howdy', 'sup'
  ];

  final List<String> _personalInfoKeywords = [
    'my name', 'i am', 'call me', 'name is', 'what is my name',
    'who am i', 'my profession', 'what do i do'
  ];

  @override
  bool canHandle(AgentRequest request) {
    final message = request.message.toLowerCase();

    // Always can handle as fallback (but with lower confidence)
    if (_isGreeting(message)) return true;
    if (_isPersonalInfo(message)) return true;
    if (_isGeneralQuery(message)) return true;

    return true; // General agent can handle anything as fallback
  }

  @override
  double getConfidenceScore(AgentRequest request) {
    final message = request.message.toLowerCase();
    double score = 0.0;

    // High confidence for specific patterns
    if (_isGreeting(message)) score = 0.9;
    else if (_isPersonalInfo(message)) score = 0.8;
    else if (_isGeneralQuery(message)) score = 0.6;
    else score = 0.3; // Low confidence for fallback

    return score;
  }

  @override
  Future<AgentResponse> handleRequest(AgentRequest request) async {
    final message = request.message.toLowerCase();

    if (_isGreeting(message)) {
      return _handleGreeting(request);
    } else if (_isPersonalInfo(message)) {
      return _handlePersonalInfo(request);
    } else if (_isGeneralQuery(message)) {
      return _handleGeneralQuery(request);
    } else {
      return _handleFallback(request);
    }
  }

  bool _isGreeting(String message) {
    return _greetingKeywords.any((keyword) => message.contains(keyword));
  }

  bool _isPersonalInfo(String message) {
    return _personalInfoKeywords.any((keyword) => message.contains(keyword));
  }

  bool _isGeneralQuery(String message) {
    final generalPatterns = [
      'how are you', 'what can you do', 'help', 'what is',
      'tell me', 'explain', 'how to', 'why'
    ];
    return generalPatterns.any((pattern) => message.contains(pattern));
  }

  Future<AgentResponse> _handleGreeting(AgentRequest request) async {
    final greetings = [
      "Hello! I'm Agent X, your ${request.profession ?? 'personal'} AI assistant. How can I help you today?",
      "Hi there! Great to see you again. What would you like to work on?",
      "Hey! Ready to be productive? I'm here to help with anything you need.",
    ];

    final greeting = greetings[DateTime.now().millisecond % greetings.length];

    return AgentResponse(
      agentName: agentName,
      response: greeting,
      type: AgentResponseType.text,
      metadata: {'intent': 'greeting'},
      suggestedActions: [
        'Create a task',
        'Check my schedule',
        'Get news updates',
        'Learn something new',
      ],
      confidence: 0.9,
    );
  }

  Future<AgentResponse> _handlePersonalInfo(AgentRequest request) async {
    final message = request.message.toLowerCase();

    // Check if user is providing their name
    if (message.contains('my name is') || message.contains('i am') || message.contains('call me')) {
      final name = _extractName(message);
      if (name.isNotEmpty) {
        // Store name in context/memory (would integrate with your memory system)
        return AgentResponse(
          agentName: agentName,
          response: "Nice to meet you, $name! I'll remember that. "
              "I'm here to help you with your ${request.profession ?? 'work'}. "
              "What would you like to do today?",
          type: AgentResponseType.text,
          metadata: {
            'intent': 'name_provided',
            'name': name,
            'action': 'store_user_name'
          },
          suggestedActions: [
            'Create a task',
            'Get productivity tips',
            'Check what I can help with',
          ],
          confidence: 0.8,
        );
      }
    }

    // Check if user is asking for their name
    if (message.contains('what is my name') || message.contains('who am i')) {
      // Would fetch from memory system
      return AgentResponse(
        agentName: agentName,
        response: "I don't have your name stored yet. You can tell me by saying "
            "'My name is [your name]' and I'll remember it for our future conversations!",
        type: AgentResponseType.text,
        metadata: {'intent': 'name_query'},
        suggestedActions: [
          'Tell me your name',
          'Ask what I can help with',
        ],
        confidence: 0.8,
      );
    }

    return _handleGeneralQuery(request);
  }

  Future<AgentResponse> _handleGeneralQuery(AgentRequest request) async {
    return AgentResponse(
      agentName: agentName,
      response: "I'm your ${request.profession ?? 'personal'} AI assistant! I can help you with:\n\n"
          "📋 **Task Management** - Create and track tasks\n"
          "📅 **Calendar & Scheduling** - Manage your time\n"
          "📧 **Communication** - Handle emails and messages\n"
          "📚 **Learning** - Get explanations and tutorials\n"
          "📰 **News & Updates** - Stay informed in your field\n\n"
          "What would you like to start with?",
      type: AgentResponseType.suggestion,
      metadata: {'intent': 'general_help'},
      suggestedActions: [
        'Create a task for today',
        'Get ${request.profession?.toLowerCase() ?? 'industry'} news',
        'Learn something new',
        'Plan my schedule',
      ],
      confidence: 0.6,
    );
  }

  Future<AgentResponse> _handleFallback(AgentRequest request) async {
    return AgentResponse(
      agentName: agentName,
      response: "I understand you're trying to communicate something, but I'm not quite sure how to help with that. "
          "Could you try rephrasing your request? I'm here to assist with tasks, scheduling, learning, and general questions about your ${request.profession?.toLowerCase() ?? 'work'}.",
      type: AgentResponseType.text,
      metadata: {'intent': 'fallback'},
      suggestedActions: [
        'Ask "What can you do?"',
        'Say "Help me create a task"',
        'Try "Show me my options"',
      ],
      confidence: 0.3,
    );
  }

  String _extractName(String message) {
    // Simple name extraction patterns
    final patterns = [
      RegExp(r'my name is (\w+)', caseSensitive: false),
      RegExp(r'i am (\w+)', caseSensitive: false),
      RegExp(r'call me (\w+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        return match.group(1)?.trim().toLowerCase().split(' ').map((word) =>
        word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : word
        ).join(' ') ?? '';
      }
    }

    return '';
  }
}
