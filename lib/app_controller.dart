import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import 'core/activity.dart';
import 'core/focus_session.dart';
import 'core/focus_profile.dart';
import 'core/budget_warning.dart';
import 'core/service_catalog.dart';
import 'data/local_store.dart';
import 'data/shared_state.dart';
import 'platform/native_tracker.dart';
import 'platform/browser_bridge.dart';
import 'platform/completion_alerts.dart';
import 'platform/site_logos.dart';

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
  bool budgetWarningsEnabled = false;
  String? budgetWarningsNotice;
  String _budgetWarningDay = '';
  final Set<String> _budgetWarnedRules = {};
  List<BudgetWarning> get budgetWarnings =>
      !budgetWarningsEnabled || !trackingEnabled
      ? []
      : nearBudgetWarnings(
          rules: rules,
          intervals: usage,
          now: now,
          location: location,
        );
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
  bool _windowsRefreshPending = false;
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
  List<FocusProfile> focusProfiles = [];
  String _appliedProfileId = '';
  bool windowsForegroundEventsActive = false;
  DateTime? runtimeCheckedAt;
  DateTime? lastVerifiedWindowsBlockAt;
  String? lastVerifiedWindowsBlockSource;

  FocusProfile? get selectedFocusProfile {
    final profile = focusProfiles
        .where((p) => p.id == _appliedProfileId)
        .firstOrNull;
    if (profile == null ||
        !profile.ruleIds.every((id) => rules.any((r) => r.id == id))) {
      return null;
    }
    return setEquals(
          profile.ruleIds,
          rules.where((r) => r.focusBlock).map((r) => r.id).toSet(),
        )
        ? profile
        : null;
  }

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

  /// Website logos, when the app was started with somewhere to keep them.
  SiteLogos? siteLogos;

  /// The logo of the first of [sources] that has a website, loading it in
  /// the background when needed.
  Uint8List? siteLogo(Iterable<String> sources) {
    final logos = siteLogos;
    if (logos == null) return null;
    for (final source in sources) {
      final host = logoHost(source);
      if (host == null) continue;
      final logo = logos.cached(host);
      if (logo == null) {
        unawaited(
          logos.load(host).then((value) {
            if (value != null) _changed();
          }),
        );
      }
      return logo;
    }
    return null;
  }

  /// Installed app names and icons for display, keyed by source.
  final Map<String, ({String label, Uint8List icon})> appDetails = {};
  final Set<String> _requestedAppDetails = {};

  /// Loads names and icons for this device's apps not yet requested.
  void requestAppDetails(Iterable<String> sources) {
    final prefix = tracker.isAndroid
        ? 'android:'
        : tracker.isWindows
        ? 'windows:'
        : null;
    if (prefix == null) return;
    final missing = sources
        .where((s) => s.startsWith(prefix))
        .map((s) => prefix == 'windows:' ? s.toLowerCase() : s)
        .where(_requestedAppDetails.add)
        .toList();
    if (missing.isEmpty) return;
    final ids = [for (final s in missing) s.substring(prefix.length)];
    unawaited(
      (prefix == 'android:'
              ? tracker.androidAppDetails(ids)
              : tracker.windowsAppDetails(ids))
          .then((details) {
            for (final MapEntry(:key, :value) in details.entries) {
              appDetails['$prefix$key'] = value;
            }
            if (details.isNotEmpty) _changed();
          })
          .catchError((Object _) {
            _requestedAppDetails.removeAll(missing);
          }),
    );
  }

  Future<bool> Function(ForegroundApp app)? restrictWindowsApp;
  Future<void> Function(String source)? restoreWindowsApp;
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
    final profiles = await store.setting('focus_profiles');
    focusProfiles = profiles == null
        ? []
        : (jsonDecode(profiles) as List)
              .map(
                (p) =>
                    FocusProfile.fromJson(Map<String, dynamic>.from(p as Map)),
              )
              .toList();
    _appliedProfileId = await store.setting('active_focus_profile') ?? '';
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
    budgetWarningsEnabled =
        await store.setting('budget_warnings_enabled') == 'true';
    _budgetWarningDay = await store.setting('budget_warning_day') ?? '';
    final warned = await store.setting('budget_warning_rules');
    if (warned != null) {
      _budgetWarnedRules.addAll((jsonDecode(warned) as List).cast<String>());
    }
    completionAlertsEnabled =
        await store.setting('completion_alerts_enabled') == 'true';
    await _updateCompletionAlerts();
    await _loadSharedRevisions();
    await reloadUsage();
    if (tracker.isWindows) {
      tracker.bindWindowsForeground(requestWindowsRefresh);
      final watching = await tracker.setWindowsForegroundWatch(trackingEnabled);
      windowsForegroundEventsActive = trackingEnabled && watching;
      if (!watching) {
        throw StateError(
          'Windows foreground restriction monitoring is unavailable.',
        );
      }
    }
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

  Future<void> setBudgetWarningsEnabled(bool enabled) async {
    await store.saveSetting('budget_warnings_enabled', '$enabled');
    budgetWarningsEnabled = enabled;
    budgetWarningsNotice = null;
    _changed();
    if (enabled && completionAlerts != null) {
      try {
        await completionAlerts!.requestPermission(exactAlarm: false);
      } catch (error) {
        budgetWarningsNotice =
            'System warnings unavailable; on-screen warnings remain: $error';
      }
    }
    if (tracker.isWindows) {
      requestWindowsRefresh();
    } else {
      await refresh();
    }
    _changed();
  }

  Future<void> _checkBudgetWarnings() async {
    if (!budgetWarningsEnabled || !trackingEnabled || _resetting || _disposed) {
      return;
    }
    try {
      final day = accountDay(now, location).$1.toIso8601String();
      if (_budgetWarningDay != day) {
        _budgetWarningDay = day;
        _budgetWarnedRules.clear();
      }
      final warnings = budgetWarnings
          .where((w) => !_budgetWarnedRules.contains(w.ruleId))
          .toList();
      if (warnings.isEmpty) return;
      _budgetWarnedRules.addAll(warnings.map((w) => w.ruleId));
      await store.transaction(() async {
        await store.saveSetting('budget_warning_day', day);
        await store.saveSetting(
          'budget_warning_rules',
          jsonEncode(_budgetWarnedRules.toList()),
        );
      });
      if (!budgetWarningsEnabled || !trackingEnabled || _disposed) return;
      budgetWarningsNotice = await completionAlerts?.showBudgetWarnings(
        warnings,
        enabled: () =>
            budgetWarningsEnabled &&
            trackingEnabled &&
            !_disposed &&
            !_resetting,
      );
    } catch (error) {
      budgetWarningsNotice =
          'System warnings unavailable; on-screen warnings remain: $error';
    }
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
      label: phase == SessionPhase.focus
          ? selectedFocusProfile?.name ?? 'Deep work'
          : 'Take a breath',
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

  Future<void> saveFocusProfile(FocusProfile profile) async {
    if (_resetting) throw StateError('Device reset is in progress.');
    if (!profile.ruleIds.every((id) => rules.any((r) => r.id == id))) {
      throw StateError('An activity was removed. Review this profile.');
    }
    if (focusProfiles.any(
      (p) =>
          p.id != profile.id &&
          p.name.toLowerCase() == profile.name.toLowerCase(),
    )) {
      throw StateError('A profile with this name already exists.');
    }
    final next = [...focusProfiles.where((p) => p.id != profile.id), profile];
    await store.saveSetting(
      'focus_profiles',
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );
    focusProfiles = next;
    _changed();
  }

  Future<void> deleteFocusProfile(String id) async {
    if (_resetting) throw StateError('Device reset is in progress.');
    final next = focusProfiles.where((p) => p.id != id).toList();
    await store.transaction(() async {
      await store.saveSetting(
        'focus_profiles',
        jsonEncode(next.map((p) => p.toJson()).toList()),
      );
      if (_appliedProfileId == id) {
        await store.saveSetting('active_focus_profile', '');
      }
    });
    focusProfiles = next;
    if (_appliedProfileId == id) _appliedProfileId = '';
    _changed();
  }

  Future<void> applyFocusProfile(String id) async {
    if (_resetting) throw StateError('Device reset is in progress.');
    final profile = focusProfiles.where((p) => p.id == id).firstOrNull;
    if (profile == null) throw StateError('Profile no longer exists.');
    await store.transaction(() async {
      final current = await store.rules();
      if (!profile.ruleIds.every((id) => current.any((r) => r.id == id))) {
        throw StateError(
          'An activity was removed. Edit this profile before using it.',
        );
      }
      final next = [
        for (final rule in current)
          ActivityRule.fromJson({
            ...rule.toJson(),
            'focus_block': profile.ruleIds.contains(rule.id),
          }),
      ];
      await store.saveRules(next);
      for (final rule in next) {
        await sharedState.rememberFocusFlag(rule);
      }
      await store.saveSetting('active_focus_profile', id);
    });
    rules = await store.rules();
    _appliedProfileId = id;
    if (blockedSource != null && restrictionForSource(blockedSource!) == null) {
      dismissBlock();
    }
    _changed();
    if (tracker.isWindows) {
      requestWindowsRefresh();
    } else {
      await refresh();
    }
  }

  Future<void> checkTrackingHealth() async {
    await _refreshDone?.future;
    await refresh();
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
    if (tracker.isWindows) {
      windowsForegroundEventsActive = await tracker.setWindowsForegroundWatch(
        true,
      );
      if (!windowsForegroundEventsActive) {
        throw StateError(
          'Windows foreground restriction monitoring is unavailable.',
        );
      }
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
      await tracker.setWindowsForegroundWatch(false);
      windowsForegroundEventsActive = false;
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
    runtimeCheckedAt = now;
    backgroundTrackingRunning = status.running;
    androidBlockingEnabled = status.blockingEnabled;
    trackingError = status.error;
    if (!status.enabled && blockedSource != null) dismissBlock();
  }

  Future<void> overrideBlock() async {
    final source = blockedSource;
    if (source != null) {
      await overrideSource(source);
      await restoreWindowsApp?.call(source);
    }
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
    runtimeCheckedAt = checkedAt;
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

  void requestWindowsRefresh() {
    if (_disposed || _resetting) return;
    _windowsRefreshPending = true;
    if (!_refreshing) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || _resetting) return;
    _windowsRefreshPending = false;
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
          if (current == null && blockedSource != null) dismissBlock();
          if (blockedSource != null &&
              restrictionForSource(blockedSource!) == null) {
            dismissBlock();
          }
          if (current != null) {
            final activity = await tracker.windowsActivity(current.processId);
            if (!activity.current) {
              current = null;
            } else if (current.source != 'windows:lockin.exe' &&
                restrictWindowsApp != null) {
              final reason = restrictionForSource(current.source);
              if (reason == null) {
                dismissBlock();
              } else {
                blockedSource = current.source;
                blockMessage = reason;
                _changed();
                final presented = await restrictWindowsApp!(current);
                if (presented) {
                  lastVerifiedWindowsBlockAt = now;
                  lastVerifiedWindowsBlockSource = current.source;
                }
                if (!presented && blockedSource == current.source) {
                  dismissBlock();
                }
                // Enforcement changed foreground. Never account the minimized
                // app as active while its explanation is shown.
                current = null;
              }
            }
            if (current != null &&
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
            if (restrictWindowsApp == null) {
              _checkBlock(current.source, entered: entered);
            }
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
      await _checkBudgetWarnings();
      if (tracker.isWindows && trackingEnabled) await _recordWindowsCheck();
      trackingError = android?.error;
    } catch (error) {
      trackingError = 'Tracking interrupted: $error';
      _webInterval = null;
      _lastWebObservation = null;
      _openInterval = null;
      _previousObservation = null;
      if (tracker.isWindows && blockedSource != null) dismissBlock();
    } finally {
      _refreshing = false;
      _refreshDone?.complete();
      _refreshDone = null;
      _changed();
      if (_windowsRefreshPending) requestWindowsRefresh();
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

  void reportRestrictionFailure(Object error) {
    trackingError = 'Could not restore the desktop restriction window: $error';
    _changed();
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
    if (tracker.isWindows) {
      tracker.bindWindowsForeground(null);
      unawaited(
        tracker
            .setWindowsForegroundWatch(false)
            .catchError((Object _) => false),
      );
    }
    super.dispose();
  }
}
