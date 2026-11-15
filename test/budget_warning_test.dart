import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/budget_warning.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/completion_alerts.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _Alerts extends CompletionAlerts {
  _Alerts() : super(android: false);
  int warnings = 0;
  bool? requestedExact;
  bool fail = false;
  @override
  Future<void> requestPermission({bool exactAlarm = true}) async {
    requestedExact = exactAlarm;
  }

  @override
  Future<String?> synchronize({
    required bool enabled,
    FocusSession? session,
  }) async => null;
  @override
  Future<String?> showBudgetWarnings(
    List<BudgetWarning> events, {
    bool Function()? enabled,
  }) async {
    if (enabled?.call() == false) return null;
    warnings++;
    if (fail) throw StateError('OS unavailable');
    return null;
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final now = DateTime.utc(2026, 11, 16, 12);
  final rule = ActivityRule(
    id: 'social',
    name: 'Social',
    sources: ['windows:discord.exe', 'web:example.com'],
    dailyMinutes: 50,
  );
  UsageInterval row(
    String id,
    DateTime at,
    int minutes, {
    String source = 'windows:discord.exe',
  }) => UsageInterval(
    id: id,
    deviceId: id,
    source: source,
    start: at.subtract(Duration(minutes: minutes)),
    end: at,
  );
  test('80 percent is inclusive; below it and an already reached limit do not warn', () {
    List<BudgetWarning> check(int minutes) => nearBudgetWarnings(
      rules: [rule],
      intervals: [row('a', now, minutes)],
      now: now,
      location: tz.UTC,
    );
    expect(check(39), isEmpty);
    expect(check(40).single.remaining, const Duration(minutes: 10));
    expect(check(49).single.message, contains('about 1 minute left'));
    expect(check(50), isEmpty);
  });
  test(
    'shared app/site overlap is unioned and previous account days are excluded',
    () {
      final warnings = nearBudgetWarnings(
        rules: [rule],
        intervals: [
          row('pc', now, 25),
          row('phone', now, 25, source: 'web:example.com'),
          row('old', now.subtract(const Duration(days: 1)), 45),
        ],
        now: now,
        location: tz.UTC,
      );
      expect(warnings, isEmpty);
    },
  );
  test('budget-day clipping follows the named account timezone', () {
    final at = DateTime.utc(2026, 11, 16, 0, 30);
    final warnings = nearBudgetWarnings(
      rules: [rule],
      intervals: [
        UsageInterval(
          id: 'midnight',
          deviceId: 'pc',
          source: 'windows:discord.exe',
          start: DateTime.utc(2026, 11, 15, 16, 50),
          end: DateTime.utc(2026, 11, 15, 17, 10),
        ),
        row('recent', at, 30),
      ],
      now: at,
      location: tz.getLocation('Asia/Jakarta'),
    );
    expect(warnings.single.used, const Duration(minutes: 40));
  });

  test('opt-in, persisted daily deduplication and no changes to budgets or tracking', () async {
    final store = LocalStore.memory();
    final alerts = _Alerts();
    var clock = now;
    var c = AppController(
      store: store,
      tracker: NativeTracker(),
      completionAlerts: alerts,
      clock: () => clock,
    );
    await c.initialize(poll: false);
    await c.saveRule(rule);
    await store.putUsage(row('today', clock, 40));
    await c.reloadUsage();
    expect(c.budgetWarnings, isEmpty);
    expect(alerts.warnings, 0);
    await c.setBudgetWarningsEnabled(true);
    expect(c.trackingEnabled, isFalse);
    expect(alerts.warnings, 0);
    expect(alerts.requestedExact, isFalse);
    c.trackingEnabled = true;
    await store.saveSetting('tracking_enabled', 'true');
    await c.refresh();
    await c.refresh();
    expect(alerts.warnings, 1);
    expect(c.rules.single.dailyMinutes, 50);
    c.dispose();
    c = AppController(
      store: store,
      tracker: NativeTracker(),
      completionAlerts: alerts,
      clock: () => clock,
    );
    await c.initialize(poll: false);
    await c.refresh();
    expect(alerts.warnings, 1);
    clock = clock.add(const Duration(days: 1));
    await store.putUsage(row('tomorrow', clock, 40));
    await c.reloadUsage();
    await c.refresh();
    expect(alerts.warnings, 2);
    await c.setBudgetWarningsEnabled(false);
    expect(c.budgetWarnings, isEmpty);
    c.dispose();
    await store.close();
  });
  test(
    'notification failure preserves on-screen warning without retry spam',
    () async {
      final store = LocalStore.memory();
      final alerts = _Alerts()..fail = true;
      await store.saveSetting('tracking_enabled', 'true');
      final c = AppController(
        store: store,
        tracker: NativeTracker(),
        completionAlerts: alerts,
        clock: () => now,
      );
      await c.initialize(poll: false);
      await c.saveRule(rule);
      await store.putUsage(row('near', now, 40));
      await c.setBudgetWarningsEnabled(true);
      await c.refresh();
      expect(c.budgetWarnings, hasLength(1));
      expect(c.budgetWarningsNotice, contains('on-screen warnings remain'));
      expect(alerts.warnings, 1);
      c.dispose();
      await store.close();
    },
  );
}
