import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test(
    'an overnight Monday schedule also blocks early Tuesday, not Wednesday',
    () {
      final schedule = ScheduleWindow(
        weekdays: [1],
        startMinute: 22 * 60,
        endMinute: 2 * 60,
      );
      final utc = tz.UTC;
      expect(schedule.contains(DateTime.utc(2026, 11, 9, 23), utc), isTrue);
      expect(schedule.contains(DateTime.utc(2026, 11, 10, 1), utc), isTrue);
      expect(schedule.contains(DateTime.utc(2026, 11, 10, 2), utc), isFalse);
      expect(schedule.contains(DateTime.utc(2026, 11, 11, 1), utc), isFalse);
    },
  );
  test('scheduled hours enforce without a timer, respect timezone and leave gaps between windows', () {
    final zone = tz.getLocation('Asia/Jakarta');
    final rule = ActivityRule(
      id: 'work',
      name: 'Focus hours',
      sources: ['windows:discord.exe'],
      focusBlock: false,
      schedules: [
        ScheduleWindow(
          weekdays: [1, 2, 3, 4, 5],
          startMinute: 540,
          endMinute: 720,
        ),
        ScheduleWindow(
          weekdays: [1, 2, 3, 4, 5],
          startMinute: 780,
          endMinute: 1020,
        ),
      ],
    );
    String? reason(int hour, int minute) => blockingReason(
      rule: rule,
      now: DateTime.utc(2026, 11, 9, hour, minute),
      location: zone,
      intervals: [],
      focusing: false,
    );
    expect(reason(1, 59), isNull);
    expect(reason(2, 0), 'Scheduled restriction');
    expect(reason(5, 0), isNull);
    expect(reason(6, 0), 'Scheduled restriction');
    expect(reason(10, 0), isNull);
    expect(
      ActivityRule.fromJson(rule.toJson()).schedules.map((w) => w.toJson()),
      rule.schedules.map((w) => w.toJson()),
    );
  });
  test('account days follow daylight saving, not a fixed 24 hours', () {
    final zone = tz.getLocation('America/New_York');
    final (springStart, springEnd) = accountDay(
      DateTime.utc(2026, 3, 8, 12),
      zone,
    );
    final (fallStart, fallEnd) = accountDay(
      DateTime.utc(2026, 11, 1, 12),
      zone,
    );
    expect(springEnd.difference(springStart), const Duration(hours: 23));
    expect(fallEnd.difference(fallStart), const Duration(hours: 25));
  });
  test('a break does not lift a daily restriction', () {
    final now = DateTime.utc(2026, 11, 10, 10);
    final rule = ActivityRule(
      id: 'yt',
      name: 'YouTube',
      sources: ['android:youtube'],
      dailyMinutes: 10,
    );
    final intervals = [
      UsageInterval(
        id: 'a',
        deviceId: 'phone',
        source: 'android:youtube',
        start: now.subtract(const Duration(minutes: 10)),
        end: now,
      ),
    ];
    expect(
      blockingReason(
        rule: rule,
        now: now,
        location: tz.UTC,
        intervals: intervals,
        focusing: false,
      ),
      'Daily budget reached',
    );
  });
  test(
    'usage is clipped at account midnight and at the last confirmed endpoint',
    () {
      final midnight = DateTime.utc(2026, 11, 10);
      final interval = UsageInterval(
        id: 'a',
        deviceId: 'pc',
        source: 'app',
        start: midnight.subtract(const Duration(minutes: 10)),
        end: midnight.add(const Duration(minutes: 5)),
      );
      expect(
        combinedUsage(
          [interval],
          from: midnight,
          until: midnight.add(const Duration(hours: 12)),
        ),
        const Duration(minutes: 5),
      );
      expect(combinedUsage([interval, interval]), const Duration(minutes: 15));
    },
  );
  test('a restored timer uses its deadline, not the number of UI ticks', () {
    final start = DateTime.utc(2026, 11, 10, 10);
    final original = FocusSession(
      id: 'focus',
      phase: SessionPhase.focus,
      start: start,
      end: start.add(const Duration(minutes: 25)),
    );
    final restored = FocusSession.fromJson(original.toJson());
    expect(
      restored.remaining(start.add(const Duration(minutes: 20))),
      const Duration(minutes: 5),
    );
    expect(
      restored.remaining(start.add(const Duration(hours: 1))),
      Duration.zero,
    );
    expect(restored.focusing(start.add(const Duration(minutes: 25))), isFalse);
  });
}
