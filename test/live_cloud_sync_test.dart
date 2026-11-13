import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/cloud_sync.dart';
import 'package:lockin/data/device_data.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:uuid/uuid.dart';

class _Network extends http.BaseClient {
  final _client = http.Client();
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('Isolated test transport offline');
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}

void main() {
  final credentialsPath = Platform.environment['LOCKIN_LIVE_AUTH_FILE'];
  test(
    'hosted Auth, independent journals, conflicts, RLS and local-only reset',
    () async {
      HttpOverrides.global = null;
      tzdata.initializeTimeZones();
      final credentials = jsonDecode(
        await File(credentialsPath!).readAsString(),
      ) as Map<String, dynamic>;
      expect(
        (credentials['key'] as String).startsWith('sb_publishable_'),
        isTrue,
        reason: 'Live clients require a public publishable key, never an admin key.',
      );
      final accounts = (credentials['accounts'] as List)
          .cast<Map<String, dynamic>>();
      expect(accounts, hasLength(2));
      expect(
        accounts.every(
          (account) =>
              (account['email'] as String).startsWith('lockin-acceptance-'),
        ),
        isTrue,
        reason: 'Use disposable acceptance accounts, never personal accounts.',
      );
      final warning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warning,
      );
      final directory = await Directory.systemTemp.createTemp('lockin-live-');
      final clients = <SupabaseClient>[];
      final stores = <LocalStore>[];
      final controllers = <AppController>[];
      final syncs = <CloudSync>[];
      final networks = <_Network>[];
      addTearDown(() async {
        for (final sync in syncs) {
          await sync.close();
        }
        for (final controller in controllers) {
          controller.dispose();
        }
        for (final client in clients) {
          await client.dispose();
        }
        for (final store in stores) {
          await store.close();
        }
        for (final network in networks) {
          network.close();
        }
        await directory.delete(recursive: true);
      });

      for (var index = 0; index < 3; index++) {
        final network = _Network();
        networks.add(network);
        final client = SupabaseClient(
          credentials['url'] as String,
          credentials['key'] as String,
          httpClient: network,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        clients.add(client);
        final account = accounts[index == 2 ? 1 : 0];
        if (index != 1) {
          try {
            await client.auth.signInWithPassword(
              email: account['email'] as String,
              password: account['password'] as String,
            );
          } on AuthException catch (error) {
            if (error.code != 'email_not_confirmed') rethrow;
            await client.auth.verifyOTP(
              tokenHash: account['token_hash'] as String,
              type: OtpType.signup,
            );
          }
          expect(client.auth.currentUser?.emailConfirmedAt != null, isTrue);
          await client.auth.signOut(scope: SignOutScope.local);
        }
        await client.auth.signInWithPassword(
          email: account['email'] as String,
          password: account['password'] as String,
        );
        expect(client.auth.currentUser?.id == account['id'], isTrue);
        final store = LocalStore.file(
          File('${directory.path}/device-$index.sqlite'),
        );
        stores.add(store);
        final controller = AppController(
          store: store,
          tracker: NativeTracker(),
        );
        controllers.add(controller);
        await controller.initialize(poll: false);
        syncs.add(CloudSync(client: client, store: store));
      }
      final a = controllers[0];
      final b = controllers[1];
      final other = controllers[2];
      final since = DateTime.now().toUtc().subtract(const Duration(days: 1));
      Future<void> sync(int index) async {
        await syncs[index].synchronize(
          deviceId: controllers[index].deviceId,
          platform: index == 1 ? 'Android' : 'Windows',
          since: since,
        );
        await controllers[index].reloadSharedState();
      }

      final ruleId = const Uuid().v4();
      ActivityRule rule(String name) => ActivityRule(
        id: ruleId,
        name: name,
        sources: ['web:acceptance.example.test'],
        dailyMinutes: 30,
        schedules: [
          ScheduleWindow(
            weekdays: [1, 2, 3, 4, 5],
            startMinute: 9 * 60,
            endMinute: 17 * 60,
          ),
        ],
      );
      await a.saveRule(rule('Hosted acceptance'));
      await a.setTimezone('Australia/Sydney');
      await a.startSession(const Duration(minutes: 5), SessionPhase.focus);
      final sessionId = a.session!.id;
      await sync(0);
      await sync(1);
      expect(b.rules.single.name, 'Hosted acceptance');
      expect(b.rules.single.dailyMinutes, 30);
      expect(b.rules.single.schedules.single.weekdays, {1, 2, 3, 4, 5});
      expect(b.rules.single.focusBlock, isFalse);
      expect(b.timezone, 'Australia/Sydney');
      expect(b.session?.id, sessionId);
      expect(syncs[1].conflicts, isEmpty);

      final now = DateTime.now().toUtc();
      for (var index = 0; index < 2; index++) {
        await stores[index].putUsage(
          UsageInterval(
            id: const Uuid().v4(),
            deviceId: controllers[index].deviceId,
            source: 'web:acceptance.example.test',
            start: now.subtract(Duration(seconds: 180 - index * 30)),
            end: now.subtract(Duration(seconds: 120 - index * 30)),
          ),
        );
      }
      await sync(0);
      await sync(1);
      await sync(0);
      expect(a.usage, hasLength(2));
      expect(b.usage, hasLength(2));
      expect(combinedUsage(a.usage), const Duration(seconds: 90));
      expect(await stores[0].usage(pendingOnly: true), isEmpty);
      expect(await stores[1].usage(pendingOnly: true), isEmpty);
      expect(syncs[0].devices, hasLength(2));

      networks[1].offline = true;
      await b.saveRule(rule('Saved offline edit'));
      await expectLater(sync(1), throwsA(isA<SocketException>()));
      expect(await b.sharedState.pending(), isNotEmpty);
      await a.saveRule(rule('Confirmed elsewhere'));
      await sync(0);
      networks[1].offline = false;
      await sync(1);
      expect(b.rules.single.name, 'Confirmed elsewhere');
      expect(syncs[1].conflicts, hasLength(1));
      final conflict = syncs[1].conflicts.single;
      await syncs[1].resolveConflict(
        conflict.change.mutationId,
        retry: true,
        baseRevision: conflict.confirmedRevision,
      );
      await sync(1);
      await sync(0);
      expect(a.rules.single.name, 'Saved offline edit');
      expect(syncs[1].conflicts, isEmpty);

      await b.endSession();
      await sync(1);
      await sync(0);
      expect(a.session?.id, sessionId);
      expect(a.session!.running(DateTime.now().toUtc()), isFalse);
      expect(a.history.single.end, b.history.single.end);

      await sync(2);
      expect(other.rules, isEmpty);
      expect(other.usage, isEmpty);
      expect(other.history, isEmpty);
      expect(await clients[2].from('usage_intervals').select(), isEmpty);
      final otherDevices = await clients[2].from('devices').select();
      expect(otherDevices, hasLength(1));
      expect(otherDevices.single['id'], other.deviceId);
      final otherShared = await clients[2].from('shared_state').select();
      expect(
        otherShared.every((row) => row['user_id'] == accounts[1]['id']),
        isTrue,
      );
      await expectLater(
        clients[2].from('devices').upsert({
          'user_id': accounts[0]['id'],
          'id': other.deviceId,
          'label': 'Forbidden test write',
          'platform': 'Windows',
        }),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );

      final remoteBefore = await clients[1].from('usage_intervals').select();
      final oldDevice = a.deviceId;
      await DeviceData(controller: a, cloud: syncs[0]).reset();
      expect(clients[0].auth.currentSession == null, isTrue);
      expect(await stores[0].usage(), isEmpty);
      expect(await stores[0].setting('cloud_owner'), isNull);
      await clients[1].auth.refreshSession();
      expect(clients[1].auth.currentUser?.id == accounts[0]['id'], isTrue);
      expect(
        await clients[1].from('usage_intervals').select(),
        unorderedEquals(remoteBefore),
      );
      expect(await clients[1].from('shared_state').select(), isNotEmpty);
      a.dispose();
      await stores[0].close();
      final reopened = LocalStore.file(
        File('${directory.path}/device-0.sqlite'),
      );
      stores.add(reopened);
      final fresh = AppController(store: reopened, tracker: NativeTracker());
      controllers.add(fresh);
      await fresh.initialize(poll: false);
      expect(fresh.deviceId, isNot(oldDevice));
      expect(fresh.trackingEnabled, isFalse);
      expect(fresh.completionAlertsEnabled, isFalse);
    },
    skip: credentialsPath == null
        ? 'Opt-in: LOCKIN_LIVE_AUTH_FILE with isolated hosted signup accounts.'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
