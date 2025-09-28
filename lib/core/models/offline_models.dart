import 'dart:convert';

enum SyncStatus {
  synced,
  pending,
  conflict,
  error,
}

enum SyncAction {
  create,
  update,
  delete,
}

class OfflineTask {
  final String id;
  final String? serverId;
  final String title;
  final String description;
  final String priority;
  final String category;
  final DateTime? dueDate;
  final bool isCompleted;
  final double progress;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final Map<String, dynamic>? conflictData;
  final bool isDeleted;

  OfflineTask({
    required this.id,
    this.serverId,
    required this.title,
    required this.description,
    required this.priority,
    required this.category,
    this.dueDate,
    required this.isCompleted,
    required this.progress,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    this.conflictData,
    required this.isDeleted,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'title': title,
      'description': description,
      'priority': priority,
      'category': category,
      'due_date': dueDate?.toIso8601String(),
      'is_completed': isCompleted ? 1 : 0,
      'progress': progress,
      'tags': jsonEncode(tags),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.name,
      'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory OfflineTask.fromMap(Map<String, dynamic> map) {
    return OfflineTask(
      id: map['id'],
      serverId: map['server_id'],
      title: map['title'],
      description: map['description'] ?? '',
      priority: map['priority'],
      category: map['category'],
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      isCompleted: map['is_completed'] == 1,
      progress: map['progress']?.toDouble() ?? 0.0,
      tags: List<String>.from(jsonDecode(map['tags'] ?? '[]')),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      syncStatus: SyncStatus.values.firstWhere(
            (e) => e.name == map['sync_status'],
        orElse: () => SyncStatus.synced,
      ),
      conflictData: map['conflict_data'] != null ? jsonDecode(map['conflict_data']) : null,
      isDeleted: map['is_deleted'] == 1,
    );
  }

  OfflineTask copyWith({
    String? title,
    String? description,
    String? priority,
    String? category,
    DateTime? dueDate,
    bool? isCompleted,
    double? progress,
    List<String>? tags,
    SyncStatus? syncStatus,
    Map<String, dynamic>? conflictData,
    bool? isDeleted,
  }) {
    return OfflineTask(
      id: id,
      serverId: serverId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      progress: progress ?? this.progress,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      syncStatus: syncStatus ?? this.syncStatus,
      conflictData: conflictData ?? this.conflictData,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class OfflineEvent {
  final String id;
  final String? serverId;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime? endTime;
  final String category;
  final String priority;
  final String? location;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final Map<String, dynamic>? conflictData;
  final bool isDeleted;

  OfflineEvent({
    required this.id,
    this.serverId,
    required this.title,
    required this.description,
    required this.startTime,
    this.endTime,
    required this.category,
    required this.priority,
    this.location,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    this.conflictData,
    required this.isDeleted,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'title': title,
      'description': description,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'category': category,
      'priority': priority,
      'location': location,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.name,
      'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory OfflineEvent.fromMap(Map<String, dynamic> map) {
    return OfflineEvent(
      id: map['id'],
      serverId: map['server_id'],
      title: map['title'],
      description: map['description'] ?? '',
      startTime: DateTime.parse(map['start_time']),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
      category: map['category'],
      priority: map['priority'],
      location: map['location'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      syncStatus: SyncStatus.values.firstWhere(
            (e) => e.name == map['sync_status'],
        orElse: () => SyncStatus.synced,
      ),
      conflictData: map['conflict_data'] != null ? jsonDecode(map['conflict_data']) : null,
      isDeleted: map['is_deleted'] == 1,
    );
  }

  OfflineEvent copyWith({
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    String? category,
    String? priority,
    String? location,
    SyncStatus? syncStatus,
    Map<String, dynamic>? conflictData,
    bool? isDeleted,
  }) {
    return OfflineEvent(
      id: id,
      serverId: serverId,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      location: location ?? this.location,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      syncStatus: syncStatus ?? this.syncStatus,
      conflictData: conflictData ?? this.conflictData,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class SyncQueueItem {
  final int? id;
  final String entityType;
  final String entityId;
  final SyncAction action;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  SyncQueueItem({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.data,
    required this.createdAt,
    required this.retryCount,
    this.lastError,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'action': action.name,
      'data': jsonEncode(data),
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'last_error': lastError,
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'],
      entityType: map['entity_type'],
      entityId: map['entity_id'],
      action: SyncAction.values.firstWhere((e) => e.name == map['action']),
      data: jsonDecode(map['data']),
      createdAt: DateTime.parse(map['created_at']),
      retryCount: map['retry_count'],
      lastError: map['last_error'],
    );
  }
}
