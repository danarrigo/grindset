import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/device_auth_storage.dart';
import 'package:lockin/data/device_data.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _AuthStorage extends LocalStorage {
  String? session;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => session != null;
  @override
  Future<String?> accessToken() async => session;
  @override
  Future<void> persistSession(String value) async {
    if (!started.isCompleted) started.complete();
    await gate?.future;
    session = value;
  }

  @override
  Future<void> removePersistedSession() async => session = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  test(
    'reset seals auth storage against delayed and late session writes',
    () async {
      final disk = _AuthStorage()..gate = Completer<void>();
      final storage = DeviceAuthStorage(disk);
      final pending = storage.persistSession('old-session');
      await disk.started.future;
      final clear = storage.clearForReset();
      final late = storage.persistSession('late-refresh');
      disk.gate!.complete();
      await Future.wait([pending, clear, late]);
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    },
  );

  test('device reset is local and next launch has a new identity with tracking off', () async {
    final store = LocalStore.memory();
    addTearDown(store.close);
    final controller = AppController(store: store, tracker: NativeTracker());
    addTearDown(controller.dispose);
    await controller.initialize(poll: false);
    final oldDevice = controller.deviceId;
    await store.saveSetting('cloud_owner', 'old-account');
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    final disk = _AuthStorage()..session = 'old-session';
    await DeviceData(
      controller: controller,
      authStorage: DeviceAuthStorage(disk),
    ).reset();
    expect(await store.setting('cloud_owner'), isNull);
    expect(await store.usage(), isEmpty);
    expect(await disk.hasAccessToken(), isFalse);
    // The old runtime is stopped, not silently reused with a different owner.
    await controller.refresh();
    final next = AppController(store: store, tracker: NativeTracker());
    addTearDown(next.dispose);
    await next.initialize(poll: false);
    expect(next.deviceId, isNot(oldDevice));
    expect(next.trackingEnabled, isFalse);
    expect(next.completionAlertsEnabled, isFalse);
    expect(next.session, isNull);
    expect(next.history, isEmpty);
    expect(next.rules, isEmpty);
  });
}
