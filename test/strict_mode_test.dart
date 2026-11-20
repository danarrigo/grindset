import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/data/shared_state.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  // Tuesday 2026-11-10, 10:00 UTC.
  var now = DateTime.utc(2026, 11, 10, 10);
  late LocalStore store;
  late AppController controller;
  final games = ActivityRule(
    id: 'games',
    name: 'Games',
    sources: ['web:game.test', 'web:play.test'],
    dailyMinutes: 30,
  );
  final locked = isA<StrictModeLocked>();

  setUp(() async {
    now = DateTime.utc(2026, 11, 10, 10);
    store = LocalStore.memory();
    controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
    );
    await controller.initialize(poll: false);
    await controller.saveRule(games);
    await controller.setStrictMode(true);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });

  test('a stricter rule is one that blocks at least as much', () {
    ActivityRule edit(Map<String, Object?> change) =>
        ActivityRule.fromJson({...games.toJson(), ...change});
    expect(isStricter(games, edit({'name': 'Gaming'})), isTrue);
    expect(isStricter(games, edit({'daily_minutes': 15})), isTrue);
    expect(
      isStricter(
        games,
        edit({
          'sources': ['web:game.test', 'web:play.test', 'web:more.test'],
        }),
      ),
      isTrue,
    );
    expect(isStricter(games, edit({'daily_minutes': 60})), isFalse);
    expect(isStricter(games, edit({'daily_minutes': null})), isFalse);
    expect(isStricter(games, edit({'focus_block': false})), isFalse);
    expect(
      isStricter(
        games,
        edit({
          'sources': ['web:game.test'],
        }),
      ),
      isFalse,
    );
  });

  test('unlocked, everything can change', () async {
    expect(controller.strictLock, isNull);
    await controller.saveRule(
      ActivityRule.fromJson({...games.toJson(), 'daily_minutes': 60}),
    );
    await controller.deleteRule('games');
    await controller.setStrictMode(false);
    expect(controller.strictMode, isFalse);
  });

  test('during a focus session nothing can be loosened', () async {
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    expect(controller.strictLock, 'during your focus session');
    await expectLater(controller.endSession(), throwsA(locked));
    await expectLater(controller.deleteRule('games'), throwsA(locked));
    await expectLater(
      controller.saveRule(
        ActivityRule.fromJson({...games.toJson(), 'daily_minutes': 60}),
      ),
      throwsA(locked),
    );
    await expectLater(controller.setStrictMode(false), throwsA(locked));
    await expectLater(controller.disableTracking(), throwsA(locked));
    await expectLater(controller.prepareForReset(), throwsA(locked));
    // Stricter is fine.
    await controller.saveRule(
      ActivityRule.fromJson({...games.toJson(), 'daily_minutes': 10}),
    );
    expect(controller.rules.single.dailyMinutes, 10);
    // When the session is over, it unlocks.
    now = now.add(const Duration(minutes: 26));
    expect(controller.strictLock, isNull);
    await controller.deleteRule('games');
  });

  test(
    'a reached daily limit locks, and Android uninstalling is paused',
    () async {
      expect(
        controller.restrictionForSource('android:com.android.packageinstaller'),
        isNull,
      );
      await store.putUsage(
        UsageInterval(
          id: 'u',
          deviceId: controller.deviceId,
          source: 'web:game.test',
          start: now.subtract(const Duration(minutes: 31)),
          end: now,
        ),
      );
      await controller.reloadUsage();
      expect(controller.strictLock, 'while a daily limit is reached');
      await expectLater(controller.deleteRule('games'), throwsA(locked));
      expect(
        controller.restrictionForSource('android:com.android.packageinstaller'),
        contains('uninstalling apps is paused'),
      );
    },
  );

  test('Focus hours can grow but not shrink while locked', () async {
    final weekdays = ScheduleWindow(
      weekdays: [1, 2, 3, 4, 5],
      startMinute: 9 * 60,
      endMinute: 17 * 60,
    );
    await controller.setFocusHours([weekdays]);
    expect(controller.strictLock, 'during Focus hours');
    final weekend = ScheduleWindow(
      weekdays: [6, 7],
      startMinute: 9 * 60,
      endMinute: 12 * 60,
    );
    await controller.setFocusHours([weekdays, weekend]);
    await expectLater(controller.setFocusHours([weekend]), throwsA(locked));
    await expectLater(controller.setFocusHours([]), throwsA(locked));
  });

  test('strict mode is shared with the account\'s devices', () async {
    final shared = SharedState(store, clock: () => now);
    final change = (await shared.pending()).firstWhere(
      (c) => c.id == 'strict_mode',
    );
    expect(change.value, {'enabled': true});

    // Another device turns it off; a device with no unsent edits follows.
    final other = LocalStore.memory();
    addTearDown(other.close);
    final device = AppController(
      store: other,
      tracker: NativeTracker(),
      clock: () => now,
    );
    await device.initialize(poll: false);
    addTearDown(device.dispose);
    final incoming = SharedState(other, clock: () => now);
    await incoming.receive({
      'kind': 'setting',
      'id': 'strict_mode',
      'revision': 4,
      'value': {'enabled': true},
    });
    await device.reloadSharedState();
    expect(device.strictMode, isTrue);
    await incoming.receive({
      'kind': 'setting',
      'id': 'strict_mode',
      'revision': 5,
      'value': {'enabled': false},
    });
    await device.reloadSharedState();
    expect(device.strictMode, isFalse);
    await expectLater(
      incoming.receive({
        'kind': 'setting',
        'id': 'strict_mode',
        'revision': 6,
        'value': {'enabled': 'yes'},
      }),
      throwsA(anything),
    );
  });

  test('the message reads as a sentence', () async {
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    await expectLater(
      controller.deleteRule('games'),
      throwsA(
        predicate(
          (e) => e.toString() == 'Strict mode: you can\'t delete a rule during your focus session.',
        ),
      ),
    );
  });
}
