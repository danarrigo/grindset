import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_profile.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  late LocalStore store;
  late AppController c;
  final at = DateTime.utc(2026, 11, 16, 12);
  setUp(() async {
    store = LocalStore.memory();
    c = AppController(store: store, tracker: NativeTracker(), clock: () => at);
    await c.initialize(poll: false);
    await c.saveRule(
      ActivityRule(
        id: 'social',
        name: 'Social',
        sources: ['windows:discord.exe'],
        focusBlock: false,
        dailyMinutes: 47,
      ),
    );
    await c.saveRule(
      ActivityRule(
        id: 'video',
        name: 'Video',
        sources: ['web:youtube.com'],
        focusBlock: true,
        schedules: [
          ScheduleWindow(weekdays: [1], startMinute: 540, endMinute: 1020),
        ],
      ),
    );
  });
  tearDown(() async {
    c.dispose();
    await store.close();
  });
  test('saving a profile does not apply it or start a timer', () async {
    final before = c.rules.map((r) => r.toJson()).toList();
    await c.saveFocusProfile(
      FocusProfile(id: 'work', name: 'Work', ruleIds: ['social']),
    );
    expect(c.rules.map((r) => r.toJson()).toList(), before);
    expect(c.session, isNull);
    expect(c.selectedFocusProfile, isNull);
    expect((await store.setting('focus_profiles'))!, contains('Work'));
  });
  test('applying changes only local focus flags and preserves budgets, schedules and outbox', () async {
    await c.saveFocusProfile(
      FocusProfile(id: 'work', name: 'Work', ruleIds: ['social']),
    );
    final before = c.rules.map((r) => r.toJson()).toList();
    final queued = await store
        .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
        .getSingle();
    await c.applyFocusProfile('work');
    expect(c.rules.map((r) => r.toJson()).toList(), [
      {...before[0], 'focus_block': true},
      {...before[1], 'focus_block': false},
    ]);
    expect(c.restrictionForSource('web:youtube.com'), 'Scheduled restriction');
    expect(c.session, isNull);
    expect(c.selectedFocusProfile?.name, 'Work');
    expect(
      (await store
              .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
              .getSingle())
          .read<int>('n'),
      queued.read<int>('n'),
    );
    await c.startSession(const Duration(minutes: 25), SessionPhase.focus);
    expect(c.session!.label, 'Work');
  });
  test('profiles and selection survive restart without overwriting later manual choices', () async {
    await c.saveFocusProfile(
      FocusProfile(id: 'study', name: 'Study', ruleIds: ['social']),
    );
    await c.applyFocusProfile('study');
    c.dispose();
    c = AppController(store: store, tracker: NativeTracker(), clock: () => at);
    await c.initialize(poll: false);
    expect(c.selectedFocusProfile?.name, 'Study');
    final rule = c.rules.first;
    await c.saveRule(
      ActivityRule.fromJson({...rule.toJson(), 'focus_block': false}),
    );
    expect(c.selectedFocusProfile, isNull);
  });
  test('a profile with a deleted activity cannot silently clear blocking selection', () async {
    await c.saveFocusProfile(
      FocusProfile(id: 'sleep', name: 'Sleep', ruleIds: ['social']),
    );
    await c.deleteRule('social');
    final before = c.rules.map((r) => r.toJson()).toList();
    await expectLater(c.applyFocusProfile('sleep'), throwsStateError);
    expect(c.rules.map((r) => r.toJson()).toList(), before);
  });
  test(
    'switching a profile during focus preserves the existing timer deadline',
    () async {
      await c.saveFocusProfile(
        FocusProfile(id: 'work', name: 'Work', ruleIds: ['social']),
      );
      await c.startSession(const Duration(minutes: 25), SessionPhase.focus);
      final before = c.session!.toJson();
      await c.applyFocusProfile('work');
      expect(c.session!.toJson(), before);
      expect(c.preferredMinutes(SessionPhase.focus), 25);
    },
  );

  test('deleting an applied profile does not unblock its activities', () async {
    await c.saveFocusProfile(
      FocusProfile(id: 'work', name: 'Work', ruleIds: ['social']),
    );
    await c.applyFocusProfile('work');
    final before = c.rules.map((r) => r.toJson()).toList();
    await c.deleteFocusProfile('work');
    expect(c.rules.map((r) => r.toJson()).toList(), before);
    expect(c.selectedFocusProfile, isNull);
  });
  test(
    'profiles require activities and reject ambiguous duplicate names',
    () async {
      expect(
        () => FocusProfile(id: 'empty', name: 'Work', ruleIds: []),
        throwsArgumentError,
      );
      await c.saveFocusProfile(
        FocusProfile(id: 'a', name: 'Work', ruleIds: ['social']),
      );
      await expectLater(
        c.saveFocusProfile(
          FocusProfile(id: 'b', name: 'work', ruleIds: ['video']),
        ),
        throwsStateError,
      );
    },
  );
}
