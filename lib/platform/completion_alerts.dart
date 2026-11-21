import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/focus_session.dart';
import '../core/budget_warning.dart';

/// Shared notification identity for the replaceable timer alarm and optional
/// immediate budget warnings. Budget warnings never modify the timer alarm.
class CompletionAlerts {
  CompletionAlerts({required this.android, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final bool android;
  final DateTime Function() _clock;
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _id = 4302;
  Future<void>? _initialization;
  Future<void> _tail = Future.value();
  int _generation = 0;

  Future<void> _initialize() => _initialization ??=
      () async {
        final ready = await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
            windows: WindowsInitializationSettings(
              appName: 'Grindset',
              appUserModelId: 'app.lockin.lockin',
              guid: 'e92ecb75-223b-4d5b-9f98-75b0f301c656',
            ),
          ),
        );
        if (ready != true) {
          throw StateError('The OS notification service is unavailable.');
        }
      }().catchError((Object error, StackTrace trace) {
        _initialization = null;
        Error.throwWithStackTrace(error, trace);
      });

  Future<void> requestPermission({bool exactAlarm = true}) async {
    await _initialize();
    if (!android) return;
    final implementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    if (await implementation.requestNotificationsPermission() != true) return;
    if (exactAlarm &&
        await implementation.canScheduleExactNotifications() != true) {
      await implementation.requestExactAlarmsPermission();
    }
  }

  Future<String?> showBudgetWarnings(
    List<BudgetWarning> warnings, {
    bool Function()? enabled,
  }) async {
    if (warnings.isEmpty) return null;
    await _initialize();
    if (enabled?.call() == false) return null;
    if (android &&
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()!
                .areNotificationsEnabled() !=
            true) {
      return 'System notifications are blocked. Budget warnings remain visible in Grindset.';
    }
    if (enabled?.call() == false) return null;
    await _plugin.show(
      id: 4303,
      title: 'Daily budget running low',
      body: warnings.length == 1
          ? warnings.single.message
          : '${warnings.length} activities have used at least 80% of their daily budgets. Open Grindset Rules for remaining time.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lockin_budget',
          'Budget warnings',
          channelDescription:
              'Optional warnings before a daily activity limit.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
    return null;
  }

  /// Windows, without the browser extension: a blocked site's tab was closed.
  Future<void> showSiteClosed(String host, String reason) async {
    await _initialize();
    await _plugin.show(
      id: 4304,
      title: '$host is blocked',
      body: '$reason. Grindset closed the tab.',
      notificationDetails: const NotificationDetails(
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  Future<String?> synchronize({required bool enabled, FocusSession? session}) {
    final generation = ++_generation;
    final operation = _tail.then((_) async {
      if (generation != _generation) return null;
      await _initialize();
      // Both platforms cancel pending schedules, including unpackaged Windows.
      // Windows requires MSIX identity only for removing already-delivered toasts.
      await _plugin.cancel(id: _id);
      if (!enabled ||
          session == null ||
          !session.end.isAfter(_clock().toUtc())) {
        return null;
      }
      var exact = true;
      if (android) {
        final implementation = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!;
        if (await implementation.areNotificationsEnabled() != true) {
          return 'Completion notifications are blocked in Android Settings.';
        }
        exact = await implementation.canScheduleExactNotifications() == true;
      }
      // A permission dialog or OS call may have outlived the requested deadline.
      // A shared session's start can be slightly ahead of this device's clock.
      // Its confirmed end still needs an alarm; only expired ends are skipped.
      if (generation != _generation || !session.end.isAfter(_clock().toUtc())) {
        return null;
      }
      // The SDK serializes whole seconds. Round up so an alarm cannot claim
      // completion before the timer's real, sub-second deadline.
      final alarmEnd = DateTime.fromMillisecondsSinceEpoch(
        ((session.end.microsecondsSinceEpoch + 999999) ~/ 1000000) * 1000,
        isUtc: true,
      );
      await _plugin.zonedSchedule(
        id: _id,
        title: session.phase == SessionPhase.focus
            ? 'Focus complete'
            : 'Break complete',
        body: 'Open Grindset when you are ready to start the next phase.',
        scheduledDate: tz.TZDateTime.from(alarmEnd, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'lockin_completion',
            'Session completion',
            channelDescription: 'An alert when your manually started focus or break timer finishes.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return exact
          ? null
          : 'Exact alarm permission is off. Completion alerts may be delayed by Android.';
    });
    // Keep subsequent cancellation usable after a platform error. Callers still
    // receive that error on their own operation and can show it truthfully.
    _tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }
}
