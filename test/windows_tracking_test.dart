import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _Windows extends NativeTracker {
  String source = 'windows:player.exe';
  @override
  bool get isWindows => true;
  @override
  bool get isAndroid => false;
  @override
  ForegroundApp foreground() =>
      ForegroundApp(source, 'Test foreground app', processId: 42);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);
  late LocalStore store;
  late AppController controller;
  late DateTime now;
  late bool current;
  late bool playing;
  late bool mediaAvailable;
  late Duration idle;
  setUp(() async {
    now = DateTime.utc(2026, 11, 10, 10);
    current = true;
    playing = false;
    mediaAvailable = true;
    idle = Duration.zero;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTracker.windowsChannel, (call) async {
          expect(call.method, 'activityState');
          expect((call.arguments as Map)['pid'], 42);
          return {
            'current': current,
            'idleMs': idle.inMilliseconds,
            'idleKnown': true,
            'mediaAvailable': mediaAvailable,
            'mediaPlaying': playing,
          };
        });
    store = LocalStore.memory();
    await store.saveSetting('tracking_enabled', 'true');
    controller = AppController(
      store: store,
      tracker: _Windows(),
      clock: () => now,
    );
    await controller.initialize(poll: false);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTracker.windowsChannel, null);
  });

  Future<void> sample() async {
    await controller.refresh();
    now = now.add(const Duration(seconds: 1));
    await controller.refresh();
    await controller.reloadUsage();
  }

  test(
    'restart records a persistent tracking gap without inventing activity',
    () async {
      await sample();
      final recorded = controller.deviceUsage(controller.deviceId);
      controller.dispose();
      now = now.add(const Duration(minutes: 2));
      controller = AppController(
        store: store,
        tracker: _Windows(),
        clock: () => now,
      );
      await controller.initialize(poll: false);
      await controller.refresh();
      expect(
        controller.trackingInterruption,
        contains('No activity was estimated'),
      );
      expect(controller.deviceUsage(controller.deviceId), recorded);
      final notice = controller.trackingInterruption;
      controller.dispose();
      controller = AppController(
        store: store,
        tracker: _Windows(),
        clock: () => now,
      );
      await controller.initialize(poll: false);
      expect(controller.trackingInterruption, notice);
      await controller.dismissTrackingInterruption();
      controller.dispose();
      controller = AppController(
        store: store,
        tracker: _Windows(),
        clock: () => now,
      );
      await controller.initialize(poll: false);
      expect(controller.trackingInterruption, isNull);
    },
  );

  test(
    'returning to a blocked desktop app shows the interruption again',
    () async {
      controller.dispose();
      final tracker = _Windows()..source = 'windows:discord.exe';
      controller = AppController(
        store: store,
        tracker: tracker,
        clock: () => now,
      );
      await controller.initialize(poll: false);
      await controller.saveRule(
        ActivityRule(
          id: 'discord',
          name: 'Discord',
          sources: ['windows:discord.exe'],
        ),
      );
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      var interruptions = 0;
      controller.showBlock = () async {
        interruptions++;
      };
      await sample();
      expect(interruptions, 1);
      tracker.source = 'windows:lockin.exe';
      await sample();
      tracker.source = 'windows:discord.exe';
      await sample();
      expect(interruptions, 2);
      await controller.overrideBlock();
      await sample();
      expect(controller.blockedSource, isNull);
      expect(interruptions, 2);
    },
  );

  test(
    'inactive foreground applications are not counted after the idle threshold',
    () async {
      idle = const Duration(minutes: 4);
      await sample();
      expect(controller.deviceUsage(controller.deviceId), Duration.zero);
    },
  );

  test(
    'foreground playback still counts when there has been no recent input',
    () async {
      idle = const Duration(minutes: 4);
      playing = true;
      await sample();
      expect(
        controller.deviceUsage(controller.deviceId),
        const Duration(seconds: 1),
      );
    },
  );

  test(
    'unavailable media detection does not silently discard a playing video',
    () async {
      idle = const Duration(minutes: 4);
      mediaAvailable = false;
      await sample();
      expect(
        controller.deviceUsage(controller.deviceId),
        const Duration(seconds: 1),
      );
    },
  );

  test(
    'a foreground race cannot attribute another application to the old process',
    () async {
      current = false;
      await sample();
      expect(controller.deviceUsage(controller.deviceId), Duration.zero);
    },
  );
}
