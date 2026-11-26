import 'package:timezone/timezone.dart' as tz;

import 'activity.dart';

class BudgetWarning {
  const BudgetWarning({
    required this.ruleId,
    required this.name,
    required this.used,
    required this.limit,
  });
  final String ruleId;
  final String name;
  final Duration used;
  final Duration limit;
  Duration get remaining => limit - used;
  String get message {
    final minutes = (remaining.inSeconds / 60).ceil();
    final left = remaining < const Duration(minutes: 1)
        ? 'less than 1 minute'
        : 'about $minutes minute${minutes == 1 ? '' : 's'}';
    return '$name: $left left in the daily budget (at least 80% used). Based on recorded usage.';
  }
}

List<BudgetWarning> nearBudgetWarnings({
  required Iterable<ActivityRule> rules,
  required Iterable<UsageInterval> intervals,
  required DateTime now,
  required tz.Location location,
}) {
  final (start, _) = accountDay(now, location);
  return [
    for (final rule in rules)
      if (rule.dailyMinutes != null)
        ..._warning(
          rule,
          combinedUsage(usageOf(rule, intervals), from: start, until: now),
        ),
  ];
}

List<BudgetWarning> _warning(ActivityRule rule, Duration used) {
  final limit = Duration(minutes: rule.dailyMinutes!);
  if (used >= limit || used.inMicroseconds * 100 < limit.inMicroseconds * 80) {
    return [];
  }
  return [
    BudgetWarning(ruleId: rule.id, name: rule.name, used: used, limit: limit),
  ];
}
