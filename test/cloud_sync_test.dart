import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/cloud_sync.dart';
import 'package:lockin/data/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';

class _CloudServer {
  late final HttpServer server;
  final rows = <Map<String, dynamic>>[];
  final uploaded = <Map<String, dynamic>>[];
  int uploads = 0;
  int downloads = 0;
  bool failUploads = false;
  Completer<void>? uploadGate;
  Completer<void>? uploadArrived;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      Object response = <Object>[];
      if (path == '/auth/v1/token') {
        final user = (jsonDecode(body) as Map)['email'] == 'other@example.test'
            ? _other
            : _owner;
        String part(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        final token =
            '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': user, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature';
        response = {
          'access_token': token,
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'test-refresh',
          'user': {
            'id': user,
            'aud': 'authenticated',
            'email': 'fixture@example.test',
            'app_metadata': <String, Object>{},
            'user_metadata': <String, Object>{},
            'created_at': '2026-11-10T00:00:00Z',
          },
        };
      } else if (path == '/auth/v1/logout') {
        request.response.statusCode = 204;
      } else if (path == '/rest/v1/usage_intervals' &&
          request.method == 'POST') {
        uploads++;
        if (!(uploadArrived?.isCompleted ?? true)) uploadArrived!.complete();
        await uploadGate?.future;
        if (failUploads) {
          request.response.statusCode = 503;
          response = {'code': 'OFFLINE_TEST', 'message': 'Network unavailable'};
        } else {
          uploaded.addAll(
            (jsonDecode(body) as List).map(
              (row) => Map<String, dynamic>.from(row as Map),
            ),
          );
        }
      } else if (path == '/rest/v1/usage_intervals') {
        downloads++;
        final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
        final limit = int.parse(request.uri.queryParameters['limit'] ?? '500');
        response = rows.skip(offset).take(limit).toList();
      } else if (path == '/rest/v1/devices' && request.method == 'GET') {
        response = [
          {
            'user_id': _owner,
            'id': 'phone',
            'label': 'Android device',
            'platform': 'Android',
            'last_seen_at': '2026-11-10T10:00:00Z',
          },
        ];
      } else if (path != '/rest/v1/devices') {
        request.response.statusCode = 404;
        response = {'message': 'Unexpected request: $path'};
      }
      request.response.headers.contentType = ContentType.json;
      if (request.response.statusCode != 204) {
        request.response.write(jsonEncode(response));
      }
      await request.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${server.port}';
}

void main() {
  late _CloudServer server;
  late SupabaseClient client;
  late LocalStore store;
  late CloudSync sync;
  final since = DateTime.utc(2026, 11, 10);
  UsageInterval interval(
    String id, {
    String device = 'desktop',
    int minutes = 1,
  }) => UsageInterval(
    id: id,
    deviceId: device,
    source: 'web:example.test',
    start: since.add(const Duration(hours: 9)),
    end: since.add(Duration(hours: 9, minutes: minutes)),
  );

  setUp(() async {
    server = _CloudServer();
    await server.start();
    client = SupabaseClient(
      server.url,
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    store = LocalStore.memory();
    sync = CloudSync(client: client, store: store);
    await client.auth.signInWithPassword(
      email: 'owner@example.test',
      password: 'test-password-only',
    );
  });
  tearDown(() async {
    await sync.close();
    await client.dispose();
    await server.server.close(force: true);
    await store.close();
  });

  test(
    'automatic sync uploads pending usage and downloads every confirmed page',
    () async {
      await store.putUsage(interval('local'));
      server.rows.addAll(
        List.generate(
          513,
          (i) => {
            ...interval('remote-$i', device: 'phone').toJson(),
            'user_id': _owner,
          },
        ),
      );
      final downloaded = Completer<void>();
      await sync.startAutomatic(
        deviceId: 'desktop',
        platform: 'Windows',
        since: () => since,
        onDownloaded: () async {
          if (!downloaded.isCompleted) downloaded.complete();
        },
      );
      await downloaded.future.timeout(const Duration(seconds: 5));
      expect(server.uploaded.single['id'], 'local');
      expect(server.uploaded.single['user_id'], _owner);
      expect(server.downloads, 2);
      expect(await store.usage(), hasLength(514));
      expect(await store.usage(pendingOnly: true), isEmpty);
      expect(sync.lastSync, isNotNull);
      expect(sync.lastError, isNull);
    },
  );

  test('manual sync joins an in-flight upload and does not acknowledge newer usage', () async {
    final original = interval('growing');
    await store.putUsage(original);
    server.uploadGate = Completer<void>();
    server.uploadArrived = Completer<void>();
    final first = sync.synchronize(
      deviceId: 'desktop',
      platform: 'Windows',
      since: since,
    );
    await server.uploadArrived!.future.timeout(const Duration(seconds: 5));
    var secondFinished = false;
    final second = sync
        .synchronize(deviceId: 'desktop', platform: 'Windows', since: since)
        .then((_) => secondFinished = true);
    await Future<void>.delayed(Duration.zero);
    expect(secondFinished, isFalse);
    await store.putUsage(interval('growing', minutes: 2));
    server.uploadGate!.complete();
    await Future.wait([first, second]);
    expect(server.uploads, 1);
    expect(
      (await store.usage(pendingOnly: true)).single.end,
      interval('growing', minutes: 2).end,
    );
  });

  test(
    'failed uploads keep pending observations and report stale sync status',
    () async {
      await store.putUsage(interval('offline'));
      server.failUploads = true;
      await expectLater(
        sync.synchronize(
          deviceId: 'desktop',
          platform: 'Windows',
          since: since,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect((await store.usage(pendingOnly: true)).single.id, 'offline');
      expect(sync.lastSync, isNull);
      expect(sync.lastError, contains('Network unavailable'));
      expect(sync.syncing, isFalse);
      server.failUploads = false;
      await sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      expect(await store.usage(pendingOnly: true), isEmpty);
      expect(sync.lastError, isNull);
    },
  );

  test(
    'a different account cannot upload the first account local history',
    () async {
      await store.putUsage(interval('owned'));
      await sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      await client.auth.signOut();
      await client.auth.signInWithPassword(
        email: 'other@example.test',
        password: 'test-password-only',
      );
      final previousUploads = server.uploads;
      await expectLater(
        sync.synchronize(
          deviceId: 'desktop',
          platform: 'Windows',
          since: since,
        ),
        throwsStateError,
      );
      expect(server.uploads, previousUploads);
      expect(sync.lastError, contains('different account'));
    },
  );
}
