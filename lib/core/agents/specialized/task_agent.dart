import '../base/base_agent.dart';
import '../base/agent_interface.dart';

/// Task Agent - Handles task management, to-dos, and productivity
class TaskAgent extends BaseAgent {
  @override
  String get agentName => 'TaskAgent';

  @override
  String get agentDescription =>
      'Manages tasks, to-dos, reminders, and productivity-related queries';

  @override
  List<String> get capabilities => [
    'Create tasks',
    'Manage to-do lists',
    'Set reminders',
    'Track project progress',
    'Productivity suggestions',
  ];

  final List<String> _taskKeywords = [
    'task', 'todo', 'reminder', 'deadline', 'project',
    'assignment', 'homework', 'work', 'complete', 'finish',
    'priority', 'urgent', 'schedule', 'plan', 'organize',
    'create task', 'add task', 'new task', 'make task',
    'task to', 'need to do', 'have to do'
  ];

  @override
  bool canHandle(AgentRequest request) {
    final message = request.message.toLowerCase();

    // Enhanced task detection
    if (hasKeywords(message, _taskKeywords)) return true;
    if (_hasTaskPattern(message)) return true;
    if (request.context['lastAgents']?.contains('TaskAgent') == true) return true;

    return false;
  }

  @override
  double getConfidenceScore(AgentRequest request) {
    final message = request.message.toLowerCase();
    double score = 0.0;

    // Enhanced scoring
    final matchedKeywords = _taskKeywords
        .where((keyword) => message.contains(keyword))
        .length;
    score += (matchedKeywords / _taskKeywords.length) * 0.7;

    // Pattern matching bonus
    if (_hasTaskPattern(message)) score += 0.2;

    // Context boost
    if (request.context['lastAgents']?.contains('TaskAgent') == true) {
      score += 0.1;
    }

    return score.clamp(0.0, 1.0);
  }

  @override
  Future<AgentResponse> handleRequest(AgentRequest request) async {
    final message = request.message.toLowerCase();

    // Analyze intent
    final taskIntent = _analyzeTaskIntent(message);

    switch (taskIntent) {
      case TaskIntent.create:
        return _createTask(request);
      case TaskIntent.list:
        return _listTasks(request);
      case TaskIntent.complete:
        return _completeTask(request);
      case TaskIntent.reminder:
        return _setReminder(request);
      case TaskIntent.productivity:
        return _providProductivityTips(request);
      default:
        return _handleGeneralTaskQuery(request);
    }
  }

  bool _hasTaskPattern(String message) {
    // Enhanced task patterns
    final patterns = [
      RegExp(r'(need to|have to|should|must).+(do|complete|finish)'),
      RegExp(r'(create|add|make).+(task|todo|reminder)'),
      RegExp(r'task.+to.+(finish|complete|do)'), // "task to finish" pattern
      RegExp(r'(remind me|set reminder)'),
      RegExp(r'(deadline|due date|due by)'),
    ];

    return patterns.any((pattern) => pattern.hasMatch(message));
  }

  TaskIntent _analyzeTaskIntent(String message) {
    if (message.contains('create') || message.contains('add')) {
      return TaskIntent.create;
    }
    if (message.contains('list') || message.contains('show') ||
        message.contains('what tasks')) {
      return TaskIntent.list;
    }
    if (message.contains('complete') || message.contains('done') ||
        message.contains('finished')) {
      return TaskIntent.complete;
    }
    if (message.contains('remind') || message.contains('reminder')) {
      return TaskIntent.reminder;
    }
    if (message.contains('productive') || message.contains('tips') ||
        message.contains('organize')) {
      return TaskIntent.productivity;
    }
    return TaskIntent.general;
  }

  Future<AgentResponse> _createTask(AgentRequest request) async {
    // Extract task details from message
    final taskTitle = _extractTaskTitle(request.message);
    final priority = _extractPriority(request.message);
    final deadline = _extractDeadline(request.message);

    // Create task (this would integrate with your backend)
    final task = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': taskTitle,
      'priority': priority,
      'deadline': deadline,
      'created': DateTime.now().toIso8601String(),
      'userId': request.userId,
    };

    return AgentResponse(
      agentName: agentName,
      response: '✅ Created task: "$taskTitle"\n'
          '📅 ${deadline != null ? "Due: ${deadline.toString().split(' ')[0]}" : "No deadline set"}\n'
          '🎯 Priority: ${priority.toString().split('.')[1]}',
      type: AgentResponseType.task,
      metadata: {
        'action': 'task_created',
        'task': task,
      },
      suggestedActions: [
        'Set a reminder',
        'Add more tasks',
        'View all tasks',
      ],
      confidence: 0.9,
    );
  }

  Future<AgentResponse> _listTasks(AgentRequest request) async {
    // This would fetch from your backend
    final mockTasks = [
      {'title': 'Complete Flutter project', 'priority': 'high', 'due': '2025-09-10'},
      {'title': 'Review code changes', 'priority': 'medium', 'due': '2025-09-08'},
      {'title': 'Update documentation', 'priority': 'low', 'due': '2025-09-12'},
    ];

    final taskList = mockTasks.map((task) =>
    '• ${task['title']} (${task['priority']}) - Due: ${task['due']}'
    ).join('\n');

    return AgentResponse(
      agentName: agentName,
      response: '📋 Your current tasks:\n\n$taskList\n\n'
          'Need help with any of these?',
      type: AgentResponseType.task,
      metadata: {
        'action': 'tasks_listed',
        'tasks': mockTasks,
      },
      suggestedActions: [
        'Mark task as complete',
        'Add new task',
        'Set reminders',
      ],
      confidence: 0.95,
    );
  }

  Future<AgentResponse> _completeTask(AgentRequest request) async {
    return AgentResponse(
      agentName: agentName,
      response: '🎉 Task completed! Great job staying productive.\n\n'
          'Would you like to:\n'
          '• Mark another task as complete\n'
          '• Add a new task\n'
          '• See your remaining tasks',
      type: AgentResponseType.task,
      metadata: {'action': 'task_completed'},
      suggestedActions: ['View remaining tasks', 'Add new task'],
      confidence: 0.85,
    );
  }

  Future<AgentResponse> _setReminder(AgentRequest request) async {
    return AgentResponse(
      agentName: agentName,
      response: '⏰ Reminder set! I\'ll notify you about this.\n\n'
          'Tip: You can set reminders for:\n'
          '• Specific times ("remind me at 3 PM")\n'
          '• Relative times ("remind me in 2 hours")\n'
          '• Dates ("remind me tomorrow")',
      type: AgentResponseType.task,
      metadata: {'action': 'reminder_set'},
      suggestedActions: ['Set another reminder', 'View all reminders'],
      confidence: 0.8,
    );
  }

  Future<AgentResponse> _providProductivityTips(AgentRequest request) async {
    final tips = [
      'Break large tasks into smaller, manageable chunks',
      'Use the Pomodoro Technique (25 min work, 5 min break)',
      'Prioritize tasks using the Eisenhower Matrix',
      'Set specific deadlines for better accountability',
      'Review and adjust your task list daily',
    ];

    final randomTip = tips[DateTime.now().millisecond % tips.length];

    return AgentResponse(
      agentName: agentName,
      response: '🚀 Productivity Tip:\n\n$randomTip\n\n'
          'Want more personalized productivity advice based on your ${request.profession} work?',
      type: AgentResponseType.suggestion,
      metadata: {'action': 'productivity_tip', 'tip': randomTip},
      suggestedActions: ['Get another tip', 'Create a task', 'Plan my day'],
      confidence: 0.7,
    );
  }

  Future<AgentResponse> _handleGeneralTaskQuery(AgentRequest request) async {
    return AgentResponse(
      agentName: agentName,
      response: 'I can help you with task management! I can:\n\n'
          '✅ Create and organize tasks\n'
          '⏰ Set reminders\n'
          '📋 Track your to-do list\n'
          '🎯 Provide productivity tips\n\n'
          'What would you like to do?',
      type: AgentResponseType.suggestion,
      metadata: {'action': 'task_help'},
      suggestedActions: [
        'Create a new task',
        'View my tasks',
        'Set a reminder',
        'Get productivity tips',
      ],
      confidence: 0.6,
    );
  }

  String _extractTaskTitle(String message) {
    // Simple extraction - in real implementation, use NLP
    final patterns = [
      RegExp(r'(create|add|make).+(task|todo)[\s:]+"([^"]+)"'),
      RegExp(r'(create|add|make).+(task|todo)[\s:]+(.+)'),
      RegExp(r'(need to|have to|should|must)\s+(.+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message.toLowerCase());
      if (match != null) {
        final title = match.group(match.groupCount)?.trim();
        if (title != null && title.isNotEmpty) {
          return title;
        }
      }
    }

    return 'New Task';
  }

  TaskPriority _extractPriority(String message) {
    if (message.contains('urgent') || message.contains('high priority')) {
      return TaskPriority.high;
    }
    if (message.contains('low priority') || message.contains('when i have time')) {
      return TaskPriority.low;
    }
    return TaskPriority.medium;
  }

  DateTime? _extractDeadline(String message) {
    // Simple deadline extraction
    final now = DateTime.now();

    if (message.contains('today')) {
      return now;
    }
    if (message.contains('tomorrow')) {
      return now.add(const Duration(days: 1));
    }
    if (message.contains('next week')) {
      return now.add(const Duration(days: 7));
    }

    return null; // No deadline specified
  }
}

enum TaskIntent {
  create,
  list,
  complete,
  reminder,
  productivity,
  general,
}

enum TaskPriority {
  low,
  medium,
  high,
}
