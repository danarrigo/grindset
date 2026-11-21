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

  /// The site in the browser's address bar.
  String? host;
  final askedForHost = <bool>[];
  var closedTabs = 0;
  @override
  Future<WindowsActivityStatus> windowsActivity(
    int processId, {
    bool browser = false,
  }) async {
    askedForHost.add(browser);
    return WindowsActivityStatus(
      current: true,
      idle: Duration.zero,
      idleKnown: true,
      mediaAvailable: true,
      mediaPlaying: false,
      host: browser ? host : null,
    );
  }

  @override
  Future<bool> closeBrowserTab(int processId) async {
    closedTabs++;
    return true;
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('a blocked app stays blocked for the whole session, and tracking keeps running', () async {
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
    controller.dismissBlock();
    await controller.refresh();
    expect(controller.blockedSource, 'windows:game.exe');
    expect(controller.trackingEnabled, isTrue);
    tracker.source = 'windows:other-game.exe';
    await controller.refresh();
    expect(controller.blockedSource, 'windows:other-game.exe');
    now = now.add(const Duration(minutes: 5));
    tracker.source = 'windows:game.exe';
    await controller.refresh();
    expect(controller.blockedSource, 'windows:game.exe');
    expect(controller.websiteRestrictions().containsKey('allowed'), isFalse);
  });

  group('without the browser extension, the address bar is used', () {
    late DateTime now;
    late LocalStore store;
    late _ForegroundFixture tracker;
    late AppController controller;
    setUp(() async {
      now = DateTime.utc(2026, 11, 10, 10);
      store = LocalStore.memory();
      await store.saveSetting('tracking_enabled', 'true');
      tracker = _ForegroundFixture()
        ..source = 'windows:chrome.exe'
        ..host = 'youtube.com';
      controller = AppController(
        store: store,
        tracker: tracker,
        clock: () => now,
      );
      await controller.initialize(poll: false);
      controller.restrictWindowsApp = (_) async => true;
      await controller.saveRule(
        ActivityRule(id: 'video', name: 'Video', sources: ['web:youtube.com']),
      );
    });
    tearDown(() async {
      controller.dispose();
      await store.close();
    });

    test(
      'a blocked site\'s tab is closed once, and the browser stays usable',
      () async {
        await controller.refresh();
        expect(tracker.askedForHost.last, isTrue);
        expect(tracker.closedTabs, 0);
        await controller.startSession(
          const Duration(minutes: 25),
          SessionPhase.focus,
        );
        now = now.add(const Duration(seconds: 1));
        await controller.refresh();
        expect(tracker.closedTabs, 1);
        expect(controller.blockedSource, isNull);
        // The tab is still closing: no second tab is closed.
        now = now.add(const Duration(seconds: 1));
        await controller.refresh();
        expect(tracker.closedTabs, 1);
        // Another site is fine.
        tracker.host = 'example.com';
        now = now.add(const Duration(seconds: 1));
        await controller.refresh();
        expect(tracker.closedTabs, 1);
        expect(controller.blockedSource, isNull);
      },
    );

    test('time on a site counts toward its daily limit', () async {
      await controller.saveRule(
        ActivityRule(
          id: 'video',
          name: 'Video',
          sources: ['web:youtube.com'],
          focusBlock: false,
          dailyMinutes: 1,
        ),
      );
      for (var i = 0; i < 55; i++) {
        await controller.refresh();
        now = now.add(const Duration(seconds: 1));
      }
      expect(tracker.closedTabs, 0);
      for (var i = 0; i < 15; i++) {
        await controller.refresh();
        now = now.add(const Duration(seconds: 1));
      }
      await controller.reloadUsage();
      expect(
        controller.usage
            .where((u) => u.source == 'web:youtube.com')
            .fold(Duration.zero, (sum, u) => sum + u.end.difference(u.start)),
        greaterThanOrEqualTo(const Duration(minutes: 1)),
      );
      expect(tracker.closedTabs, greaterThan(0));
    });

    test(
      'strict mode does not block a browser whose sites it can read',
      () async {
        await controller.setStrictMode(true);
        await controller.startSession(
          const Duration(minutes: 25),
          SessionPhase.focus,
        );
        tracker.host = 'example.com';
        for (var i = 0; i < 12; i++) {
          now = now.add(const Duration(seconds: 1));
          await controller.refresh();
        }
        expect(controller.restrictionForSource('windows:chrome.exe'), isNull);
      },
    );
  });
}
