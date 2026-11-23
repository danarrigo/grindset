import 'package:timezone/timezone.dart' as tz;

import 'activity.dart';

class RecordedDay {
  const RecordedDay({
    required this.date,
    required this.usage,
    required this.hasRecords,
    required this.budgetsReached,
    required this.budgetOverruns,
  });
  final tz.TZDateTime date;
  final Duration usage;
  final bool hasRecords;
  final List<String> budgetsReached;
  final List<({String name, Duration excess})> budgetOverruns;
}

/// A projection of confirmed intervals, never an estimate of unobserved time.
/// One device's, or every device's with overlapping time counted once when
/// [deviceId] is null.
class WeeklyInsights {
  WeeklyInsights({
    required Iterable<UsageInterval> intervals,
    required Iterable<ActivityRule> rules,
    required String? deviceId,
    required DateTime now,
    required tz.Location location,
  }) {
    final local = tz.TZDateTime.from(now, location);
    final start = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day - 6,
    ).toUtc();
    final recorded = intervals
        .where(
          (i) =>
              (deviceId == null || i.deviceId == deviceId) &&
              i.end.isAfter(start) &&
              i.start.isBefore(now),
        )
        .toList();
    days = [
      for (var index = 0; index < 7; index++)
        _day(
          tz.TZDateTime(
            location,
            local.year,
            local.month,
            local.day - 6 + index,
          ),
          recorded,
          rules,
          now,
        ),
    ];
    total = combinedUsage(recorded, from: start, until: now);
    matched = combinedUsage(
      recorded.where(
        (i) => rules.any(
          (rule) => rule.sources.any((s) => matchesSource(s, i.source)),
        ),
      ),
      from: start,
      until: now,
    );
    topSources = [
      for (final source in recorded.map((i) => i.source).toSet())
        (
          source: source,
          duration: combinedUsage(
            recorded.where((i) => i.source == source),
            from: start,
            until: now,
          ),
        ),
    ]..sort((a, b) => b.duration.compareTo(a.duration));
  }
  late final List<RecordedDay> days;
  late final Duration total;
  late final Duration matched;
  late final List<({String source, Duration duration})> topSources;
  int get recordedDays => days.where((day) => day.hasRecords).length;
  int get budgetDays =>
      days.where((day) => day.budgetsReached.isNotEmpty).length;

  static RecordedDay _day(
    tz.TZDateTime date,
    List<UsageInterval> recorded,
    Iterable<ActivityRule> rules,
    DateTime now,
  ) {
    final start = date.toUtc();
    final next = tz.TZDateTime(
      date.location,
      date.year,
      date.month,
      date.day + 1,
    ).toUtc();
    final until = next.isBefore(now) ? next : now;
    final rows = recorded
        .where((i) => i.end.isAfter(start) && i.start.isBefore(until))
        .toList();
    final budgets = [
      for (final rule in rules)
        if (rule.dailyMinutes != null)
          (
            name: rule.name,
            limit: Duration(minutes: rule.dailyMinutes!),
            used: combinedUsage(
              rows.where(
                (i) => rule.sources.any((s) => matchesSource(s, i.source)),
              ),
              from: start,
              until: until,
            ),
          ),
    ];
    return RecordedDay(
      date: date,
      usage: combinedUsage(rows, from: start, until: until),
      hasRecords: rows.isNotEmpty,
      budgetsReached: [
        for (final budget in budgets)
          if (budget.used >= budget.limit) budget.name,
      ],
      budgetOverruns: [
        for (final budget in budgets)
          if (budget.used > budget.limit)
            (name: budget.name, excess: budget.used - budget.limit),
      ],
    );
  }
}
