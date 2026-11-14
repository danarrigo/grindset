import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import 'core/activity.dart';
import 'core/focus_session.dart';
import 'data/local_store.dart';
import 'data/shared_state.dart';
import 'platform/native_tracker.dart';
import 'platform/browser_bridge.dart';
import 'platform/completion_alerts.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.tracker,
    this.completionAlerts,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final LocalStore store;
  late final sharedState = SharedState(store, clock: () => now);
  final Map<String, int> _ruleRevisions = {};
  int ruleRevision(String id) => _ruleRevisions[id] ?? 0;
  final NativeTracker tracker;
  final CompletionAlerts? completionAlerts;
  bool completionAlertsEnabled = false;
  String? completionAlertsNotice;
  String? _alertKey;
  int _alertGeneration = 0;
  BrowserBridge? browserBridge;
  ({String id, String source, DateTime start})? _webInterval;
  DateTime? _lastWebObservation;
  final DateTime Function() _clock;
  final _uuid = const Uuid();
  Timer? _timer;
  bool _refreshing = false;
  Completer<void>? _refreshDone;
  bool _resetting = false;
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
  bool backgroundTrackingRunning = false;
  bool androidBlockingEnabled = false;
  DateTime? _lastAndroidImport;
  String? trackingError;
  String? trackingInterruption;
  DateTime? _lastWindowsCheck;
  String? blockedSource;
  String? blockMessage;
  Future<void> Function()? showBlock;
  VoidCallback? onSharedChange;

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
    _lastWindowsCheck = DateTime.tryParse(
      await store.setting('tracking_heartbeat') ?? '',
    );
    final interruption = await store.setting('tracking_interruption');
    trackingInterruption = interruption == null || interruption.isEmpty
        ? null
        : interruption;
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
    _lastAndroidImport = DateTime.tryParse(
      await store.setting('android_imported_until') ?? '',
    );
    if (tracker.isAndroid) {
      tracker.bindAndroidActions(
        onOverride: overrideBlock,
        onDismiss: dismissBlock,
        onStopped: () => disableTracking(notifyNative: false),
      );
      try {
        await _adoptAndroidStatus(
          await tracker.initializeAndroidTracking(trackingEnabled),
        );
      } catch (error) {
        trackingError = 'Android background runtime unavailable: $error';
      }
      showBlock = () async {
        final source = blockedSource;
        if (source != null) {
          await tracker.showAndroidBlock(
            source,
            blockMessage ?? 'An activity rule is active.',
          );
        }
      };
    }
    completionAlertsEnabled =
        await store.setting('completion_alerts_enabled') == 'true';
    await _updateCompletionAlerts();
    await _loadSharedRevisions();
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

  Future<void> _loadSharedRevisions() async {
    final rows = await store
        .customSelect("SELECT id,revision FROM sync_entities WHERE kind='rule'")
        .get();
    _ruleRevisions.clear();
    for (final row in rows) {
      _ruleRevisions[row.read<String>('id')] = row.read<int>('revision');
    }
  }

  Future<void> reloadSharedState() async {
    await store.transaction(() async {
      rules = await store.rules();
      timezone = await store.setting('timezone') ?? timezone;
      tz.getLocation(timezone);
      final active = await store.setting('active_session');
      session = active == null
          ? null
          : FocusSession.fromJson(jsonDecode(active) as Map<String, dynamic>);
      final rows = await store.customSelect('SELECT value FROM sessions').get();
      history = rows
          .map(
            (r) => FocusSession.fromJson(
              jsonDecode(r.read<String>('value')) as Map<String, dynamic>,
            ),
          )
          .toList();
      await _loadSharedRevisions();
    });
    await _updateCompletionAlerts();
    await reloadUsage();
  }

  Future<void> setCompletionAlertsEnabled(bool enabled) async {
    final alerts = completionAlerts;
    if (alerts == null) {
      throw StateError('Completion alerts require Windows or Android.');
    }
    await store.saveSetting('completion_alerts_enabled', '$enabled');
    completionAlertsEnabled = enabled;
    if (enabled) {
      try {
        await alerts.requestPermission();
      } catch (error) {
        completionAlertsNotice =
            'Could not request notification permission: $error';
        _changed();
        return;
      }
    }
    await _updateCompletionAlerts(force: true);
  }

  Future<void> _updateCompletionAlerts({bool force = false}) async {
    final alerts = completionAlerts;
    if (alerts == null) return;
    final key =
        '$completionAlertsEnabled:${session?.id}:${session?.end.microsecondsSinceEpoch}';
    if (!force && key == _alertKey) return;
    _alertKey = key;
    final generation = ++_alertGeneration;
    String? notice;
    try {
      notice = await alerts.synchronize(
        enabled: completionAlertsEnabled,
        session: session,
      );
    } catch (error) {
      notice = 'Completion alerts are unavailable: $error';
      _alertKey = null;
    }
    if (!_disposed && generation == _alertGeneration) {
      completionAlertsNotice = notice;
      _changed();
    }
  }

  Duration deviceUsage(String id) => combinedUsage(
    usage.where((i) => i.deviceId == id),
    from: accountDay(now, location).$1,
    until: now,
  );
  Duration ruleUsage(ActivityRule rule) => combinedUsage(
    usage.where(
      (i) => rule.sources.any((source) => matchesSource(source, i.source)),
    ),
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

  Future<void> setPreferredMinutes(SessionPhase phase, int minutes) async {
    if (minutes < 1 || minutes > 1440) {
      throw ArgumentError('Choose 1 to 1440 minutes.');
    }
    await store.saveSetting('preset_${phase.name}', '$minutes');
    if (phase == SessionPhase.focus) {
      _focusMinutes = minutes;
    } else {
      _breakMinutes = minutes;
    }
    _changed();
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
      await sharedState.queue('focus', 'active', next.toJson());
      await sharedState.queue('session', next.id, next.toJson());
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
    onSharedChange?.call();
    await _updateCompletionAlerts();
  }

  Future<void> saveRule(ActivityRule rule, {int? baseRevision}) async {
    await store.transaction(() async {
      final current = await store.rules();
      final previous = current.where((r) => r.id == rule.id).firstOrNull;
      await store.saveRules([...current.where((r) => r.id != rule.id), rule]);
      await sharedState.rememberFocusFlag(rule);
      if (previous == null ||
          jsonEncode(SharedState.sharedRule(previous)) !=
              jsonEncode(SharedState.sharedRule(rule))) {
        await sharedState.queue(
          'rule',
          rule.id,
          SharedState.sharedRule(rule),
          baseRevision: baseRevision,
        );
      }
    });
    rules = await store.rules();
    _changed();
    onSharedChange?.call();
  }

  Future<void> deleteRule(String id) async {
    await store.transaction(() async {
      await store.saveRules((await store.rules()).where((r) => r.id != id));
      await sharedState.queue('rule', id, null, baseRevision: ruleRevision(id));
    });
    rules = await store.rules();
    _changed();
    onSharedChange?.call();
  }

  Future<void> setTimezone(String value) async {
    tz.getLocation(value);
    await store.transaction(() async {
      await store.saveSetting('timezone', value);
      await sharedState.queue('setting', 'timezone', {'timezone': value});
    });
    timezone = value;
    await reloadUsage();
    onSharedChange?.call();
  }

  Future<void> enableTracking() async {
    if (!tracker.supported) {
      throw StateError('Native tracking requires Windows or Android.');
    }
    if (tracker.isWindows && !trackingEnabled) {
      _lastWindowsCheck = null;
      await store.saveSetting('tracking_heartbeat', '');
    }
    await store.saveSetting('tracking_enabled', 'true');
    trackingEnabled = true;
    if (tracker.isAndroid) {
      await _adoptAndroidStatus(await tracker.setAndroidTracking(true));
    }
    if (!await tracker.hasAccess()) await tracker.requestAccess();
    await refresh();
  }

  Future<void> disableTracking({bool notifyNative = true}) async {
    if (tracker.isAndroid && notifyNative) {
      await tracker.setAndroidTracking(false);
    }
    await store.saveSetting('tracking_enabled', 'false');
    trackingEnabled = false;
    backgroundTrackingRunning = false;
    trackingError = null;
    if (tracker.isWindows) {
      _lastWindowsCheck = null;
      await store.saveSetting('tracking_heartbeat', '');
    }
    _openInterval = null;
    _previousObservation = null;
    _webInterval = null;
    _lastWebObservation = null;
    dismissBlock();
  }

  Future<void> _adoptAndroidStatus(AndroidTrackingStatus status) async {
    if (trackingEnabled != status.enabled) {
      await store.saveSetting('tracking_enabled', '${status.enabled}');
    }
    trackingEnabled = status.enabled;
    backgroundTrackingRunning = status.running;
    androidBlockingEnabled = status.blockingEnabled;
    trackingError = status.error;
    if (!status.enabled && blockedSource != null) dismissBlock();
  }

  Future<void> overrideBlock() async {
    final source = blockedSource;
    if (source != null) await overrideSource(source);
  }

  Future<void> overrideSource(String source) async {
    if (_resetting) throw StateError('Device reset is in progress.');
    final until = now.add(const Duration(minutes: 5));
    final next = {..._overrides, source: until};
    await store.saveSetting(
      'overrides',
      jsonEncode(next.map((k, v) => MapEntry(k, v.toIso8601String()))),
    );
    _overrides[source] = until;
    if (blockedSource != null && matchesSource(source, blockedSource!)) {
      dismissBlock();
    }
    _changed();
  }

  void dismissBlock() {
    if (tracker.isAndroid && blockedSource != null) {
      unawaited(
        tracker.hideAndroidBlock().catchError((Object error) {
          trackingError = 'Could not dismiss Android blocking: $error';
          _changed();
        }),
      );
    }
    blockedSource = null;
    blockMessage = null;
    _changed();
  }

  Future<void> dismissTrackingInterruption() async {
    await store.saveSetting('tracking_interruption', '');
    trackingInterruption = null;
    _changed();
  }

  Future<void> _recordWindowsCheck() async {
    final checkedAt = now;
    final previous = _lastWindowsCheck;
    if (previous != null &&
        checkedAt.difference(previous) > const Duration(seconds: 5)) {
      String time(DateTime value) =>
          '${value.toUtc().toIso8601String().split('.').first.replaceFirst('T', ' ')} UTC';
      trackingInterruption =
          'Tracking could not be confirmed between ${time(previous)} and ${time(checkedAt)}. No activity was estimated for this gap.';
      await store.saveSetting('tracking_interruption', trackingInterruption!);
    }
    await store.saveSetting('tracking_heartbeat', checkedAt.toIso8601String());
    _lastWindowsCheck = checkedAt;
  }

  Future<void> prepareForReset() async {
    _resetting = true;
    _timer?.cancel();
    await disableTracking();
    await _refreshDone?.future;
    completionAlertsEnabled = false;
    await store.saveSetting('completion_alerts_enabled', 'false');
    await completionAlerts?.synchronize(enabled: false);
    await browserBridge?.disconnect();
    await browserBridge?.close();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || _resetting) return;
    _refreshing = true;
    _refreshDone = Completer<void>();
    try {
      final tick = _ticks++;
      AndroidTrackingStatus? android;
      if (tracker.isAndroid) {
        android = await tracker.androidStatus();
        await _adoptAndroidStatus(android);
      }
      if (trackingEnabled && tracker.supported) {
        accessGranted = await tracker.hasAccess();
        if (!accessGranted) {
          _openInterval = null;
          _previousObservation = null;
          if (blockedSource != null) dismissBlock();
        } else if (tracker.isWindows) {
          var current = tracker.foreground();
          if (current != null) {
            final activity = await tracker.windowsActivity(current.processId);
            if (!activity.current ||
                (activity.idleKnown &&
                    activity.mediaAvailable &&
                    activity.idle >= const Duration(minutes: 3) &&
                    !(browserBridge
                            ?.observationFor(current.source)
                            ?.mediaPlaying ??
                        activity.mediaPlaying))) {
              current = null;
            }
          }
          final observed = now;
          if (current == null || current.source == 'windows:lockin.exe') {
            _openInterval = null;
          } else {
            final previous = _previousObservation;
            final entered = _openInterval?.source != current.source;
            if (entered ||
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
            _checkBlock(current.source, entered: entered);
          }
          await _recordBrowser(current, observed);
          _previousObservation = observed;
        } else {
          if (!backgroundTrackingRunning) {
            if (blockedSource != null) dismissBlock();
            throw StateError(
              android?.error ?? 'Background tracking is stopped. Open Grindset to restart it.',
            );
          }
          if (tick % 15 == 0) {
            final until = now;
            final earliest = until.subtract(const Duration(days: 3));
            var from =
                _lastAndroidImport?.subtract(const Duration(days: 1)) ??
                accountDay(until, location).$1;
            if (from.isBefore(earliest)) from = earliest;
            if (!from.isBefore(until)) from = accountDay(until, location).$1;
            final intervals = await tracker.androidHistory(
              deviceId,
              from,
              until,
            );
            await store.transaction(() async {
              for (final interval in intervals) {
                await store.putUsage(interval);
              }
              await store.saveSetting(
                'android_imported_until',
                until.toIso8601String(),
              );
            });
            _lastAndroidImport = until;
            await reloadUsage();
          }
          final source = androidBlockingEnabled
              ? await tracker.androidForegroundSource()
              : null;
          if (source == null || !trackingEnabled) {
            if (blockedSource != null) dismissBlock();
          } else {
            _checkBlock(source);
          }
        }
      }
      if (tick % 5 == 0) await reloadUsage();
      if (tracker.isWindows && trackingEnabled) await _recordWindowsCheck();
      trackingError = android?.error;
    } catch (error) {
      trackingError = 'Tracking interrupted: $error';
      _webInterval = null;
      _lastWebObservation = null;
      _openInterval = null;
      _previousObservation = null;
    } finally {
      _refreshing = false;
      _refreshDone?.complete();
      _refreshDone = null;
      _changed();
    }
  }

  Future<void> _recordBrowser(ForegroundApp? app, DateTime observed) async {
    final snapshot = app == null
        ? null
        : browserBridge?.observationFor(app.source);
    final native = _openInterval;
    if (snapshot == null || native == null) {
      _webInterval = null;
      _lastWebObservation = null;
      return;
    }
    final at = snapshot.observedAt.isAfter(observed)
        ? observed
        : snapshot.observedAt;
    if (_webInterval?.source != snapshot.source) {
      final previous = _webInterval;
      if (previous != null &&
          at.isAfter(previous.start) &&
          _lastWebObservation != null &&
          at.difference(_lastWebObservation!) <= const Duration(seconds: 12)) {
        await store.putUsage(
          UsageInterval(
            id: previous.id,
            deviceId: deviceId,
            source: previous.source,
            start: previous.start,
            end: at,
          ),
        );
      }
      _webInterval = (
        id: _uuid.v4(),
        source: snapshot.source,
        start: at.isAfter(native.start) ? at : native.start,
      );
      _lastWebObservation = null;
    }
    final open = _webInterval!;
    if (at.isAfter(open.start) &&
        (_lastWebObservation == null || at.isAfter(_lastWebObservation!))) {
      await store.putUsage(
        UsageInterval(
          id: open.id,
          deviceId: deviceId,
          source: open.source,
          start: open.start,
          end: at,
        ),
      );
    }
    _lastWebObservation = at;
  }

  DateTime? _overrideUntil(String source) {
    DateTime? latest;
    for (final entry in _overrides.entries) {
      if (matchesSource(entry.key, source) &&
          (latest == null || entry.value.isAfter(latest))) {
        latest = entry.value;
      }
    }
    return latest;
  }

  Map<String, Object> websiteRestrictions() {
    final blocked = <Map<String, String>>[];
    for (final source
        in rules
            .expand((rule) => rule.sources)
            .toSet()
            .where((source) => source.startsWith('web:'))) {
      final host = websiteHost(source.substring(4));
      if (host == null) continue;
      final reason = restrictionForSource('web:$host');
      if (trackingEnabled && reason != null) {
        blocked.add({'domain': host, 'reason': reason});
      }
    }
    final allowed = _overrides.entries
        .where(
          (entry) => entry.key.startsWith('web:') && entry.value.isAfter(now),
        )
        .map((entry) => websiteHost(entry.key.substring(4)))
        .nonNulls
        .toList();
    return {
      'enabled': trackingEnabled,
      'blocked': blocked,
      'allowed': trackingEnabled ? allowed : <String>[],
    };
  }

  String? restrictionForSource(String source) {
    String? reason;
    for (final rule in rules.where(
      (r) => r.sources.any((candidate) => matchesSource(candidate, source)),
    )) {
      reason = blockingReason(
        rule: rule,
        now: now,
        location: location,
        intervals: usage,
        focusing: session?.focusing(now) ?? false,
        overrideUntil: _overrideUntil(source),
      );
      if (reason != null) break;
    }
    return reason;
  }

  void _checkBlock(String source, {bool entered = false}) {
    final reason = restrictionForSource(source);
    if (reason == null) {
      dismissBlock();
      return;
    }
    final changed = blockedSource != source;
    blockedSource = source;
    blockMessage = reason;
    if ((changed || entered) && showBlock != null) {
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
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    if (tracker.isAndroid) NativeTracker.channel.setMethodCallHandler(null);
    super.dispose();
  }
}
