import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/data/shared_state.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/focus_hours_dialog.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  // Tuesday 2026-11-10, 10:00 UTC.
  var now = DateTime.utc(2026, 11, 10, 10);
  late LocalStore store;
  late AppController controller;
  final weekdays = ScheduleWindow(
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
    await controller.saveRule(
      ActivityRule(
        id: 'news',
        name: 'News',
        sources: ['web:news.test'],
        focusBlock: false,
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });

  test('during Focus hours, rules that block while focusing are on', () async {
    expect(controller.restrictionForSource('web:game.test'), isNull);
    await controller.setFocusHours([weekdays]);
    expect(controller.restrictionForSource('web:game.test'), 'Focus hours');
    expect(controller.focusHoursEnd, 17 * 60);
    // A rule that does not block while focusing is untouched.
    expect(controller.restrictionForSource('web:news.test'), isNull);
    // Outside the hours, nothing is blocked.
    now = DateTime.utc(2026, 11, 10, 18);
    expect(controller.restrictionForSource('web:game.test'), isNull);
    now = DateTime.utc(2026, 11, 14, 10); // Saturday
    expect(controller.restrictionForSource('web:game.test'), isNull);
  });

  test('Focus hours are saved, shared, and turned off with no times', () async {
    await controller.setFocusHours([weekdays]);
    final shared = SharedState(store, clock: () => now);
    final change = (await shared.pending()).firstWhere(
      (c) => c.id == 'focus_hours',
    );
    expect(change.kind, 'setting');
    expect(change.value, {
      'schedules': [weekdays.toJson()],
    });

    final reopened = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
    );
    await reopened.initialize(poll: false);
    addTearDown(reopened.dispose);
    expect(reopened.focusHours.single.toJson(), weekdays.toJson());

    await controller.setFocusHours([]);
    expect(controller.focusHours, isEmpty);
    expect(controller.restrictionForSource('web:game.test'), isNull);
  });

  test('Focus hours set on another device apply here', () async {
    final shared = SharedState(store, clock: () => now);
    await shared.receive({
      'kind': 'setting',
      'id': 'focus_hours',
      'revision': 3,
      'value': {
        'schedules': [weekdays.toJson()],
      },
    });
    await controller.reloadSharedState();
    expect(controller.restrictionForSource('web:game.test'), 'Focus hours');
    await expectLater(
      shared.receive({
        'kind': 'setting',
        'id': 'focus_hours',
        'revision': 4,
        'value': {
          'schedules': [
            {
              'weekdays': [9],
              'start_minute': 0,
              'end_minute': 60,
            },
          ],
        },
      }),
      throwsA(anything),
    );
  });

  testWidgets('the Focus hours screen edits times and names the rules', (
    tester,
  ) async {
    List<ScheduleWindow>? result;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              opened = true;
              result = await showDialog<List<ScheduleWindow>>(
                context: context,
                builder: (_) => const FocusHoursDialog(
                  windows: [],
                  timezone: 'Asia/Jakarta',
                  focusRules: ['Games', 'Social media'],
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
    expect(find.text('Blocks Games and Social media.'), findsOneWidget);
    expect(find.text('Add more times'), findsNothing);
    await tester.tap(find.text('Use Focus hours'));
    await tester.pumpAndSettle();
    expect(find.text('Times use Asia/Jakarta.'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(result!.single.toJson(), weekdays.toJson());

    // Turning it off saves no times.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
  });
}
