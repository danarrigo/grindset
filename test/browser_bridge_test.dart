import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
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
    String origin = _origin,
    bool authorized = true,
  }) async {
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:${bridge.port}$path'),
    );
    req.headers.set('Origin', origin);
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
      onOverride: controller.overrideSource,
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
    'subdomain budgets share the policy and overrides do not lift another site',
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
      final result = await request(
        '/v1/override',
        body: {'domain': 'example.com'},
      );
      expect(result.$1, 200);
      expect(result.$2['allowed'], ['example.com']);
      expect(controller.restrictionForSource('web:sub.example.com'), isNull);
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
}
