/// Advanced intent classifier for multi-agent routing
class IntentClassifier {
  static const Map<String, List<String>> intentKeywords = {
    'greeting': ['hi', 'hello', 'hey', 'good morning', 'good afternoon'],
    'personal_info': ['my name', 'i am', 'who am i', 'call me'],
    'task_management': ['task', 'todo', 'reminder', 'complete', 'deadline'],
    'calendar': ['schedule', 'meeting', 'appointment', 'calendar', 'book'],
    'learning': ['learn', 'explain', 'how to', 'what is', 'tutorial'],
    'news': ['news', 'updates', 'latest', 'happening', 'current'],
    'help': ['help', 'what can you do', 'capabilities', 'options'],
  };

  static IntentClassificationResult classifyIntent(String message) {
    final lowercaseMessage = message.toLowerCase();
    final Map<String, double> intentScores = {};

    // Calculate scores for each intent
    for (final intent in intentKeywords.keys) {
      final keywords = intentKeywords[intent]!;
      int matches = 0;

      for (final keyword in keywords) {
        if (lowercaseMessage.contains(keyword)) {
          matches++;
        }
      }

      final score = matches / keywords.length;
      if (score > 0) {
        intentScores[intent] = score;
      }
    }

    // Find highest scoring intent
    if (intentScores.isEmpty) {
      return IntentClassificationResult(
        intent: 'fallback',
        confidence: 0.2,
        allScores: {'fallback': 0.2},
      );
    }

    final topIntent = intentScores.entries
        .reduce((a, b) => a.value > b.value ? a : b);

    return IntentClassificationResult(
      intent: topIntent.key,
      confidence: topIntent.value,
      allScores: intentScores,
    );
  }
}

class IntentClassificationResult {
  final String intent;
  final double confidence;
  final Map<String, double> allScores;

  IntentClassificationResult({
    required this.intent,
    required this.confidence,
    required this.allScores,
  });
}
