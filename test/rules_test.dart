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
  test('a break does not lift a daily restriction; override expires at its deadline', () {
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
    String? reason({DateTime? override}) => blockingReason(
      rule: rule,
      now: now,
      location: tz.UTC,
      intervals: intervals,
      focusing: false,
      overrideUntil: override,
    );
    expect(reason(), 'Daily budget reached');
    expect(reason(override: now.add(const Duration(seconds: 1))), isNull);
    expect(reason(override: now), 'Daily budget reached');
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
