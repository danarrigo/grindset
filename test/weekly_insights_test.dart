import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/weekly_insights.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  UsageInterval row(
    String id,
    DateTime from,
    DateTime to, {
    String source = 'windows:discord.exe',
    String device = 'pc',
  }) => UsageInterval(
    id: id,
    deviceId: device,
    source: source,
    start: from,
    end: to,
  );
  test('weekly totals union overlapping app/site observations and exclude other devices', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final report = WeeklyInsights(
      intervals: [
        row(
          'app',
          DateTime.utc(2026, 11, 16, 11),
          DateTime.utc(2026, 11, 16, 11, 30),
        ),
        row(
          'web',
          DateTime.utc(2026, 11, 16, 11, 15),
          DateTime.utc(2026, 11, 16, 11, 45),
          source: 'web:youtube.com',
        ),
        row(
          'phone',
          now.subtract(const Duration(hours: 2)),
          now,
          device: 'phone',
        ),
      ],
      rules: [
        ActivityRule(
          id: 'social',
          name: 'Social',
          sources: ['windows:discord.exe', 'web:youtube.com'],
          dailyMinutes: 30,
        ),
      ],
      deviceId: 'pc',
      now: now,
      location: tz.UTC,
    );
    expect(report.total, const Duration(minutes: 45));
    expect(report.matched, const Duration(minutes: 45));
    expect(report.recordedDays, 1);
    expect(report.budgetDays, 1);
    expect(report.days.last.budgetsReached, ['Social']);
    expect(report.days.take(6).every((day) => !day.hasRecords), isTrue);
    expect(report.topSources, hasLength(2));
  });
  test('unknown days are not manufactured as observed zeroes', () {
    final report = WeeklyInsights(
      intervals: [],
      rules: [],
      deviceId: 'pc',
      now: DateTime.utc(2026, 11, 16, 12),
      location: tz.UTC,
    );
    expect(report.recordedDays, 0);
    expect(report.days, hasLength(7));
    expect(report.topSources, isEmpty);
  });
  test('intervals crossing the seven-day boundary and future endpoints are clipped', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final report = WeeklyInsights(
      intervals: [
        row(
          'past',
          DateTime.utc(2026, 11, 9, 23, 50),
          DateTime.utc(2026, 11, 10, 0, 10),
        ),
        row(
          'future',
          now.subtract(const Duration(minutes: 10)),
          now.add(const Duration(hours: 2)),
        ),
      ],
      rules: [],
      deviceId: 'pc',
      now: now,
      location: tz.UTC,
    );
    expect(report.total, const Duration(minutes: 20));
    expect(report.recordedDays, 2);
    expect(report.days.first.usage, const Duration(minutes: 10));
    expect(report.days.last.usage, const Duration(minutes: 10));
  });
  test('local days respect daylight-saving duration rather than fixed 24-hour bins', () {
    final zone = tz.getLocation('America/New_York');
    final report = WeeklyInsights(
      intervals: [
        row('spring', DateTime.utc(2026, 3, 8, 5), DateTime.utc(2026, 3, 9, 4)),
      ],
      rules: [],
      deviceId: 'pc',
      now: DateTime.utc(2026, 3, 9, 16),
      location: zone,
    );
    final sunday = report.days.singleWhere((day) => day.date.day == 8);
    expect(sunday.usage, const Duration(hours: 23));
    expect(report.total, const Duration(hours: 23));
  });
  test('budget history is explicitly a projection of current source/limit definitions', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final observations = [
      row('one', now.subtract(const Duration(minutes: 40)), now),
    ];
    WeeklyInsights project(int minutes) => WeeklyInsights(
      intervals: observations,
      rules: [
        ActivityRule(
          id: 'a',
          name: 'A',
          sources: ['windows:Discord.EXE'],
          dailyMinutes: minutes,
        ),
      ],
      deviceId: 'pc',
      now: now,
      location: tz.UTC,
    );
    expect(project(30).budgetDays, 1);
    expect(
      project(30).days.last.budgetOverruns.single.excess,
      const Duration(minutes: 10),
    );
    expect(project(40).days.last.budgetOverruns, isEmpty);
    expect(project(60).budgetDays, 0);
  });

  test('all devices together count time on two devices at once once', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final report = WeeklyInsights(
      intervals: [
        row(
          'pc',
          DateTime.utc(2026, 11, 16, 9),
          DateTime.utc(2026, 11, 16, 10),
        ),
        row(
          'phone',
          DateTime.utc(2026, 11, 16, 9, 30),
          DateTime.utc(2026, 11, 16, 10, 30),
          device: 'phone',
        ),
        row(
          'phone-earlier',
          DateTime.utc(2026, 11, 14, 20),
          DateTime.utc(2026, 11, 14, 20, 15),
          device: 'phone',
        ),
      ],
      rules: const [],
      deviceId: null,
      now: now,
      location: tz.UTC,
    );
    expect(report.total, const Duration(minutes: 105));
    expect(report.recordedDays, 2);
  });
}
