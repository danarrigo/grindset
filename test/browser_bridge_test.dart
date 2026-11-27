import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/browser_bridge.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

const _origin = 'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Windows extends NativeTracker {
  _Windows(this.source);
  final String Function() source;
  @override
  bool get isWindows => true;
  @override
  Future<bool> setWindowsForegroundWatch(bool enabled) async => true;
  @override
  bool get isAndroid => false;
  @override
  ForegroundApp foreground() =>
      ForegroundApp(source(), 'Browser', processId: 42);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These controller tests exercise real loopback HTTP, not a widget fake network.
  HttpOverrides.global = null;
  setUpAll(tzdata.initializeTimeZones);
  late LocalStore store;
  late AppController controller;
  late BrowserBridge bridge;
  late HttpClient client;
  late DateTime now;
  late String source;
  String? token;

  Future<(int, Map<String, dynamic>)> request(
    String path, {
    Object? body,
    String? origin = _origin,
    bool authorized = true,
  }) async {
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:${bridge.port}$path'),
    );
    if (origin != null) req.headers.set('Origin', origin);
    if (authorized && token != null) {
      req.headers.set('Authorization', 'Bearer $token');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 5));
    return (
      res.statusCode,
      jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>,
    );
  }

  Future<void> pair() async {
    final response = await request(
      '/v1/pair',
      body: {'code': bridge.beginPairing()},
      authorized: false,
    );
    expect(response.$1, 200);
    token = response.$2['token'] as String;
  }

  Future<void> heartbeat({String domain = 'example.com'}) async {
    final response = await request(
      '/v1/heartbeat',
      body: {
        'browser': 'chrome',
        'domain': domain,
        'focused': true,
        'mediaPlaying': false,
      },
    );
    expect(response.$1, 200);
  }

  setUp(() async {
    now = DateTime.utc(2026, 11, 10, 10);
    source = 'windows:chrome.exe';
    token = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeTracker.windowsChannel,
          (_) async => {
            'current': true,
            'idleMs': 0,
            'idleKnown': true,
            'mediaAvailable': true,
            'mediaPlaying': false,
          },
        );
    store = LocalStore.memory();
    await store.saveSetting('tracking_enabled', 'true');
    controller = AppController(
      store: store,
      tracker: _Windows(() => source),
      clock: () => now,
    );
    await controller.initialize(poll: false);
    bridge = BrowserBridge(
      store: store,
      now: () => now,
      trackingEnabled: () => controller.trackingEnabled,
      restrictions: controller.websiteRestrictions,
      askForPass: (host, reason) =>
          controller.requestPass('web:$host', name: host, reason: reason),
    );
    await bridge.start(port: 0);
    controller.browserBridge = bridge;
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await bridge.close();
    controller.dispose();
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTracker.windowsChannel, null);
  });

  test('the blocked page asks an AI for a few minutes on that site', () async {
    await pair();
    await controller.saveRule(
      ActivityRule(
        id: 'video',
        name: 'Video',
        sources: ['web:youtube.com'],
        schedules: [
          ScheduleWindow(
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            startMinute: 0,
            endMinute: 23 * 60 + 59,
          ),
        ],
      ),
    );
    var rules = (await request('/v1/rules')).$2;
    expect(rules['askAi'], isFalse);
    expect(rules['blocked'], hasLength(1));

    final reasons = <String>[];
    controller.askAi =
        ({
          required what,
          required because,
          required reason,
          required localTime,
          required unlocksToday,
        }) async {
          reasons.add(reason);
          if (reason == 'fail') {
            throw const _Failed('Sign in to use the AI check.');
          }
          return (allow: true, message: 'Okay.', minutes: 20);
        };
    rules = (await request('/v1/rules')).$2;
    expect(rules['askAi'], isTrue);
    expect(rules['pause'], 0);

    // Hosts and a short reason only.
    expect(
      (await request(
        '/v1/pass',
        body: {'domain': 'https://youtube.com/watch', 'reason': 'Lecture'},
      )).$1,
      400,
    );
    expect(
      (await request(
        '/v1/pass',
        body: {'domain': 'youtube.com', 'reason': 'x' * 121},
      )).$1,
      400,
    );
    expect(
      (await request(
        '/v1/pass',
        body: {'domain': 'youtube.com', 'reason': 'Lecture'},
        authorized: false,
      )).$1,
      401,
    );
    // The AI check's own errors reach the page.
    final failed = await request(
      '/v1/pass',
      body: {'domain': 'youtube.com', 'reason': 'fail'},
    );
    expect(failed.$2, {
      'allow': false,
      'message': 'Sign in to use the AI check.',
    });

    final allowed = await request(
      '/v1/pass',
      body: {'domain': 'youtube.com', 'reason': 'Lecture for class'},
    );
    expect(allowed.$2, {'allow': true, 'message': 'Okay.', 'minutes': 20});
    expect(reasons, ['fail', 'Lecture for class']);
    expect((await request('/v1/rules')).$2['blocked'], isEmpty);
    now = now.add(const Duration(minutes: 20));
    expect((await request('/v1/rules')).$2['blocked'], hasLength(1));
  });

  test('health records only authenticated successful policy requests and resets on disconnect', () async {
    expect(bridge.isListening, isTrue);
    expect(bridge.lastPolicyRequestAt, isNull);
    await request('/v1/rules', authorized: false);
    expect(bridge.lastPolicyRequestAt, isNull);
    await pair();
    await request('/v1/rules');
    expect(bridge.lastPolicyRequestAt, now);
    await bridge.disconnect();
    expect(bridge.lastPolicyRequestAt, isNull);
  });

  test('a Firefox-based browser pairs, and its heartbeat counts while Zen is in front', () async {
    const firefox = 'moz-extension://0f1e2d3c-4b5a-4697-8877-665544332211';
    final paired = await request(
      '/v1/pair',
      body: {'code': bridge.beginPairing()},
      origin: firefox,
      authorized: false,
    );
    expect(paired.$1, 200);
    token = paired.$2['token'] as String;
    expect(
      (await request(
        '/v1/heartbeat',
        origin: firefox,
        body: {
          'browser': 'firefox',
          'domain': 'example.com',
          'focused': true,
          'mediaPlaying': false,
        },
      )).$1,
      200,
    );
    expect(bridge.observationFor('windows:zen.exe')?.source, 'web:example.com');
    expect(
      bridge.observationFor('windows:firefox.exe')?.source,
      'web:example.com',
    );
    // Another browser in front does not borrow the Firefox heartbeat.
    expect(bridge.observationFor('windows:chrome.exe'), isNull);
    // A look-alike origin is still refused.
    expect(
      (await request('/v1/rules', origin: 'moz-extension://not-a-uuid')).$1,
      403,
    );
  });

  test('pairing requires an extension origin, a live code and an authenticated token', () async {
    final code = bridge.beginPairing();
    expect(
      (await request(
        '/v1/pair',
        body: {'code': code},
        origin: 'https://example.com',
      )).$1,
      403,
    );
    expect((await request('/v1/rules')).$1, 401);
    for (var i = 0; i < 5; i++) {
      expect((await request('/v1/pair', body: {'code': 'not-a-code'})).$1, 403);
    }
    expect((await request('/v1/pair', body: {'code': code})).$1, 403);
    await pair();
    expect((await request('/v1/rules')).$2['enabled'], isTrue);
    await bridge.disconnect();
    expect((await request('/v1/rules')).$1, 401);
  });

  test(
    'Chrome privileged GET can omit Origin, but still requires its token',
    () async {
      await pair();
      expect((await request('/v1/rules', origin: null)).$1, 200);
      expect(
        (await request('/v1/rules', origin: null, authorized: false)).$1,
        401,
      );
      expect(
        (await request('/v1/rules', origin: 'https://example.com')).$1,
        403,
      );
      expect(
        (await request(
          '/v1/pair',
          origin: null,
          body: {'code': bridge.beginPairing()},
        )).$1,
        403,
      );
      expect((await request('/v1/unknown', origin: null)).$1, 403);
    },
  );

  test(
    'the wire format rejects complete URLs and extra page metadata',
    () async {
      await pair();
      expect(
        (await request(
          '/v1/heartbeat',
          body: {
            'browser': 'chrome',
            'domain': 'https://example.com/private?q=secret',
            'focused': true,
            'mediaPlaying': false,
          },
        )).$1,
        400,
      );
      expect(
        (await request(
          '/v1/heartbeat',
          body: {
            'browser': 'chrome',
            'domain': 'example.com',
            'focused': true,
            'mediaPlaying': false,
            'title': 'Never collect',
          },
        )).$1,
        400,
      );
      expect(bridge.observationFor(source), isNull);
      await heartbeat(domain: 'www.EXAMPLE.com');
      expect(bridge.observationFor(source)?.source, 'web:example.com');
      now = now.add(const Duration(seconds: 13));
      expect(bridge.observationFor(source), isNull);
    },
  );

  test('website intervals stop at confirmed browser heartbeats, never a disconnected estimate', () async {
    await pair();
    await heartbeat();
    await controller.refresh();
    now = now.add(const Duration(seconds: 5));
    await heartbeat();
    await controller.refresh();
    await controller.reloadUsage();
    expect(
      combinedUsage(
        controller.usage.where((i) => i.source == 'web:example.com'),
      ),
      const Duration(seconds: 5),
    );
    expect(
      controller.deviceUsage(controller.deviceId),
      const Duration(seconds: 5),
      reason: 'Browser app and domain intervals must not double count.',
    );
    now = now.add(const Duration(seconds: 13));
    await controller.refresh();
    await controller.reloadUsage();
    expect(
      combinedUsage(
        controller.usage.where((i) => i.source == 'web:example.com'),
      ),
      const Duration(seconds: 5),
    );
  });

  test('a browser heartbeat cannot attribute website use while another app is foreground', () async {
    await pair();
    source = 'windows:notepad.exe';
    await heartbeat();
    await controller.refresh();
    now = now.add(const Duration(seconds: 5));
    await heartbeat();
    await controller.refresh();
    await controller.reloadUsage();
    expect(controller.usage.where((i) => i.source.startsWith('web:')), isEmpty);
  });

  test(
    'resuming tracking cannot backdate website usage into the disabled gap',
    () async {
      await pair();
      await heartbeat();
      await controller.refresh();
      now = now.add(const Duration(seconds: 5));
      await heartbeat();
      await controller.refresh();
      await controller.disableTracking();
      now = now.add(const Duration(seconds: 3));
      await controller.enableTracking();
      now = now.add(const Duration(seconds: 2));
      await heartbeat();
      await controller.refresh();
      await controller.reloadUsage();
      expect(
        combinedUsage(
          controller.usage.where((i) => i.source.startsWith('web:')),
        ),
        const Duration(seconds: 7),
      );
    },
  );

  test(
    'subdomain budgets share the policy, and there is no way to lift a block',
    () async {
      await pair();
      await controller.saveRule(
        ActivityRule(
          id: 'site',
          name: 'Site',
          dailyMinutes: 1,
          sources: ['web:example.com'],
        ),
      );
      await controller.saveRule(
        ActivityRule(
          id: 'other',
          name: 'Other',
          dailyMinutes: 1,
          sources: ['web:another.com'],
        ),
      );
      for (final (id, host) in [
        ('first', 'm.example.com'),
        ('second', 'another.com'),
      ]) {
        await store.putUsage(
          UsageInterval(
            id: id,
            deviceId: controller.deviceId,
            source: 'web:$host',
            start: now.subtract(const Duration(minutes: 1)),
            end: now,
          ),
        );
      }
      await controller.reloadUsage();
      expect(
        controller.restrictionForSource('web:sub.example.com'),
        'Daily budget reached',
      );
      // The old temporary-override route is gone.
      expect(
        (await request('/v1/override', body: {'domain': 'example.com'})).$1,
        404,
      );
      expect(
        controller.restrictionForSource('web:sub.example.com'),
        'Daily budget reached',
      );
      expect(
        controller.restrictionForSource('web:another.com'),
        'Daily budget reached',
      );
      expect(
        matchesSource('web:example.com', 'web:example.com.evil.test'),
        isFalse,
      );
    },
  );

  test(
    'in strict mode, a browser in front without the extension is blocked',
    () async {
      await controller.saveRule(
        ActivityRule(id: 'video', name: 'Video', sources: ['web:video.test']),
      );
      await controller.setStrictMode(true);
      await controller.startSession(
        const Duration(minutes: 25),
        SessionPhase.focus,
      );
      await controller.refresh();
      // A moment's grace while the extension wakes up.
      expect(controller.restrictionForSource(source), isNull);
      now = now.add(const Duration(seconds: 11));
      await controller.refresh();
      expect(
        controller.restrictionForSource(source),
        contains('turn on the Grindset extension'),
      );
      await pair();
      await heartbeat();
      expect(controller.restrictionForSource(source), isNull);
      // A browser the extension cannot report from is never verified.
      source = 'windows:brave.exe';
      await controller.refresh();
      now = now.add(const Duration(seconds: 11));
      expect(
        controller.restrictionForSource(source),
        contains('Use Chrome, Edge, Firefox or Zen'),
      );
      // Once the session is over, browsers are left alone again.
      now = now.add(const Duration(minutes: 30));
      expect(controller.restrictionForSource(source), isNull);
    },
  );
}

class _Failed implements Exception {
  const _Failed(this.message);
  final String message;
  @override
  String toString() => message;
}
