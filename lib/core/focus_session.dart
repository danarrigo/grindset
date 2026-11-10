enum SessionPhase { focus, rest }

class FocusSession {
  FocusSession({
    required this.id,
    required this.phase,
    required DateTime start,
    required DateTime end,
    this.label = 'Deep work',
  }) : start = start.toUtc(),
       end = end.toUtc() {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError('Invalid session duration');
    }
  }
  final String id;
  final SessionPhase phase;
  final DateTime start;
  final DateTime end;
  final String label;

  Duration remaining(DateTime now) =>
      now.isBefore(end) ? end.difference(now) : Duration.zero;
  bool running(DateTime now) => !now.isBefore(start) && now.isBefore(end);
  bool focusing(DateTime now) => phase == SessionPhase.focus && running(now);

  FocusSession finish(DateTime now) => FocusSession(
    id: id,
    phase: phase,
    start: start,
    label: label,
    end: now.isBefore(end) && now.isAfter(start) ? now : end,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'phase': phase.name,
    'started_at': start.toIso8601String(),
    'ended_at': end.toIso8601String(),
    'label': label,
  };
  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
    id: json['id'] as String,
    phase: SessionPhase.values.byName(json['phase'] as String),
    start: DateTime.parse(json['started_at'] as String),
    end: DateTime.parse(json['ended_at'] as String),
    label: json['label'] as String,
  );
}
