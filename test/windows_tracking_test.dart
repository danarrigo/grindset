import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _Windows extends NativeTracker {
  @override
  bool get isWindows => true;
  @override
  bool get isAndroid => false;
  @override
  ForegroundApp foreground() =>
      const ForegroundApp('windows:player.exe', 'Player', processId: 42);
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
