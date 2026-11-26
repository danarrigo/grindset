import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

final _hostLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');

/// Host identifiers only. URL paths, queries and fragments are never accepted.
String? websiteHost(String value) {
  var host = value.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.startsWith('www.')) host = host.substring(4);
  if (host.isEmpty || host.length > 253) return null;
  return host.split('.').every(_hostLabel.hasMatch) ? host : null;
}

/// Answers by rule source, then observed source. Both come from small sets
/// (rule and catalog sources, apps and sites seen), so this stays small.
final _matches = <String, Map<String, bool>>{};
var _matchCount = 0;

/// Whether a rule's source covers an observed one. Asked for every rule,
/// source and usage record on each refresh, so answers are remembered.
bool matchesSource(String ruleSource, String observedSource) {
  final known = _matches[ruleSource]?[observedSource];
  if (known != null) return known;
  if (++_matchCount > 100000) {
    _matches.clear();
    _matchCount = 1;
  }
  return (_matches[ruleSource] ??= {})[observedSource] = _matchesSource(
    ruleSource,
    observedSource,
  );
}

bool _matchesSource(String ruleSource, String observedSource) {
  if (ruleSource.startsWith('windows:') &&
      observedSource.startsWith('windows:')) {
    return ruleSource.toLowerCase() == observedSource.toLowerCase();
  }
  if (!ruleSource.startsWith('web:') || !observedSource.startsWith('web:')) {
    return ruleSource == observedSource;
  }
  final rule = websiteHost(ruleSource.substring(4));
  final observed = websiteHost(observedSource.substring(4));
  return rule != null &&
      observed != null &&
      (observed == rule || observed.endsWith('.$rule'));
}

class UsageInterval {
  UsageInterval({
    required this.id,
    required this.deviceId,
    required this.source,
    required DateTime start,
    required DateTime end,
  }) : start = start.toUtc(),
       end = end.toUtc() {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError('A usage interval must have positive duration.');
    }
  }

  final String id;
  final String deviceId;
  final String source;
  final DateTime start;
  // A confirmed observation, never an estimate of an offline device's activity.
  final DateTime end;

  Map<String, Object> toJson() => {
    'id': id,
    'device_id': deviceId,
    'source': source,
    'started_at': start.toIso8601String(),
    'ended_at': end.toIso8601String(),
  };

  factory UsageInterval.fromJson(Map<String, dynamic> json) => UsageInterval(
    id: json['id'] as String,
    deviceId: json['device_id'] as String,
    source: json['source'] as String,
    start: DateTime.parse(json['started_at'] as String),
    end: DateTime.parse(json['ended_at'] as String),
  );
}

/// Elapsed usage, not the sum of overlapping device durations.
Duration combinedUsage(
  Iterable<UsageInterval> intervals, {
  DateTime? from,
  DateTime? until,
}) {
  final spans = <(DateTime, DateTime)>[];
  for (final interval in intervals) {
    final start = from != null && interval.start.isBefore(from)
        ? from
        : interval.start;
    final end = until != null && interval.end.isAfter(until)
        ? until
        : interval.end;
    if (end.isAfter(start)) spans.add((start, end));
  }
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  DateTime? start;
  DateTime? end;
  var elapsed = Duration.zero;
  for (final span in spans) {
    if (end == null || span.$1.isAfter(end)) {
      if (start != null && end != null) elapsed += end.difference(start);
      start = span.$1;
      end = span.$2;
    } else if (span.$2.isAfter(end)) {
      end = span.$2;
    }
  }
  if (start != null && end != null) elapsed += end.difference(start);
  return elapsed;
}

(DateTime, DateTime) accountDay(DateTime instant, tz.Location location) {
  final local = tz.TZDateTime.from(instant, location);
  return (
    tz.TZDateTime(location, local.year, local.month, local.day).toUtc(),
    tz.TZDateTime(location, local.year, local.month, local.day + 1).toUtc(),
  );
}

class ScheduleWindow {
  ScheduleWindow({
    required Iterable<int> weekdays,
    required this.startMinute,
    required this.endMinute,
  }) : weekdays = Set.unmodifiable(weekdays) {
    if (this.weekdays.isEmpty ||
        this.weekdays.any((d) => d < 1 || d > 7) ||
        startMinute < 0 ||
        startMinute >= 1440 ||
        endMinute < 0 ||
        endMinute >= 1440 ||
        startMinute == endMinute) {
      throw ArgumentError('Choose weekdays and different start/end times.');
    }
  }
  final Set<int> weekdays;
  final int startMinute;
  final int endMinute;

  bool contains(DateTime instant, tz.Location location) {
    final time = tz.TZDateTime.from(instant, location);
    final minute = time.hour * 60 + time.minute;
    if (startMinute < endMinute) {
      return weekdays.contains(time.weekday) &&
          minute >= startMinute &&
          minute < endMinute;
    }
    // After midnight belongs to the weekday on which the window started.
    final previousDay = time.weekday == 1 ? 7 : time.weekday - 1;
    return (minute >= startMinute && weekdays.contains(time.weekday)) ||
        (minute < endMinute && weekdays.contains(previousDay));
  }

  Map<String, Object> toJson() => {
    'weekdays': weekdays.toList(),
    'start_minute': startMinute,
    'end_minute': endMinute,
  };
  factory ScheduleWindow.fromJson(Map<String, dynamic> json) => ScheduleWindow(
    weekdays: (json['weekdays'] as List).cast<int>(),
    startMinute: json['start_minute'] as int,
    endMinute: json['end_minute'] as int,
  );
}

class ActivityRule {
  ActivityRule({
    required this.id,
    required this.name,
    required Iterable<String> sources,
    this.focusBlock = true,
    this.dailyMinutes,
    Iterable<ScheduleWindow> schedules = const [],
  }) : sources = Set.unmodifiable(sources),
       schedules = List.unmodifiable(schedules) {
    if (name.trim().isEmpty ||
        this.sources.isEmpty ||
        (dailyMinutes != null && dailyMinutes! <= 0)) {
      throw ArgumentError(
        'An activity needs a name, sources, and positive limit.',
      );
    }
  }
  final String id;
  final String name;
  final Set<String> sources;
  final bool focusBlock;
  final int? dailyMinutes;
  final List<ScheduleWindow> schedules;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sources': sources.toList(),
    'focus_block': focusBlock,
    'daily_minutes': dailyMinutes,
    'schedules': schedules.map((s) => s.toJson()).toList(),
  };
  factory ActivityRule.fromJson(Map<String, dynamic> json) => ActivityRule(
    id: json['id'] as String,
    name: json['name'] as String,
    sources: (json['sources'] as List).cast<String>(),
    focusBlock: json['focus_block'] as bool,
    dailyMinutes: json['daily_minutes'] as int?,
    schedules: (json['schedules'] as List).map(
      (s) => ScheduleWindow.fromJson(Map<String, dynamic>.from(s as Map)),
    ),
  );
  String encode() => jsonEncode(toJson());
}

/// The records [rule] covers. A day has thousands of records but few apps
/// and sites, so each source is checked against the rule once.
Iterable<UsageInterval> usageOf(
  ActivityRule rule,
  Iterable<UsageInterval> intervals,
) {
  final covered = <String, bool>{};
  return intervals.where(
    (i) => covered[i.source] ??= rule.sources.any(
      (source) => matchesSource(source, i.source),
    ),
  );
}

/// Call for each rule matching the foreground source. No rule lifts another.
String? blockingReason({
  required ActivityRule rule,
  required DateTime now,
  required tz.Location location,
  required Iterable<UsageInterval> intervals,
  bool focusing = false,
  bool focusHours = false,
}) {
  if (rule.schedules.any((s) => s.contains(now, location))) {
    return 'Scheduled restriction';
  }
  if (rule.dailyMinutes != null) {
    final (start, end) = accountDay(now, location);
    final used = combinedUsage(
      usageOf(rule, intervals),
      from: start,
      until: now.isBefore(end) ? now : end,
    );
    if (used >= Duration(minutes: rule.dailyMinutes!)) {
      return 'Daily budget reached';
    }
  }
  if (focusing && rule.focusBlock) return 'Focus session in progress';
  if (focusHours && rule.focusBlock) return 'Focus hours';
  return null;
}

/// Focus hours as stored: a JSON list of schedule windows.
List<ScheduleWindow> decodeFocusHours(String json) => List.unmodifiable([
  for (final window in jsonDecode(json) as List)
    ScheduleWindow.fromJson(Map<String, dynamic>.from(window as Map)),
]);

/// Whether [next] blocks at least everything [old] does: no app removed, no
/// higher daily limit, focus blocking and every scheduled time kept.
bool isStricter(ActivityRule old, ActivityRule next) =>
    old.sources.every(next.sources.contains) &&
    (!old.focusBlock || next.focusBlock) &&
    (old.dailyMinutes == null ||
        (next.dailyMinutes != null &&
            next.dailyMinutes! <= old.dailyMinutes!)) &&
    coversWindows(next.schedules, old.schedules);

/// Whether [next] still blocks every time [old] did.
bool coversWindows(
  Iterable<ScheduleWindow> next,
  Iterable<ScheduleWindow> old,
) => old.every(
  (window) => next.any(
    (w) =>
        w.startMinute == window.startMinute &&
        w.endMinute == window.endMinute &&
        w.weekdays.containsAll(window.weekdays),
  ),
);
