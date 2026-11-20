import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _Android extends NativeTracker {
  @override
  bool get isAndroid => true;
  @override
  bool get isWindows => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);
  late LocalStore store;
  late AppController controller;
  late DateTime now;
  late bool enabled;
  late bool running;
  late bool failRead;
  late bool usageAccess;
  late String? nativeError;
  late String? foreground;
  late List<Map<String, Object>> records;
  late List<MethodCall> calls;

  setUp(() async {
    now = DateTime.utc(2026, 11, 10, 10);
    enabled = true;
    running = true;
    failRead = false;
    usageAccess = true;
    nativeError = null;
    foreground = null;
    records = [];
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTracker.channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initializeTracking':
            case 'trackingStatus':
              return {
                'enabled': enabled,
                'running': running,
                'blockingEnabled': true,
                'error': nativeError,
              };
            case 'setTrackingEnabled':
              enabled = (call.arguments as Map)['enabled'] == true;
              return {
                'enabled': enabled,
                'running': enabled && running,
                'blockingEnabled': true,
                'error': nativeError,
              };
            case 'hasUsageAccess':
              return usageAccess;
            case 'foregroundSource':
              return foreground;
            case 'readUsage':
              if (failRead) {
                throw PlatformException(
                  code: 'USER_LOCKED',
                  message: 'Unlock the device.',
                );
              }
              return records;
            case 'showBlock':
            case 'hideBlock':
            case 'setStrictLock':
            case 'requestUsageAccess':
              return null;
            default:
              throw StateError('Unexpected Android request: ${call.method}');
          }
        });
    store = LocalStore.memory();
    controller = AppController(
      store: store,
      tracker: _Android(),
      clock: () => now,
    );
    await controller.initialize(poll: false);
  });

  tearDown(() async {
    controller.dispose();
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTracker.channel, null);
  });

  test(
    'permission interruption remains visible after refresh and reopen',
    () async {
      nativeError = 'Usage Access is required for background tracking.';
      usageAccess = false;
      running = false;
      calls.clear();
      await controller.refresh();
      expect(controller.trackingError, nativeError);
      expect(calls.where((call) => call.method == 'readUsage'), isEmpty);
      controller.dispose();
      controller = AppController(
        store: store,
        tracker: _Android(),
        clock: () => now,
      );
      await controller.initialize(poll: false);
      expect(controller.trackingError, nativeError);
      await controller.refresh();
      expect(controller.trackingError, nativeError);
      nativeError = null;
      usageAccess = true;
      running = true;
      await controller.refresh();
      expect(controller.trackingError, isNull);
    },
  );

  test(
    'tracking review does not reopen already granted Usage Access',
    () async {
      calls.clear();
      await controller.enableTracking();
      expect(
        calls.where((call) => call.method == 'requestUsageAccess'),
        isEmpty,
      );
    },
  );

  test('tracking review requests missing Usage Access', () async {
    usageAccess = false;
    running = false;
    calls.clear();
    await controller.enableTracking();
    expect(
      calls.where((call) => call.method == 'requestUsageAccess'),
      hasLength(1),
    );
  });

  test(
    'native background intervals retain identity across overlapping imports',
    () async {
      final start = now.subtract(const Duration(minutes: 2));
      records = [
        {
          'source': 'android:example.app',
          'start': start.millisecondsSinceEpoch,
          'end': now.millisecondsSinceEpoch,
        },
      ];
      await controller.refresh();
      expect(
        controller.deviceUsage(controller.deviceId),
        const Duration(minutes: 2),
      );
      final originalId = controller.usage.single.id;
      now = now.add(const Duration(minutes: 1));
      records.single['end'] = now.millisecondsSinceEpoch;
      for (var tick = 0; tick < 15; tick++) {
        await controller.refresh();
      }
      expect(controller.usage.single.id, originalId);
      expect(
        controller.deviceUsage(controller.deviceId),
        const Duration(minutes: 3),
      );
      expect(
        await store.setting('android_imported_until'),
        now.toIso8601String(),
      );
    },
  );

  test(
    'failed native reads do not advance the durable import checkpoint',
    () async {
      failRead = true;
      await controller.refresh();
      expect(controller.trackingError, contains('Unlock the device'));
      expect(await store.setting('android_imported_until'), isNull);
      expect(controller.usage, isEmpty);
    },
  );

  test('Android daily rules use the shared accounting policy and cannot be waved away', () async {
    records = [
      {
        'source': 'android:example.app',
        'start': now
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
      },
    ];
    foreground = 'android:example.app';
    await controller.saveRule(
      ActivityRule(
        id: 'activity',
        name: 'Distractions',
        dailyMinutes: 1,
        sources: ['android:example.app', 'android:another.app'],
      ),
    );
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.blockedSource, 'android:example.app');
    expect(calls.where((c) => c.method == 'showBlock'), hasLength(1));
    // Leaving the block screen does not lift it: the app is blocked again.
    controller.dismissBlock();
    now = now.add(const Duration(seconds: 1));
    await controller.refresh();
    expect(controller.blockedSource, 'android:example.app');
    foreground = 'android:another.app';
    await controller.refresh();
    expect(controller.blockedSource, 'android:another.app');
  });

  test(
    'strict mode tells Android when it locks, so uninstalling is blocked',
    () async {
      records = [
        {
          'source': 'android:example.app',
          'start': now
              .subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
          'end': now.millisecondsSinceEpoch,
        },
      ];
      await controller.saveRule(
        ActivityRule(
          id: 'activity',
          name: 'Distractions',
          dailyMinutes: 1,
          sources: ['android:example.app'],
        ),
      );
      List<Object?> locks() => [
        for (final c in calls)
          if (c.method == 'setStrictLock') (c.arguments as Map)['locked'],
      ];
      await controller.refresh();
      expect(locks(), [false]);
      await controller.setStrictMode(true);
      expect(controller.strictLock, 'while a daily limit is reached');
      foreground = 'android:com.google.android.packageinstaller';
      await controller.refresh();
      expect(locks(), [false, true]);
      expect(controller.blockedSource, foreground);
      expect(controller.blockMessage, contains('uninstalling apps is paused'));
    },
  );

  test(
    'a notification stop remains authoritative if its Dart callback was lost',
    () async {
      foreground = 'android:example.app';
      await controller.saveRule(
        ActivityRule(
          id: 'activity',
          name: 'Distractions',
          dailyMinutes: 1,
          sources: [foreground!],
        ),
      );
      records = [
        {
          'source': foreground!,
          'start': now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          'end': now.millisecondsSinceEpoch,
        },
      ];
      await controller.refresh();
      expect(controller.blockedSource, isNotNull);
      calls.clear();
      enabled = false;
      await controller.refresh();
      expect(controller.trackingEnabled, isFalse);
      expect(controller.blockedSource, isNull);
      expect(await store.setting('tracking_enabled'), 'false');
      expect(calls.where((c) => c.method == 'readUsage'), isEmpty);
      expect(calls.where((c) => c.method == 'setTrackingEnabled'), isEmpty);
    },
  );
}
