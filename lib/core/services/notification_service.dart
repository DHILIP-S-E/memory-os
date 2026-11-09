import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:personal_memory_os/core/models/reminder.dart';

/// Two-layer alarm strategy:
///   Cloud layer  → EventBridge Scheduler → SNS → APNs/FCM (via FastAPI backend)
///   Device layer → flutter_local_notifications (this service — works offline)
///
/// Both layers are scheduled on every critical reminder.
/// The LLM never triggers alarms — only this service and the backend scheduler do.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Notification channel IDs
  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Personal Memory OS reminder alarms';

  static const _scrollChannelId = 'scroll_guard';

  /// Payload of the notification that launched the app from a killed state, if any.
  static String? launchPayload;

  /// Payload of the Scroll Guard notification; tapping it should open capture.
  static const scrollGuardPayload = 'scroll_guard';

  // Notification action IDs
  static const _actionDone = 'action_done';
  static const _actionSnooze = 'action_snooze';

  /// Must be called in main() before runApp().
  static Future<void> initialize({
    void Function(String? payload)? onNotificationTap,
    void Function(String actionId, String? payload)? onActionTap,
  }) async {
    if (_initialized) return;

    tzData.initializeTimeZones();

    // Android initialisation
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialisation
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.actionId == _actionDone ||
            response.actionId == _actionSnooze) {
          onActionTap?.call(response.actionId!, response.payload);
        } else {
          onNotificationTap?.call(response.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: _backgroundHandler,
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _scrollChannelId,
          'Scroll Guard',
          description: 'Nudges to capture a memory after long scrolling',
          importance: Importance.defaultImportance,
        ));

    // Request permissions on iOS/Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      launchPayload = launch!.notificationResponse?.payload;
    }

    _initialized = true;
  }

  /// Schedule a local notification for [reminder] at its [scheduledAt] time.
  /// Does nothing if [scheduledAt] is null or already passed.
  static Future<void> scheduleReminder(Reminder reminder) async {
    if (reminder.scheduledAt == null) return;

    final scheduledTz = tz.TZDateTime.from(reminder.scheduledAt!, tz.local);
    if (scheduledTz.isBefore(tz.TZDateTime.now(tz.local))) return;

    final isHighPriority = reminder.priority == ReminderPriority.high ||
        reminder.reminderType == ReminderType.deadline;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: isHighPriority, // alarm-style for high priority
      ticker: reminder.title,
      actions: const [
        AndroidNotificationAction(
          _actionDone,
          'Done',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _actionSnooze,
          'Snooze 15m',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'reminder',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      _notificationId(reminder.id),
      reminder.title,
      reminder.description ?? 'Tap to open',
      scheduledTz,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminder.id,
    );
  }

  /// Cancel the local notification for [reminderId].
  static Future<void> cancelReminder(String reminderId) async {
    await _plugin.cancel(_notificationId(reminderId));
  }

  /// Cancel all scheduled local notifications.
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Show an immediate notification (e.g. for snooze confirmation).
  static Future<void> showImmediate({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details =
        NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// The Scroll Guard nudge for time spent in other apps. One slot, so a new one replaces the old.
  static Future<void> showScrollGuard({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _scrollChannelId,
        'Scroll Guard',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(918273, title, body, details, payload: scrollGuardPayload);
  }

  /// Derive a stable int ID from a reminder UUID string.
  static int _notificationId(String reminderId) =>
      reminderId.hashCode.abs() % 2147483647;
}

/// Background notification response handler (top-level function required).
@pragma('vm:entry-point')
void _backgroundHandler(NotificationResponse response) {
  // Handle background action taps — update reminder status via isolate-safe logic
}
