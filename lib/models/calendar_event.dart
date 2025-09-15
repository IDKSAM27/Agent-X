import 'package:flutter/material.dart';

class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime? endTime;
  final String category;
  final String priority;
  final Color color;
  final bool isAllDay;
  final String? location;
  final DateTime createdAt;
  final DateTime updatedAt;

  CalendarEvent({
    required this.id,
    required this.title,
    this.description = '',
    required this.startTime,
    this.endTime,
    this.category = 'general',
    this.priority = 'medium',
    this.color = const Color(0xFF2196F3),
    this.isAllDay = false,
    this.location,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Get formatted date
  String get formattedDate {
    return '${startTime.day}/${startTime.month}/${startTime.year}';
  }

  // Get formatted time
  String get formattedTime {
    if (isAllDay) return 'All Day';
    final hour = startTime.hour.toString().padLeft(2, '0');
    final minute = startTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Get formatted duration
  String get formattedDuration {
    if (isAllDay || endTime == null) return '';
    final duration = endTime!.difference(startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'category': category,
      'priority': priority,
      'color': color.value,
      'isAllDay': isAllDay,
      'location': location,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CalendarEvent.fromMap(Map<String, dynamic> map) {
    return CalendarEvent(
      id: map['id'],
      title: map['title'],
      description: map['description'] ?? '',
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      category: map['category'] ?? 'general',
      priority: map['priority'] ?? 'medium',
      color: Color(map['color'] ?? 0xFF2196F3),
      isAllDay: map['isAllDay'] ?? false,
      location: map['location'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    String? category,
    String? priority,
    Color? color,
    bool? isAllDay,
    String? location,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      color: color ?? this.color,
      isAllDay: isAllDay ?? this.isAllDay,
      location: location ?? this.location,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
