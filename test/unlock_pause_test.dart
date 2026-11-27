import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/unlock_pause_dialog.dart';
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

  test(
    'an AI can open one blocked site for a few minutes, even in strict mode',
    () async {
      await controller.saveRule(
        ActivityRule(
          id: 'social',
          name: 'Social',
          sources: ['web:linkedin.com', 'web:youtube.com'],
        ),
      );
      await controller.setStrictMode(true);
      final asked = <String>[];
      UnlockVerdict answer = (
        allow: false,
        message: 'That can wait.',
        minutes: null,
      );
      UnlockVerdict? verdict;
      Future<UnlockVerdict> ask(String reason) => controller.requestPass(
        'web:linkedin.com',
        name: 'linkedin.com',
        reason: reason,
      );

      // Without an AI there is no way in.
      expect(controller.canAskForPass('web:linkedin.com'), isFalse);
      verdict = await ask('A recruiter messaged me');
      expect(verdict.allow, isFalse);

      controller.askAi =
          ({
            required what,
            required because,
            required reason,
            required localTime,
            required unlocksToday,
          }) async {
            asked.add('$what / $because / $reason / $localTime');
            return answer;
          };
      verdict = await ask('Bored');
      expect(verdict.message, 'That can wait.');
      expect(
        controller.restrictionForSource('web:linkedin.com'),
        'Focus hours',
      );

      answer = (allow: true, message: 'Okay.', minutes: 90);
      verdict = await ask('A recruiter messaged me');
      expect(asked.last, contains('open linkedin.com for a few minutes'));
      expect(asked.last, contains('during Focus hours'));
      expect(asked.last, contains('Tue 10:00'));
      // Never longer than 30 minutes, whatever the AI says.
      expect(verdict.minutes, 30);
      expect(controller.restrictionForSource('web:linkedin.com'), isNull);
      expect(controller.restrictionForSource('web:www.linkedin.com'), isNull);
      // Only that site: the rest of the rule, and other rules, stay blocked.
      expect(controller.restrictionForSource('web:youtube.com'), 'Focus hours');
      expect(controller.restrictionForSource('web:game.test'), 'Focus hours');
      controller.trackingEnabled = true;
      expect(
        (controller.websiteRestrictions()['blocked'] as List).map(
          (e) => (e as Map)['domain'],
        ),
        unorderedEquals(['youtube.com', 'game.test']),
      );
      expect(
        controller.unlocksToday.first.what,
        'open linkedin.com for 30 min',
      );

      // It survives a restart, then ends on time.
      final reopened = AppController(
        store: store,
        tracker: NativeTracker(),
        clock: () => now,
      );
      await reopened.initialize(poll: false);
      expect(reopened.restrictionForSource('web:linkedin.com'), isNull);
      reopened.dispose();
      now = now.add(const Duration(minutes: 30));
      expect(
        controller.restrictionForSource('web:linkedin.com'),
        'Focus hours',
      );

      // Nothing to ask for once nothing blocks it.
      now = DateTime.utc(2026, 11, 10, 18);
      expect(controller.canAskForPass('web:linkedin.com'), isFalse);
    },
  );

  test('the block screen knows what blocks it and until when', () async {
    // Focus hours 9:00-17:00 (UTC here), and it is 10:00.
    final hoursSpan = controller.blockSpan('web:game.test')!;
    expect(hoursSpan.label, 'Focus hours');
    expect(hoursSpan.from, DateTime.utc(2026, 11, 10, 9));
    expect(hoursSpan.until, DateTime.utc(2026, 11, 10, 17));

    // Overnight 22:00-06:00, seen after midnight, began the day before.
    final night = ScheduleWindow(
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startMinute: 22 * 60,
      endMinute: 6 * 60,
    );
    expect(night.span(DateTime.utc(2026, 11, 11, 2), controller.location), (
      DateTime.utc(2026, 11, 10, 22),
      DateTime.utc(2026, 11, 11, 6),
    ));
    expect(night.span(DateTime.utc(2026, 11, 10, 23), controller.location), (
      DateTime.utc(2026, 11, 10, 22),
      DateTime.utc(2026, 11, 11, 6),
    ));
    expect(
      night.span(DateTime.utc(2026, 11, 10, 12), controller.location),
      isNull,
    );

    // A focus session wins over Focus hours while it runs.
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    final sessionSpan = controller.blockSpan('web:game.test')!;
    expect(sessionSpan.label, 'Focus session');
    expect(sessionSpan.until, now.add(const Duration(minutes: 25)));

    // Nothing blocks it in the evening.
    now = DateTime.utc(2026, 11, 10, 18);
    expect(controller.blockSpan('web:game.test'), isNull);
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

  test('turning off the AI check while blocking needs the pause', () async {
    await controller.setUnlockPause(30);
    await controller.setAiUnlock(true);
    await expectLater(
      controller.setAiUnlock(false),
      throwsA(isA<UnlockPauseNeeded>()),
    );
    expect(controller.aiUnlock, isTrue);
    now = DateTime.utc(2026, 11, 10, 18);
    await controller.setAiUnlock(false);
    expect(controller.aiUnlock, isFalse);
  });

  testWidgets('the AI says no with a reason, then yes after another wait', (
    tester,
  ) async {
    final asked = <String>[];
    var allow = false;
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => UnlockPauseDialog(
                  what: 'end this focus session early',
                  seconds: 5,
                  because: 'during your focus session',
                  judge: (reason) async {
                    asked.add(reason);
                    return allow
                        ? (
                            allow: true,
                            message: 'Okay, go ahead.',
                            minutes: null,
                          )
                        : (
                            allow: false,
                            message: 'A video can wait.',
                            minutes: null,
                          );
                  },
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('unlock-reason')),
      'Bored',
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Ask AI'), findsOneWidget);
    await tester.tap(find.text('Ask AI'));
    await tester.pump();
    expect(find.text('A video can wait.'), findsOneWidget);
    expect(find.text('Wait 0:05'), findsOneWidget);

    allow = true;
    await tester.enterText(
      find.byKey(const ValueKey('unlock-reason')),
      'Teacher sent the lesson video',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    expect(result, 'Teacher sent the lesson video');
    expect(asked, ['Bored', 'Teacher sent the lesson video']);
  });

  testWidgets('without an answer from the AI, it stays locked', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => UnlockPauseDialog(
                  what: 'take a 15-minute break',
                  seconds: 1,
                  because: 'during Focus hours',
                  judge: (_) async => throw Exception('offline'),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('unlock-reason')), 'Call');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Ask AI'));
    await tester.pump();
    expect(find.byKey(const ValueKey('unlock-verdict')), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Never mind'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
