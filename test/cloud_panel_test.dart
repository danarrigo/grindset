import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/data/cloud_sync.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/data/shared_state.dart';
import 'package:lockin/platform/app_links.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/cloud_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _PkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

void main() {
  test('a saved edit is named for what it changed', () {
    SharedChange change(String kind, String id, [Map<String, dynamic>? v]) =>
        SharedChange(
          kind: kind,
          id: id,
          mutationId: 'm',
          baseRevision: 1,
          value: v,
        );
    expect(conflictTitle(change('setting', 'focus_hours')), 'Focus hours');
    expect(conflictTitle(change('setting', 'timezone')), 'Account timezone');
    expect(conflictTitle(change('setting', 'strict_mode')), 'Strict mode');
    expect(conflictTitle(change('rule', 'r', {'name': 'Games'})), 'Games');
    expect(conflictTitle(change('rule', 'r')), 'Deleted rule');
  });

  testWidgets('signup and resend request the public confirmation destination', (
    tester,
  ) async {
    tzdata.initializeTimeZones();
    final requests = <http.Request>[];
    final network = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/signup')) {
        return http.Response(
          jsonEncode({
            'id': '11111111-1111-4111-8111-111111111111',
            'aud': 'authenticated',
            'email': 'fixture@example.test',
            'created_at': '2026-11-14T00:00:00Z',
            'app_metadata': <String, Object>{},
            'user_metadata': <String, Object>{},
            'identities': <Object>[],
          }),
          200,
        );
      }
      expect(request.url.path, endsWith('/resend'));
      return http.Response('{}', 200);
    });
    late final SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://fixture.supabase.co',
        'public-test-key',
        httpClient: network,
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: _PkceStorage(),
        ),
      );
    });
    final store = LocalStore.memory();
    final controller = AppController(store: store, tracker: NativeTracker());
    await controller.initialize(poll: false);
    final cloud = CloudSync(client: client, store: store);
    addTearDown(() async {
      await cloud.close();
      controller.dispose();
      await tester.runAsync(client.dispose);
      await store.close();
      network.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudPanel(
              controller: controller,
              cloud: cloud,
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'fixture@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'fixture-password',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Check your email'),
      findsOneWidget,
      reason: tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data)
          .join('\n'),
    );
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.ensureVisible(find.text('Resend confirmation email'));
    await tester.tap(find.text('Resend confirmation email'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Confirmation email requested'), findsOneWidget);
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(
        request.url.queryParameters['redirect_to'],
        AppLinks.confirmation.toString(),
      );
      expect(jsonDecode(request.body)['email'], 'fixture@example.test');
    }
    expect(await store.setting('cloud_owner'), isNull);
    expect(client.auth.currentSession, isNull);
  });

  testWidgets(
    'deleting an account asks first, deletes on the server, then resets',
    (tester) async {
      tzdata.initializeTimeZones();
      final rpcs = <String>[];
      var failDelete = true;
      final network = MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'fixture-access',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'fixture-refresh',
              'user': {
                'id': '11111111-1111-4111-8111-111111111111',
                'aud': 'authenticated',
                'email': 'fixture@example.test',
                'created_at': '2026-11-14T00:00:00Z',
                'app_metadata': <String, Object>{},
                'user_metadata': <String, Object>{},
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/rpc/delete_account')) {
          rpcs.add(request.headers['Authorization'] ?? '');
          return failDelete
              ? http.Response('{"message":"offline"}', 503, request: request)
              : http.Response('', 204, request: request);
        }
        return http.Response('{}', 200);
      });
      late final SupabaseClient client;
      await tester.runAsync(() async {
        client = SupabaseClient(
          'https://fixture.supabase.co',
          'public-test-key',
          httpClient: network,
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: _PkceStorage(),
          ),
        );
        await client.auth.signInWithPassword(
          email: 'fixture@example.test',
          password: 'fixture-password',
        );
      });
      final store = LocalStore.memory();
      final controller = AppController(store: store, tracker: NativeTracker());
      await controller.initialize(poll: false);
      final cloud = CloudSync(client: client, store: store);
      var resets = 0;
      addTearDown(() async {
        await cloud.close();
        controller.dispose();
        await tester.runAsync(client.dispose);
        await store.close();
        network.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CloudPanel(
                controller: controller,
                cloud: cloud,
                onChanged: () {},
                resetDevice: () async => resets++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rpcs, isEmpty);

      // A failed delete keeps this device as it is.
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(rpcs, hasLength(1));
      expect(resets, 0);

      failDelete = false;
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(rpcs, ['Bearer fixture-access', 'Bearer fixture-access']);
      expect(
        resets,
        1,
        reason: tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data)
            .join('\n'),
      );
    },
  );
}
