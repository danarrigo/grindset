import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  // Tuesday 2026-11-10, 10:00 UTC: inside Focus hours (9:00-17:00).
  late DateTime now;
  late LocalStore store;
  late AppController controller;
  final hours = ScheduleWindow(
    weekdays: [1, 2, 3, 4, 5],
    startMinute: 9 * 60,
    endMinute: 17 * 60,
  );

  setUp(() async {
    now = DateTime.utc(2026, 11, 10, 10);
    store = LocalStore.memory();
    controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
    );
    await controller.initialize(poll: false);
    await controller.saveRule(
      ActivityRule(id: 'games', name: 'Games', sources: ['web:game.test']),
    );
    await controller.setFocusHours([hours]);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });

  test('without the pause, loosening works as before', () async {
    await controller.deleteRule('games');
    expect(controller.rules, isEmpty);
  });

  test(
    'while blocking, loosening waits for a reason, then goes ahead',
    () async {
      await controller.setUnlockPause(60);
      expect(controller.needsUnlockPause, isTrue);
      await expectLater(
        controller.setFocusHours([]),
        throwsA(
          isA<UnlockPauseNeeded>().having(
            (e) => e.what,
            'what',
            'shorten or turn off Focus hours',
          ),
        ),
      );
      expect(controller.focusHours, isNotEmpty);

      await controller.recordUnlock('turn off Focus hours', 'Day off');
      await controller.setFocusHours([]);
      expect(controller.focusHours, isEmpty);

      // Passing the pause lets one change through, not the rest of the day.
      await controller.setFocusHours([hours]);
      now = now.add(const Duration(minutes: 3));
      expect(
        () => controller.deleteRule('games'),
        throwsA(isA<UnlockPauseNeeded>()),
      );
    },
  );

  test(
    'nothing to unlock outside blocking, and strict mode still wins',
    () async {
      await controller.setUnlockPause(30);
      now = DateTime.utc(2026, 11, 10, 18);
      expect(controller.needsUnlockPause, isFalse);
      await controller.deleteRule('games');

      now = DateTime.utc(2026, 11, 10, 10);
      await controller.saveRule(
        ActivityRule(id: 'games', name: 'Games', sources: ['web:game.test']),
      );
      await controller.setStrictMode(true);
      expect(controller.needsUnlockPause, isFalse);
      expect(
        () => controller.deleteRule('games'),
        throwsA(isA<StrictModeLocked>()),
      );
    },
  );

  test('a break stops blocking here for 15 minutes', () async {
    await controller.setUnlockPause(30);
    expect(controller.restrictionForSource('web:game.test'), 'Focus hours');
    await controller.recordUnlock(
      'take a 15-minute break',
      'Lunch video',
      takeBreak: true,
    );
    expect(controller.onBreak, isTrue);
    expect(controller.restrictionForSource('web:game.test'), isNull);
    expect(controller.websiteRestrictions()['blocked'], isEmpty);
    // A break is not a way around the pause for other changes.
    expect(controller.needsUnlockPause, isFalse);

    now = now.add(const Duration(minutes: 15));
    expect(controller.onBreak, isFalse);
    expect(controller.restrictionForSource('web:game.test'), 'Focus hours');

    now = now.add(const Duration(minutes: 1));
    await controller.recordUnlock('take a break', 'Call', takeBreak: true);
    await controller.endBreak();
    expect(controller.restrictionForSource('web:game.test'), 'Focus hours');

    // Strict mode turned on mid-break ends it.
    await controller.recordUnlock('take a break', 'Call', takeBreak: true);
    await controller.setStrictMode(true);
    expect(controller.restrictionForSource('web:game.test'), 'Focus hours');
  });

  test('shortening the pause while blocking needs the pause too', () async {
    await controller.setUnlockPause(300);
    await expectLater(
      controller.setUnlockPause(0),
      throwsA(isA<UnlockPauseNeeded>()),
    );
    await controller.setUnlockPause(300);
    expect(controller.unlockPause, 300);
    now = DateTime.utc(2026, 11, 10, 18);
    await controller.setUnlockPause(0);
    expect(controller.unlockPause, 0);
  });

  test('pause, break and reasons survive a restart', () async {
    await controller.setUnlockPause(60);
    await controller.recordUnlock('end this focus session early', 'Tutorial');
    await controller.recordUnlock('take a break', 'Bored', takeBreak: true);
    final reopened = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
    );
    await reopened.initialize(poll: false);
    addTearDown(reopened.dispose);
    expect(reopened.unlockPause, 60);
    expect(reopened.onBreak, isTrue);
    expect(reopened.unlocksToday.map((u) => u.reason), ['Bored', 'Tutorial']);

    now = DateTime.utc(2026, 11, 11, 10);
    expect(reopened.unlocksToday, isEmpty);
    expect(reopened.unlocks, hasLength(2));
  });
}
