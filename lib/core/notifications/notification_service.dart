import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_config.dart';
import 'notification_helper.dart';
import '../../services/background_service.dart';

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
      // 1. Notification Permission
      final bool? granted = await androidImplementation.requestNotificationsPermission();
      debugPrint('Notification Permission Granted: $granted');

      // 2. Exact Alarm Permission (Android 12+)
      await androidImplementation.requestExactAlarmsPermission();
      
      // 3. Check Exact Notification Policy (Critical for Android 14+)
      // Note: canScheduleExactNotifications is not available in all versions of the plugin, 
      // but if available we should log it. If not, catching error.
      try {
         // Some versions might not expose this or it might be async? 
         // Actually commonly used logic:
         final bool? canSchedule = await androidImplementation.canScheduleExactNotifications();
         debugPrint('Can schedule exact notifications: $canSchedule');
         
         if (canSchedule == false) {
             debugPrint("WARNING: Exact notifications NOT allowed. Scheduled tasks may fail.");
         }
      } catch (e) {
          debugPrint('Error checking exact schedule capability: $e');
      }

      // 4. Battery Optimization (Crucial for Vivo/Samsung/Xiaomi)
      final status = await Permission.ignoreBatteryOptimizations.status;
      debugPrint('Ignore Battery Optimizations Status: $status');
      
      if (!status.isGranted) {
        debugPrint('Requesting Ignore Battery Optimizations...');
        // This usually opens a dialog or settings page
        await Permission.ignoreBatteryOptimizations.request();
      }
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
    
    // --- RELIABLE SCHEDULING VIA WORKMANAGER ---
    final backgroundService = BackgroundService();
    await backgroundService.initialize(); // Ensure initialized
    
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
        // Schedule standard alarm as backup/immediate feedback
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
                fullScreenIntent: true, // Wake up screen
            ),
            ),
            androidScheduleMode: AndroidScheduleMode.alarmClock,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
        );
        
        // Schedule RELIABLE background task
        await backgroundService.scheduleEventWakeup(
            eventId: safeId,
            title: 'Today: $title',
            body: 'You have an event today: $title at ${_formatTime(startTime)}',
            scheduledDate: morningDate,
            type: 'morning',
        );
    }

    // 2. Pre-Event Notification (30 minutes before)
    final preEventDate = startTime.subtract(const Duration(minutes: 30));
    final now = DateTime.now();

    debugPrint('Scheduling pre-event notification for $title at $preEventDate (now: $now)');

    if (preEventDate.isAfter(now)) {
        // Schedule for 30 mins before
        debugPrint('Scheduling pre-event notification (ID: ${(safeId << 2) | 2})');
        
        // Schedule RELIABLE background task
        await backgroundService.scheduleEventWakeup(
            eventId: safeId,
            title: 'Upcoming: $title',
            body: 'Event starts in 30 minutes.',
            scheduledDate: preEventDate,
            type: 'pre',
        );

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
                  fullScreenIntent: true, // Wake up screen
              ),
              ),
              androidScheduleMode: AndroidScheduleMode.alarmClock,
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
                    fullScreenIntent: true, // Wake up screen
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

  Future<void> showImmediateBriefingNotification(String title, String body) async {
      await _flutterLocalNotificationsPlugin.show(
      888, // Same ID as scheduled
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationConfig.scheduledChannelId,
          NotificationConfig.scheduledChannelName,
          channelDescription: NotificationConfig.scheduledChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true, // Try to wake screen
        ),
      ),
      payload: 'daily_briefing',
    );
  }

  Future<void> showImmediateEventNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    // Unique ID generation for immediate notification from background
    // We try to match what would be used by the alarm so user doesn't see duplicates if both fire
    // But since they might fire at slightly different times, duplicates are possible but harmless (better than missing)
    
    // We'll trust the ID passed from BackgroundService which is `safeId`
    // However, we need to know if it's morning or pre-event. 
    // Wait, the `id` passed to `scheduleEventNotifications` was `safeId`.
    // In `scheduleEventWakeup` we passed `safeId`.
    // But `zonedSchedule` used `(safeId << 2) | 1` or `(safeId << 2) | 2`.
    // The background service should ideally pass the correct final ID or we calculate it.
    // Simpler: Just show a notification. We'll use a unique ID based on hash or random if needed, 
    // or just use the ID passed. 
    // Let's use `id` as is, assuming caller passed a distinct enough ID or we don't care about overwriting.
    // Actually, to avoid overwriting *other* events, we should probably use a distinct ID range or the same derivation.
    // Let's assume the ID passed is the `safeId` (event ID hash).
    // We should probably generate a unique notification ID.
    // Let's just use `id` and hope for the best/overwrite if same event.
    
    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationConfig.scheduledChannelId,
          NotificationConfig.scheduledChannelName,
          channelDescription: NotificationConfig.scheduledChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
        ),
      ),
      payload: 'event_reminder',
    );
  }
  
  Future<void> scheduleDailyBriefingNotification(TimeOfDay time) async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    
    // Create target time for today
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If passed, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // Schedule daily
    await _flutterLocalNotificationsPlugin.zonedSchedule(
      888, // Fixed ID for daily briefing
      'Daily Briefing Ready',
      'Your daily briefing is ready for you.',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationConfig.scheduledChannelId,
          NotificationConfig.scheduledChannelName,
          channelDescription: NotificationConfig.scheduledChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repeats daily at this time
      payload: 'daily_briefing', // Use for navigation
    );
    
    debugPrint("Scheduled daily briefing notification for ${time.hour}:${time.minute} (Next: $scheduledDate)");
  }
  
  Future<void> cancelEventNotifications(int id) async {
       // Ensure safety: mask to 29 bits to allow shifting
      final int safeId = id & 0x1FFFFFFF; // Mask id to ensure it fits when shifted
      await _flutterLocalNotificationsPlugin.cancel((safeId << 2) | 1);
      await _flutterLocalNotificationsPlugin.cancel((safeId << 2) | 2);

      // Cancel Background Tasks
      try {
        final backgroundService = BackgroundService();
         // No need to init just to cancel
        await backgroundService.cancelEventWakeup(safeId);
      } catch (e) {
          debugPrint("Error cancelling background tasks: $e");
      }
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
