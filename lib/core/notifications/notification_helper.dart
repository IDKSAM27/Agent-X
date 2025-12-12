import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';

class NotificationHelper {
  static bool _initialized = false;

  static Future<void> initializeTimeZones() async {
    if (!_initialized) {
      tz.initializeTimeZones();
      try {
        final String timeZoneName = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint('Timezone initialized: $timeZoneName');
      } catch (e) {
        debugPrint('Failed to get local timezone: $e');
      }
      _initialized = true;
    }
  }

  static tz.TZDateTime nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
