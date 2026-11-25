import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/data/shared_state.dart';
import 'package:lockin/data/cloud_sync.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/data/device_data.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

const _owner = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';

class _CloudServer {
  late final HttpServer server;
  final rows = <Map<String, dynamic>>[];
  final uploaded = <Map<String, dynamic>>[];
  final sharedRows = <Map<String, dynamic>>[];
  final sharedUploads = <Map<String, dynamic>>[];
  final receipts = <String, Map<String, dynamic>>{};
  int sharedRevision = 0;
  int sharedDownloads = 0;
  int uploads = 0;
  int downloads = 0;
  int unlockStatus = 200;
  Map<String, dynamic> unlockResponse = {'allow': true, 'message': 'Okay.'};
  final unlockRequests = <Map<String, dynamic>>[];
  final downloadedSince = <String>[];
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
      } else if (path == '/rest/v1/rpc/apply_shared_changes') {
        final payload = jsonDecode(body) as Map;
        expect(
          payload['p_expected_owner'],
          _owner,
          reason: 'An account change must not rebind pending mutations.',
        );
        final changes = payload['p_changes'] as List;
        final results = <Map<String, dynamic>>[];
        for (final item in changes) {
          final change = Map<String, dynamic>.from(item as Map);
          final nonce = change['mutation_id'] as String;
          if (receipts.containsKey(nonce)) {
            results.add(receipts[nonce]!);
            continue;
          }
          sharedUploads.add(change);
          var current = sharedRows
              .where(
                (row) =>
                    row['kind'] == change['kind'] && row['id'] == change['id'],
              )
              .firstOrNull;
          final applied =
              (current?['revision'] ?? 0) == change['base_revision'];
          if (applied) {
            sharedRows.remove(current);
            current = {
              'kind': change['kind'],
              'id': change['id'],
              'revision': ++sharedRevision,
              'value': change['value'],
            };
            sharedRows.add(current);
          }
          final result = {
            'mutation_id': nonce,
            'applied': applied,
            'record': current,
          };
          receipts[nonce] = result;
          results.add(result);
        }
        response = results;
      } else if (path == '/rest/v1/shared_state') {
        sharedDownloads++;
        final cursor = int.parse(
          (request.uri.queryParameters['revision'] ?? 'gt.0').substring(3),
        );
        final descending =
            request.uri.queryParameters['order']?.startsWith('revision.desc') ??
            false;
        final ordered =
            sharedRows.where((r) => (r['revision'] as int) > cursor).toList()
              ..sort((a, b) {
                final order = (a['revision'] as int).compareTo(
                  b['revision'] as int,
                );
                return descending ? -order : order;
              });
        response = ordered
            .take(int.parse(request.uri.queryParameters['limit'] ?? '500'))
            .toList();
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
        downloadedSince.add(request.uri.queryParameters['ended_at']!);
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
      } else if (path == '/functions/v1/unlock-check') {
        unlockRequests.add(Map<String, dynamic>.from(jsonDecode(body) as Map));
        request.response.statusCode = unlockStatus;
        response = unlockResponse;
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
  setUpAll(tzdata.initializeTimeZones);
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

  test(
    'the AI unlock check sends the reason and returns the verdict',
    () async {
      Future<({bool allow, String message})> ask() => sync.checkUnlock(
        what: 'end this focus session early',
        because: 'during your focus session',
        reason: 'Teacher needs the YouTube link',
        localTime: 'Tue 10:05 AM',
        unlocksToday: 1,
      );
      final allowed = await ask();
      expect(allowed.allow, isTrue);
      expect(server.unlockRequests.single, {
        'what': 'end this focus session early',
        'because': 'during your focus session',
        'reason': 'Teacher needs the YouTube link',
        'localTime': 'Tue 10:05 AM',
        'unlocksToday': 1,
      });

      server.unlockResponse = {'allow': false, 'message': 'That can wait.'};
      final denied = await ask();
      expect(denied.allow, isFalse);
      expect(denied.message, 'That can wait.');

      // No key on the server yet: the server's own message is shown.
      server
        ..unlockStatus = 503
        ..unlockResponse = {
          'error': 'not_configured',
          'message': "The AI check isn't set up on the server yet.",
        };
      await expectLater(
        ask(),
        throwsA(
          isA<UnlockCheckFailed>().having(
            (e) => e.message,
            'message',
            "The AI check isn't set up on the server yet.",
          ),
        ),
      );

      await client.auth.signOut();
      await expectLater(ask(), throwsA(isA<UnlockCheckFailed>()));
      expect(server.unlockRequests, hasLength(3));
    },
  );

  test(
    'the first sync fetches the past week for insights, later ones today',
    () async {
      Future<void> once() => sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      await once();
      await once();
      expect(server.downloadedSince, [
        'gt.${since.subtract(const Duration(days: 7)).toIso8601String()}',
        'gt.${since.toIso8601String()}',
      ]);
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

  test('device reset drains an in-flight upload before clearing its owner', () async {
    final controller = AppController(store: store, tracker: NativeTracker());
    addTearDown(controller.dispose);
    await controller.initialize(poll: false);
    await store.putUsage(interval('pending-before-reset'));
    server.uploadGate = Completer<void>();
    server.uploadArrived = Completer<void>();
    final upload = sync.synchronize(
      deviceId: controller.deviceId,
      platform: 'Windows',
      since: since,
    );
    final stopped = expectLater(upload, throwsStateError);
    await server.uploadArrived!.future;
    var finished = false;
    final reset = DeviceData(
      controller: controller,
      cloud: sync,
    ).reset().then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(finished, isFalse);
    expect(await store.setting('cloud_owner'), _owner);
    server.uploadGate!.complete();
    await reset;
    await stopped;
    expect(client.auth.currentUser, isNull);
    expect(await store.setting('cloud_owner'), isNull);
    expect(await store.usage(), isEmpty);
    expect(await SharedState(store).pending(), isEmpty);
    // The already-sent request may have reached the server. Local reset is not
    // an assertion that cloud history was deleted.
    expect(server.uploaded.single['id'], 'pending-before-reset');
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

  test('two devices share rules, timezone and timer without copying a focus blocklist', () async {
    var clock = since.add(const Duration(hours: 10));
    final desktop = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => clock,
    );
    await desktop.initialize(poll: false);
    // These represent two devices with independent executors, not shared SQLite.
    final warning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warning,
    );
    final phoneStore = LocalStore.memory();
    final phone = AppController(
      store: phoneStore,
      tracker: NativeTracker(),
      clock: () => clock,
    );
    final phoneSync = CloudSync(client: client, store: phoneStore);
    addTearDown(() async {
      desktop.dispose();
      phone.dispose();
      await phoneSync.close();
      await phoneStore.close();
    });
    await desktop.saveRule(
      ActivityRule(
        id: 'video',
        name: 'Video',
        sources: ['web:example.com'],
        dailyMinutes: 30,
        focusBlock: true,
      ),
    );
    await desktop.setTimezone('America/New_York');
    await desktop.startSession(const Duration(minutes: 25), SessionPhase.focus);
    await sync.synchronize(
      deviceId: desktop.deviceId,
      platform: 'Windows',
      since: since,
    );
    await desktop.reloadSharedState();
    await phone.initialize(initialTimezone: 'Asia/Tokyo', poll: false);
    await phoneSync.synchronize(
      deviceId: phone.deviceId,
      platform: 'Android',
      since: since,
    );
    await phone.reloadSharedState();
    expect(phone.session!.id, desktop.session!.id);
    expect(phone.timezone, 'America/New_York');
    expect(phone.rules.single.name, 'Video');
    expect(phone.rules.single.focusBlock, isFalse);
    expect(desktop.rules.single.focusBlock, isTrue);
    expect(phoneSync.conflicts, isEmpty);
    clock = clock.add(const Duration(minutes: 5));
    await phone.endSession();
    await phoneSync.synchronize(
      deviceId: phone.deviceId,
      platform: 'Android',
      since: since,
    );
    await sync.synchronize(
      deviceId: desktop.deviceId,
      platform: 'Windows',
      since: since,
    );
    await desktop.reloadSharedState();
    expect(desktop.session!.end, clock);
    expect(desktop.focusedToday, const Duration(minutes: 5));
  });

  test(
    'shared state downloads use revision keysets beyond the server row limit',
    () async {
      for (var i = 1; i <= 513; i++) {
        server.sharedRows.add({
          'kind': 'rule',
          'id': 'r$i',
          'revision': i,
          'value': {
            'id': 'r$i',
            'name': 'Rule $i',
            'sources': ['web:example.com'],
            'daily_minutes': null,
            'schedules': [],
          },
        });
      }
      server.sharedRevision = 513;
      await sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      expect(await store.rules(), hasLength(513));
      expect(server.sharedDownloads, 2);
      expect(await store.setting('shared_cursor'), '514');
      await sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      expect(server.sharedDownloads, 3);
    },
  );

  test(
    'a stale offline edit is preserved for explicit review across HTTP sync',
    () async {
      final shared = SharedState(store);
      final value = {
        'id': 'video',
        'name': 'Offline edit',
        'sources': ['web:example.com'],
        'daily_minutes': 30,
        'schedules': [],
      };
      server.sharedRows.add({
        'kind': 'rule',
        'id': 'video',
        'revision': 1,
        'value': {...value, 'name': 'Confirmed edit'},
      });
      server.sharedRevision = 1;
      await shared.queue('rule', 'video', value);
      await sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      expect((await store.rules()).single.name, 'Confirmed edit');
      final conflict = sync.conflicts.single;
      expect(conflict.change.value!['name'], 'Offline edit');
      expect(conflict.confirmedValue!['name'], 'Confirmed edit');
      await sync.resolveConflict(
        conflict.change.mutationId,
        retry: true,
        baseRevision: conflict.confirmedRevision,
      );
      await sync.synchronize(
        deviceId: 'desktop',
        platform: 'Windows',
        since: since,
      );
      expect(sync.conflicts, isEmpty);
      expect(
        server.sharedRows.singleWhere(
          (r) => r['kind'] == 'rule',
        )['value']['name'],
        'Offline edit',
      );
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
