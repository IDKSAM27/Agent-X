import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationConfig {
  static const String channelId = 'agent_x_high_importance_channel';
  static const String channelName = 'Agent X High Importance';
  static const String channelDescription = 'This channel is used for important notifications.';
  
  static const String scheduledChannelId = 'scheduled_channel_v2';
  static const String scheduledChannelName = 'Scheduled Notifications V2';
  static const String scheduledChannelDescription = 'Notifications for scheduled events.';

  static const AndroidNotificationChannel highImportanceChannel = AndroidNotificationChannel(
    channelId,
    channelName,
    description: channelDescription,
    importance: Importance.max,
    playSound: true,
  );
  
  static const AndroidNotificationChannel scheduledChannel = AndroidNotificationChannel(
    scheduledChannelId,
    scheduledChannelName,
    description: scheduledChannelDescription,
    importance: Importance.high,
    playSound: true,
  );
}

class NotificationType {
  static const String eventMorning = 'event_morning';
  static const String eventPreStart = 'event_pre_start'; // 30 mins before
  static const String taskDue = 'task_due';
  static const String general = 'general';
}
