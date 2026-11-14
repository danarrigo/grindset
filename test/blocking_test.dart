import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

// Exercises the public tracker seam, not Windows APIs on a Linux test host.
class _ForegroundFixture extends NativeTracker {
  String source = 'windows:game.exe';
  @override
  bool get isWindows => true;
  @override
  Future<bool> setWindowsForegroundWatch(bool enabled) async => true;
  @override
  void bindWindowsForeground(void Function()? onChanged) {}
  @override
  bool get isAndroid => false;
  @override
  Future<bool> hasAccess() async => true;
  @override
  ForegroundApp? foreground() => ForegroundApp(source, source);
  @override
  Future<WindowsActivityStatus> windowsActivity(int processId) async =>
      const WindowsActivityStatus(
        current: true,
        idle: Duration.zero,
        idleKnown: true,
        mediaAvailable: true,
        mediaPlaying: false,
      );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test(
    'a five-minute override is source-specific and does not stop tracking',
    () async {
      var now = DateTime.utc(2026, 11, 10, 10);
      final store = LocalStore.memory();
      final tracker = _ForegroundFixture();
      final controller = AppController(
        store: store,
        tracker: tracker,
        clock: () => now,
      );
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize(poll: false);
      await controller.saveRule(
        ActivityRule(
          id: 'games',
          name: 'Games',
          sources: ['windows:game.exe', 'windows:other-game.exe'],
        ),
      );
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      await controller.enableTracking();
      expect(controller.blockedSource, 'windows:game.exe');
      await controller.overrideBlock();
      await controller.refresh();
      expect(controller.blockedSource, isNull);
      expect(controller.trackingEnabled, isTrue);
      tracker.source = 'windows:other-game.exe';
      await controller.refresh();
      expect(controller.blockedSource, 'windows:other-game.exe');
      now = now.add(const Duration(minutes: 5));
      tracker.source = 'windows:game.exe';
      await controller.refresh();
      expect(controller.blockedSource, 'windows:game.exe');
    },
  );
}
