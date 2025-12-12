import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';
import 'notification_config.dart';
import 'notification_helper.dart';

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // 1. Initialize Timezones
    await NotificationHelper.initializeTimeZones();

    // 2. Android Initialization Settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 3. iOS Initialization Settings
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // 4. Combined Initialization Settings
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    // 5. Initialize Plugin
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Handle notification tap
        debugPrint('Notification tapped with payload: ${response.payload}');
      },
    );

    // 6. Create Notification Channels (Android)
    await _createNotificationChannels();
  }

  Future<void> _createNotificationChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation
          .createNotificationChannel(NotificationConfig.highImportanceChannel);
      await androidImplementation
          .createNotificationChannel(NotificationConfig.scheduledChannel);
    }
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final bool? granted = await androidImplementation.requestNotificationsPermission();
      debugPrint('Notification Permission Granted: $granted');
      
      // Request exact alarms permission (Android 12+)
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  // --- Scheduling Logic ---

  Future<void> scheduleEventNotifications({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required DateTime startTime,
  }) async {
    // Ensure safety: mask to 29 bits to allow shifting
    final int safeId = id & 0x1FFFFFFF;
    
    // 1. Morning Notification (8:00 AM on the day of event)
    final morningDate = DateTime(
      eventDate.year,
      eventDate.month,
      eventDate.day,
      8, // 8:00 AM
      0,
    );

    // Only schedule if the time is in the future
    if (morningDate.isAfter(DateTime.now())) {
        await _flutterLocalNotificationsPlugin.zonedSchedule(
            (safeId << 2) | 1, // Unique ID for morning
            'Today: $title',
            'You have an event today: $title at ${_formatTime(startTime)}',
            tz.TZDateTime.from(morningDate, tz.local),
            const NotificationDetails(
            android: AndroidNotificationDetails(
                NotificationConfig.scheduledChannelId,
                NotificationConfig.scheduledChannelName,
                channelDescription: NotificationConfig.scheduledChannelDescription,
                importance: Importance.high,
                priority: Priority.high,
            ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
        );
    }

    // 2. Pre-Event Notification (30 minutes before)
    final preEventDate = startTime.subtract(const Duration(minutes: 30));
    final now = DateTime.now();

    debugPrint('Scheduling pre-event notification for $title at $preEventDate (now: $now)');

    if (preEventDate.isAfter(now)) {
        // Schedule for 30 mins before
        debugPrint('Scheduling pre-event notification (ID: ${(safeId << 2) | 2})');
        try {
          await _flutterLocalNotificationsPlugin.zonedSchedule(
              (safeId << 2) | 2, // Unique ID for pre-event
              'Upcoming: $title',
              'Configured to start in 30 minutes.',
              tz.TZDateTime.from(preEventDate, tz.local),
              const NotificationDetails(
              android: AndroidNotificationDetails(
                  NotificationConfig.scheduledChannelId,
                  NotificationConfig.scheduledChannelName,
                  channelDescription: NotificationConfig.scheduledChannelDescription,
                  importance: Importance.high,
                  priority: Priority.high,
              ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (e) {
          debugPrint('Error scheduling pre-event notification: $e');
        }
    } else if (startTime.isAfter(now)) {
        // Event is within 30 minutes! Schedule closer to now.
        final diff = startTime.difference(now);
        final minutes = diff.inMinutes; // e.g. 15
        
        debugPrint('Event within 30 mins ($minutes mins). Showing immediate notification.');
        
        try {
            await _flutterLocalNotificationsPlugin.show(
              (safeId << 2) | 2, // Reuse same ID slot
              'Upcoming: $title',
              'Event starts in ${minutes > 0 ? minutes : "less than 1"} minutes!',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                    NotificationConfig.scheduledChannelId,
                    NotificationConfig.scheduledChannelName,
                    channelDescription: NotificationConfig.scheduledChannelDescription,
                    importance: Importance.high,
                    priority: Priority.high,
                ),
              ),
            );
            debugPrint('Successfully showed immediate notification');
        } catch (e) {
             debugPrint('Error showing immediate pre-event notification: $e');
        }
    } else {
        debugPrint('Skipping pre-event notification as event has already started/passed');
    }
  }
  
  Future<void> cancelEventNotifications(int id) async {
       // Ensure safety: mask to 29 bits to allow shifting
      final int safeId = id & 0x1FFFFFFF; // Mask id to ensure it fits when shifted
      await _flutterLocalNotificationsPlugin.cancel((safeId << 2) | 1);
      await _flutterLocalNotificationsPlugin.cancel((safeId << 2) | 2);
  }

  Future<void> cancelAll() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  // Helper
  String _formatTime(DateTime time) {
    // Simple formatter, can use DateFormat from intl if available
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}
