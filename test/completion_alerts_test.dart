import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/completion_alerts.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late LocalStore store;
  late AppController controller;
  late DateTime now;
  late bool permission;
  late bool exact;
  late bool failInitialize;
  late List<MethodCall> calls;
  Map<dynamic, dynamic>? scheduled;
  Completer<void>? scheduleGate;
  Completer<void>? scheduleArrived;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    // The SDK also checks the real clock. Keep our controllable clock safely
    // ahead of it, and assert against exact relative deadlines, not wall dates.
    final wall = DateTime.now().toUtc();
    now = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour + 1,
      wall.minute,
      wall.second,
      123,
      456,
    );
    permission = true;
    exact = true;
    failInitialize = false;
    calls = [];
    scheduled = null;
    scheduleGate = null;
    scheduleArrived = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              if (failInitialize) throw PlatformException(code: 'UNAVAILABLE');
              return true;
            case 'requestNotificationsPermission':
            case 'areNotificationsEnabled':
              return permission;
            case 'requestExactAlarmsPermission':
            case 'canScheduleExactNotifications':
              return exact;
            case 'cancel':
              scheduled = null;
              return null;
            case 'zonedSchedule':
              if (!(scheduleArrived?.isCompleted ?? true)) {
                scheduleArrived!.complete();
              }
              await scheduleGate?.future;
              scheduled = Map<dynamic, dynamic>.from(call.arguments as Map);
              return null;
            default:
              throw StateError(
                'Unexpected notification method: ${call.method}',
              );
          }
        });
    store = LocalStore.memory();
    controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
      completionAlerts: CompletionAlerts(android: true, clock: () => now),
    );
    await controller.initialize(poll: false);
    calls.clear();
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'completion alerts require opt-in and schedule the actual UTC deadline',
    () async {
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      expect(scheduled, isNull);
      await controller.setCompletionAlertsEnabled(true);
      expect(controller.completionAlertsNotice, isNull);
      final alarm = DateTime.parse('${scheduled!['scheduledDateTime']}Z');
      expect(alarm.isBefore(controller.session!.end), isFalse);
      expect(
        alarm.difference(controller.session!.end),
        lessThan(const Duration(seconds: 1)),
      );
      expect(scheduled!['timeZoneName'], anyOf('UTC', 'Etc/UTC'));
      expect(scheduled!['title'], 'Focus complete');
      expect(await store.setting('completion_alerts_enabled'), 'true');
      expect(controller.completionAlertsNotice, isNull);
    },
  );

  test(
    'ending early cancels the pending deadline without a false completion',
    () async {
      await controller.setCompletionAlertsEnabled(true);
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      calls.clear();
      now = now.add(const Duration(seconds: 1));
      await controller.endSession();
      expect(scheduled, isNull);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
    },
  );

  test(
    'disabling completion alerts cancels the alarm but does not stop the timer',
    () async {
      await controller.setCompletionAlertsEnabled(true);
      await controller.startSession(
        const Duration(minutes: 5),
        SessionPhase.rest,
      );
      expect(scheduled!['title'], 'Break complete');
      await controller.setCompletionAlertsEnabled(false);
      expect(scheduled, isNull);
      expect(controller.session!.running(now), isTrue);
      expect(await store.setting('completion_alerts_enabled'), 'false');
    },
  );

  test('denied exact alarms use an explicitly delayed fallback', () async {
    exact = false;
    await controller.setCompletionAlertsEnabled(true);
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    expect(scheduled, isNotNull);
    expect(
      (scheduled!['platformSpecifics'] as Map)['scheduleMode'],
      'inexactAllowWhileIdle',
    );
    expect(controller.completionAlertsNotice, contains('delayed'));
  });

  test(
    'notification denial is visible and never prevents starting a timer',
    () async {
      permission = false;
      await controller.setCompletionAlertsEnabled(true);
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      expect(scheduled, isNull);
      expect(controller.session!.running(now), isTrue);
      expect(controller.completionAlertsNotice, contains('blocked'));
    },
  );

  test(
    'a downloaded shared session replaces the local scheduled deadline',
    () async {
      await controller.setCompletionAlertsEnabled(true);
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      final local = (await controller.sharedState.pending(focusOnly: true))
          .single;
      await controller.sharedState.accept(
        local,
        applied: true,
        record: {
          'kind': 'focus',
          'id': 'active',
          'revision': 1,
          'value': local.value,
        },
      );
      now = now.add(const Duration(seconds: 5));
      final other = FocusSession(
        id: 'other',
        phase: SessionPhase.rest,
        start: now,
        end: now.add(const Duration(minutes: 5)),
      );
      await controller.sharedState.receive({
        'kind': 'focus',
        'id': 'active',
        'revision': 2,
        'value': other.toJson(),
      });
      await controller.reloadSharedState();
      expect(scheduled!['title'], 'Break complete');
      final alarm = DateTime.parse('${scheduled!['scheduledDateTime']}Z');
      expect(alarm.isBefore(other.end), isFalse);
      expect(alarm.difference(other.end), lessThan(const Duration(seconds: 1)));
    },
  );

  test(
    'a restored enabled timer recreates its alarm without enabling tracking',
    () async {
      await controller.setCompletionAlertsEnabled(true);
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      final deadline = controller.session!.end;
      controller.dispose();
      controller = AppController(
        store: store,
        tracker: NativeTracker(),
        clock: () => now,
        completionAlerts: CompletionAlerts(android: true, clock: () => now),
      );
      scheduled = null;
      await controller.initialize(poll: false);
      expect(controller.completionAlertsEnabled, isTrue);
      expect(controller.session!.end, deadline);
      expect(scheduled, isNotNull);
      expect(controller.trackingEnabled, isFalse);
    },
  );

  test('a temporary OS initialization failure remains retryable', () async {
    controller.dispose();
    failInitialize = true;
    controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
      completionAlerts: CompletionAlerts(android: true, clock: () => now),
    );
    await controller.initialize(poll: false);
    expect(controller.completionAlertsNotice, contains('unavailable'));
    failInitialize = false;
    await controller.setCompletionAlertsEnabled(true);
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    expect(scheduled, isNotNull);
    expect(controller.completionAlertsNotice, isNull);
  });

  test('a shared session with a slightly ahead device clock still schedules its end', () async {
    await controller.setCompletionAlertsEnabled(true);
    final future = FocusSession(
      id: 'ahead-device',
      phase: SessionPhase.focus,
      start: now.add(const Duration(seconds: 2)),
      end: now.add(const Duration(minutes: 25)),
    );
    await controller.sharedState.receive({
      'kind': 'focus',
      'id': 'active',
      'revision': 1,
      'value': future.toJson(),
    });
    await controller.reloadSharedState();
    expect(scheduled, isNotNull);
  });

  test(
    'an early end during an in-flight schedule cannot resurrect an old alarm',
    () async {
      await controller.setCompletionAlertsEnabled(true);
      scheduleGate = Completer<void>();
      scheduleArrived = Completer<void>();
      final start = controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      await scheduleArrived!.future;
      now = now.add(const Duration(seconds: 1));
      final end = controller.endSession();
      scheduleGate!.complete();
      await Future.wait([start, end]);
      expect(scheduled, isNull);
      expect(calls.last.method, 'cancel');
    },
  );
}
