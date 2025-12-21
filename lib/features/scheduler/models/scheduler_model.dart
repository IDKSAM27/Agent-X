class ScheduleItem {
  final String day;
  final String startTime;
  final String endTime;
  final String subject;
  final String type;
  final String? location;

  ScheduleItem({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.subject,
    required this.type,
    this.location,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      day: json['day'] ?? '',
      startTime: json['start_time'] ?? '',
      endTime: json['end_time'] ?? '',
      subject: json['subject'] ?? '',
      type: json['type'] ?? 'class',
      location: json['location'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'start_time': startTime,
      'end_time': endTime,
      'subject': subject,
      'type': type,
      'location': location,
    };
  }
}

class Schedule {
  final int? id;
  final String name;
  final String type;
  final List<ScheduleItem> items;
  final String? createdAt;

  Schedule({
    this.id,
    required this.name,
    required this.type,
    required this.items,
    this.createdAt,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List;
    List<ScheduleItem> items = itemsList.map((i) => ScheduleItem.fromJson(i)).toList();

    return Schedule(
      id: json['id'],
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      items: items,
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'items': items.map((e) => e.toJson()).toList(),
      if (createdAt != null) 'created_at': createdAt,
    };
  }
}
