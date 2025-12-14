import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'briefing_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../core/notifications/notification_service.dart';

// Task names
const String taskFetchDailyBriefing = 'fetchDailyBriefing';
const String taskEventNotification = 'taskEventNotification';

// Define the callback dispatcher (must be top-level or static)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("Workmanager executing task: $task");

    try {
      // 1. Initialize Firebase (required for Auth/Services)
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 2. Initialize Timezones (required for Notifications mostly, but good practice)
      tz.initializeTimeZones();

      switch (task) {
        case taskFetchDailyBriefing:
          return await _handleFetchBriefingTask();
        case taskEventNotification:
          return await _handleEventNotificationTask(inputData);
        default:
          return Future.value(true);
      }
    } catch (e) {
      debugPrint("Workmanager Task Error: $e");
      return Future.value(false); // Task failed
    }
  });
}

Future<bool> _handleFetchBriefingTask() async {
  try {
    debugPrint("Starting background briefing fetch...");
    final briefingService = BriefingService();
    
    // Force refresh to get new data
    await briefingService.getBriefing(forceRefresh: true);
    
    debugPrint("Background briefing fetch successful!");
    
    // TRIGGER NOTIFICATION FROM HERE (RELIABLE)
    final notificationService = NotificationService();
    // Re-initialize for background isolate
    await notificationService.initialize();
    await notificationService.showImmediateBriefingNotification(
        "Daily Briefing Ready",
        "Your daily briefing is ready for you.",
    );
    
    return true;
  } catch (e) {
    debugPrint("Background briefing fetch failed: $e");
    return false;
  }
}

Future<bool> _handleEventNotificationTask(Map<String, dynamic>? inputData) async {
  if (inputData == null) return false;

  try {
    final String title = inputData['title'] ?? 'Event Reminder';
    final String body = inputData['body'] ?? 'You have an upcoming event.';
    final int id = inputData['id'] ?? 0;

    debugPrint("Handling background event notification: $title");

    final notificationService = NotificationService();
    await notificationService.initialize();
    
    // Use a specialized method or the generic one
    await notificationService.showImmediateEventNotification(
      id: id,
      title: title,
      body: body,
    );

    return true;
  } catch (e) {
    debugPrint("Background event notification failed: $e");
    return false;
  }
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode, // True prints logs to console
    );
    debugPrint("Workmanager initialized");
  }

  Future<void> scheduleBriefingFetch({
    required TimeOfDay notificationTime,
  }) async {
    final now = DateTime.now();
    
    // Calculate target fetch time (e.g. 15 minutes before notification)
    // WorkManager minimum frequency is 15 minutes for periodic, 
    // but for OneOff tasks we can use initialDelay.
    
    // Calculate initial delay
    var targetDate = DateTime(
      now.year,
      now.month,
      now.day,
      notificationTime.hour,
      notificationTime.minute,
    );

    // If target time is past, schedule for tomorrow
    if (targetDate.isBefore(now)) {
      targetDate = targetDate.add(const Duration(days: 1));
    }

    // Schedule for 5 minutes before target time (Since WorkManager triggers the notification)
    // We want the notification to appear roughly at 'notificationTime'.
    final fetchDate = targetDate.subtract(const Duration(minutes: 5));
    
    Duration initialDelay = fetchDate.difference(now);
    if (initialDelay.isNegative) {
        // If passed, run immediately
        initialDelay = const Duration(seconds: 10);
    }
    
    debugPrint("Scheduling background fetch in ${initialDelay.inMinutes} minutes (at $fetchDate)");

    // Cancel existing unique work to replace it
    await Workmanager().cancelByUniqueName(taskFetchDailyBriefing);

    await Workmanager().registerOneOffTask(
      taskFetchDailyBriefing,
      taskFetchDailyBriefing,
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected, // Need internet
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Future<void> scheduleEventWakeup({
    required int eventId,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String type, // 'morning' or 'pre'
  }) async {
    final now = DateTime.now();
    
    // Ensure we don't schedule in the past
    if (scheduledDate.isBefore(now)) {
      debugPrint("Skipping past event scheduling for $type");
      return;
    }

    final Duration initialDelay = scheduledDate.difference(now);
    final String uniqueName = 'event_${eventId}_$type';

    debugPrint("Scheduling reliable wakeup '$uniqueName' in ${initialDelay.inMinutes} mins");

    await Workmanager().registerOneOffTask(
      uniqueName,
      taskEventNotification,
      initialDelay: initialDelay,
      inputData: {
        'id': eventId,
        'title': title,
        'body': body,
      },
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        // BatteryNotLow might be too aggressive, let's keep it simple
      ),
    );
  }

  Future<void> cancelEventWakeup(int eventId) async {
    await Workmanager().cancelByUniqueName('event_${eventId}_morning');
    await Workmanager().cancelByUniqueName('event_${eventId}_pre');
  }
}
