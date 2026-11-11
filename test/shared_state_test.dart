import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/data/shared_state.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  late LocalStore store;
  late AppController controller;
  late SharedState shared;
  final now = DateTime.utc(2026, 11, 11, 12);
  Map<String, dynamic> rule(String name) => {
    'id': 'video',
    'name': name,
    'sources': ['web:example.com'],
    'daily_minutes': 30,
    'schedules': [],
  };
  Map<String, dynamic> record(
    String kind,
    String id,
    int revision,
    Map<String, dynamic>? value,
  ) => {'kind': kind, 'id': id, 'revision': revision, 'value': value};

  setUp(() async {
    store = LocalStore.memory();
    controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
    );
    await controller.initialize(poll: false);
    shared = SharedState(store, clock: () => now);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });

  test('local edits and their durable outbox commit together; focus flags stay device-local', () async {
    await controller.saveRule(
      ActivityRule(
        id: 'video',
        name: 'Video',
        sources: ['web:example.com'],
        focusBlock: true,
      ),
    );
    final change = (await shared.pending()).single;
    expect(change.kind, 'rule');
    expect(change.value!.containsKey('focus_block'), isFalse);
    await shared.accept(
      change,
      applied: true,
      record: record('rule', 'video', 1, change.value),
    );
    await shared.receive(record('rule', 'video', 2, rule('Renamed elsewhere')));
    await controller.reloadSharedState();
    expect(controller.rules.single.name, 'Renamed elsewhere');
    expect(controller.rules.single.focusBlock, isTrue);
    await shared.receive(
      record('rule', 'new', 3, {...rule('New remote rule'), 'id': 'new'}),
    );
    expect((await store.rules()).last.focusBlock, isFalse);
  });

  test('an acknowledgement cannot erase an edit made while the old upload was in flight', () async {
    await shared.queue('rule', 'video', rule('First'));
    final old = (await shared.pending()).single;
    await shared.queue('rule', 'video', rule('Second'));
    await shared.accept(
      old,
      applied: true,
      record: record('rule', 'video', 10, old.value),
    );
    final pending = (await shared.pending()).single;
    expect(pending.value!['name'], 'Second');
    expect(pending.baseRevision, 10);
  });

  test('a conflicting rule is kept for review and never silently overwrites confirmed policy', () async {
    await shared.queue('rule', 'video', rule('Offline edit'));
    final local = (await shared.pending()).single;
    await shared.accept(
      local,
      applied: false,
      record: record('rule', 'video', 7, rule('Confirmed elsewhere')),
    );
    expect((await store.rules()).single.name, 'Confirmed elsewhere');
    expect(await shared.pending(), isEmpty);
    final conflict = (await shared.conflicts()).single;
    expect(conflict.change.value!['name'], 'Offline edit');
    expect(conflict.confirmedValue!['name'], 'Confirmed elsewhere');
    await shared.resolveConflict(conflict.change.mutationId, retry: true);
    expect((await shared.pending()).single.baseRevision, 7);
    expect((await store.rules()).single.name, 'Offline edit');
  });

  test('new devices adopt the account timezone without a spurious bootstrap conflict', () async {
    await shared.seed();
    final timezone = (await shared.pending()).singleWhere(
      (c) => c.kind == 'setting',
    );
    await shared.accept(
      timezone,
      applied: false,
      record: record('setting', 'timezone', 5, {
        'timezone': 'America/New_York',
      }),
    );
    expect(await store.setting('timezone'), 'America/New_York');
    expect(await shared.conflicts(), isEmpty);
  });

  test('the confirmed shared focus session replaces and trims a competing local session', () async {
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    final local = controller.session!;
    final other = FocusSession(
      id: 'other-device',
      phase: SessionPhase.rest,
      start: now.subtract(const Duration(seconds: 5)),
      end: now.add(const Duration(minutes: 5)),
      label: 'Break',
    );
    final focus = (await shared.pending()).singleWhere(
      (c) => c.kind == 'focus',
    );
    await shared.accept(
      focus,
      applied: false,
      record: record('focus', 'active', 4, other.toJson()),
    );
    await controller.reloadSharedState();
    expect(controller.session!.id, other.id);
    final row = await store
        .customSelect(
          'SELECT value FROM sessions WHERE id=?',
          variables: [Variable(local.id)],
        )
        .getSingleOrNull();
    if (row != null) {
      final stopped = FocusSession.fromJson(
        jsonDecode(row.read<String>('value')) as Map<String, dynamic>,
      );
      expect(stopped.end.isAfter(now), isFalse);
    }
    expect(await store.setting('shared_notice'), contains('another device'));
  });

  test('replaying an older focus acknowledgement cannot resurrect shortened history', () async {
    final planned = FocusSession(
      id: 'shared',
      phase: SessionPhase.focus,
      start: now.subtract(const Duration(minutes: 10)),
      end: now.add(const Duration(minutes: 15)),
    );
    await shared.receive(record('focus', 'active', 1, planned.toJson()));
    final stopped = planned.finish(now.subtract(const Duration(minutes: 1)));
    await shared.receive(record('session', 'shared', 2, stopped.toJson()));
    await shared.receive(record('focus', 'active', 1, planned.toJson()));
    await controller.reloadSharedState();
    expect(controller.session!.end, stopped.end);
    expect(controller.history.single.end, stopped.end);
  });

  test('remote tombstones remove rules but an unacknowledged newer local edit is preserved', () async {
    await shared.receive(record('rule', 'video', 1, rule('Original')));
    await shared.queue('rule', 'video', rule('Pending'));
    await shared.receive(record('rule', 'video', 2, null));
    expect((await shared.pending()).single.value!['name'], 'Pending');
    final pending = (await shared.pending()).single;
    await shared.accept(
      pending,
      applied: false,
      record: record('rule', 'video', 2, null),
    );
    expect(await store.rules(), isEmpty);
    expect(await shared.conflicts(), hasLength(1));
  });
}
