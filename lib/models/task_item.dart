import 'package:flutter/material.dart';

class TaskItem {
  final String id;
  final String title;
  final String description;
  final String priority;
  final String category; // work, personal, urgent, etc.
  final DateTime? dueDate;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final double progress; // 0.0 to 1.0

  TaskItem({
    required this.id,
    required this.title,
    this.description = '',
    this.priority = 'medium',
    this.category = 'general',
    this.dueDate,
    this.isCompleted = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.tags = const [],
    this.progress = 0.0,
  }) : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Get priority color
  Color get priorityColor {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Get priority icon
  IconData get priorityIcon {
    switch (priority) {
      case 'high':
        return Icons.priority_high;
      case 'medium':
        return Icons.remove;
      case 'low':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.circle;
    }
  }

  // Check if overdue
  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  // Get due status
  String get dueStatus {
    if (dueDate == null) return '';
    if (isCompleted) return 'Completed';

    final now = DateTime.now();
    final difference = dueDate!.difference(now);

    if (difference.isNegative) return 'Overdue';
    if (difference.inDays == 0) return 'Due today';
    if (difference.inDays == 1) return 'Due tomorrow';
    if (difference.inDays < 7) return 'Due in ${difference.inDays} days';

    return 'Due ${dueDate!.day}/${dueDate!.month}/${dueDate!.year}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'priority': priority,
      'category': category,
      'dueDate': dueDate?.toIso8601String(),
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'tags': tags,
      'progress': progress,
    };
  }

  factory TaskItem.fromMap(Map<String, dynamic> map) {
    return TaskItem(
      id: map['id'],
      title: map['title'],
      description: map['description'] ?? '',
      priority: map['priority'] ?? 'medium',
      category: map['category'] ?? 'general',
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      isCompleted: map['isCompleted'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
      tags: List<String>.from(map['tags'] ?? []),
      progress: map['progress'] ?? 0.0,
    );
  }

  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    String? priority,
    String? category,
    DateTime? dueDate,
    bool? isCompleted,
    List<String>? tags,
    double? progress,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      tags: tags ?? this.tags,
      progress: progress ?? this.progress,
    );
  }
}
