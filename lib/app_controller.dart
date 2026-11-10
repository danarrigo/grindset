import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import 'core/activity.dart';
import 'core/focus_session.dart';
import 'data/local_store.dart';
import 'platform/native_tracker.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.tracker,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final LocalStore store;
  final NativeTracker tracker;
  final DateTime Function() _clock;
  final _uuid = const Uuid();
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;
  int _ticks = 0;
  DateTime? _previousObservation;
  ({String id, String source, DateTime start})? _openInterval;
  final Map<String, DateTime> _overrides = {};
  DateTime get now => _clock().toUtc();
  String deviceId = '';
  String timezone = 'UTC';
  tz.Location get location => tz.getLocation(timezone);
  List<UsageInterval> usage = [];
  List<ActivityRule> rules = [];
  FocusSession? session;
  List<FocusSession> history = [];
  int _focusMinutes = 25;
  int _breakMinutes = 5;
  int preferredMinutes(SessionPhase phase) =>
      phase == SessionPhase.focus ? _focusMinutes : _breakMinutes;
  bool trackingEnabled = false;
  bool accessGranted = false;
  String? trackingError;
  String? blockedSource;
  String? blockMessage;
  Future<void> Function()? showBlock;

  Future<void> initialize({
    String initialTimezone = 'UTC',
    bool poll = true,
  }) async {
    deviceId = await store.setting('device_id') ?? _uuid.v4();
    await store.saveSetting('device_id', deviceId);
    timezone = await store.setting('timezone') ?? initialTimezone;
    tz.getLocation(
      timezone,
    ); // Invalid persisted zones must not silently reset days.
    await store.saveSetting('timezone', timezone);
    trackingEnabled = await store.setting('tracking_enabled') == 'true';
    _focusMinutes =
        (int.tryParse(await store.setting('preset_focus') ?? '') ?? 25).clamp(
          1,
          1440,
        );
    _breakMinutes =
        (int.tryParse(await store.setting('preset_rest') ?? '') ?? 5).clamp(
          1,
          1440,
        );
    rules = await store.rules();
    final active = await store.setting('active_session');
    if (active != null) {
      session = FocusSession.fromJson(
        jsonDecode(active) as Map<String, dynamic>,
      );
    }
    final rows = await store.customSelect('SELECT value FROM sessions').get();
    history = rows
        .map(
          (r) => FocusSession.fromJson(
            jsonDecode(r.read<String>('value')) as Map<String, dynamic>,
          ),
        )
        .toList();
    final overrides = await store.setting('overrides');
    if (overrides != null) {
      (jsonDecode(overrides) as Map<String, dynamic>).forEach((key, value) {
        final until = DateTime.parse(value as String);
        if (until.isAfter(now)) _overrides[key] = until;
      });
    }
    await reloadUsage();
    if (poll) {
      await refresh();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> reloadUsage() async {
    final (start, _) = accountDay(now, location);
    usage = await store.usage(from: start);
    _changed();
  }

  Duration deviceUsage(String id) => combinedUsage(
    usage.where((i) => i.deviceId == id),
    from: accountDay(now, location).$1,
    until: now,
  );
  Duration ruleUsage(ActivityRule rule) => combinedUsage(
    usage.where((i) => rule.sources.contains(i.source)),
    from: accountDay(now, location).$1,
    until: now,
  );
  Duration get focusedToday {
    final start = accountDay(now, location).$1;
    return combinedUsage(
      history
          .where(
            (s) =>
                s.phase == SessionPhase.focus &&
                s.start.isBefore(now) &&
                s.end.isAfter(start),
          )
          .map(
            (s) => UsageInterval(
              id: s.id,
              deviceId: deviceId,
              source: 'focus',
              start: s.start,
              end: s.end.isAfter(now) ? now : s.end,
            ),
          ),
      from: start,
      until: now,
    );
  }

  Future<void> startSession(Duration duration, SessionPhase phase) async {
    if (duration <= Duration.zero || duration > const Duration(days: 1)) {
      throw ArgumentError('Choose a duration between one second and 24 hours.');
    }
    if (session?.running(now) ?? false) {
      throw StateError('End the active session first.');
    }
    final started = now;
    final next = FocusSession(
      id: _uuid.v4(),
      phase: phase,
      start: started,
      end: started.add(duration),
      label: phase == SessionPhase.focus ? 'Deep work' : 'Take a breath',
    );
    await _saveSession(next, presetMinutes: duration.inMinutes.clamp(1, 1440));
  }

  Future<void> endSession() async {
    final active = session;
    if (active == null) return;
    // An immediate stop must still produce a positive, valid interval.
    if (!now.isAfter(active.start)) return;
    await _saveSession(active.finish(now));
  }

  Future<void> _saveSession(FocusSession next, {int? presetMinutes}) async {
    await store.transaction(() async {
      if (presetMinutes != null) {
        await store.saveSetting('preset_${next.phase.name}', '$presetMinutes');
      }
      await store.saveSetting('active_session', jsonEncode(next.toJson()));
      await store.customStatement(
        'INSERT INTO sessions(id,value) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value',
        [next.id, jsonEncode(next.toJson())],
      );
    });
    if (presetMinutes != null) {
      if (next.phase == SessionPhase.focus) {
        _focusMinutes = presetMinutes;
      } else {
        _breakMinutes = presetMinutes;
      }
    }
    session = next;
    history = [...history.where((s) => s.id != next.id), next];
    _changed();
  }

  Future<void> saveRule(ActivityRule rule) async {
    final next = [...rules.where((r) => r.id != rule.id), rule];
    await store.saveRules(next);
    rules = next;
    _changed();
  }

  Future<void> deleteRule(String id) async {
    final next = rules.where((r) => r.id != id).toList();
    await store.saveRules(next);
    rules = next;
    _changed();
  }

  Future<void> setTimezone(String value) async {
    tz.getLocation(value);
    await store.saveSetting('timezone', value);
    timezone = value;
    await reloadUsage();
  }

  Future<void> enableTracking() async {
    if (!tracker.supported) {
      throw StateError('Native tracking requires Windows or Android.');
    }
    await store.saveSetting('tracking_enabled', 'true');
    trackingEnabled = true;
    await tracker.requestAccess();
    await refresh();
  }

  Future<void> overrideBlock() async {
    final source = blockedSource;
    if (source == null) return;
    final until = now.add(const Duration(minutes: 5));
    final next = {..._overrides, source: until};
    await store.saveSetting(
      'overrides',
      jsonEncode(next.map((k, v) => MapEntry(k, v.toIso8601String()))),
    );
    _overrides[source] = until;
    dismissBlock();
  }

  void dismissBlock() {
    blockedSource = null;
    blockMessage = null;
    _changed();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      if (trackingEnabled && tracker.supported) {
        accessGranted = await tracker.hasAccess();
        if (!accessGranted) {
          _openInterval = null;
          _previousObservation = null;
        } else if (tracker.isWindows) {
          final current = tracker.foreground();
          final observed = now;
          if (current == null || current.source == 'windows:lockin.exe') {
            _openInterval = null;
          } else {
            final previous = _previousObservation;
            if (_openInterval?.source != current.source ||
                previous == null ||
                observed.difference(previous) > const Duration(seconds: 5)) {
              _openInterval = (
                id: _uuid.v4(),
                source: current.source,
                start: observed,
              );
            } else if (observed.isAfter(_openInterval!.start)) {
              await store.putUsage(
                UsageInterval(
                  id: _openInterval!.id,
                  deviceId: deviceId,
                  source: current.source,
                  start: _openInterval!.start,
                  end: observed,
                ),
              );
            }
            _checkBlock(current.source);
          }
          _previousObservation = observed;
        } else if (_ticks % 15 == 0) {
          final intervals = await tracker.androidHistory(
            deviceId,
            accountDay(now, location).$1,
            now,
          );
          await store.transaction(() async {
            for (final interval in intervals) {
              await store.putUsage(interval);
            }
          });
        }
      }
      if (_ticks++ % 5 == 0) await reloadUsage();
      trackingError = null;
    } catch (error) {
      trackingError = 'Tracking interrupted: $error';
      _openInterval = null;
      _previousObservation = null;
    } finally {
      _refreshing = false;
      _changed();
    }
  }

  void _checkBlock(String source) {
    String? reason;
    for (final rule in rules.where((r) => r.sources.contains(source))) {
      reason = blockingReason(
        rule: rule,
        now: now,
        location: location,
        intervals: usage,
        focusing: session?.focusing(now) ?? false,
        overrideUntil: _overrides[source],
      );
      if (reason != null) break;
    }
    if (reason == null) {
      dismissBlock();
      return;
    }
    final changed = blockedSource != source;
    blockedSource = source;
    blockMessage = reason;
    if (changed && showBlock != null) {
      unawaited(
        showBlock!().catchError((Object error) {
          trackingError = 'Could not show blocking screen: $error';
          _changed();
        }),
      );
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
