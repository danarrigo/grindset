import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
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

/// A change strict mode does not allow right now. Its message is for people.
class StrictModeLocked implements Exception {
  StrictModeLocked(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A loosening change that waits for the unlock pause: a reason and a
/// countdown, shown by the app before it tries again.
class UnlockPauseNeeded implements Exception {
  UnlockPauseNeeded(this.what);

  /// What is being unlocked, as in "you can't [what] right now".
  final String what;
  @override
  String toString() => 'Give a reason to $what.';
}

/// One time the unlock pause was passed on this device.
typedef UnlockRecord = ({DateTime at, String what, String reason});

/// An AI's answer to a reason to unlock. [minutes] is how long it allows
/// one app or site for, when asked about one.
typedef UnlockVerdict = ({bool allow, String message, int? minutes});

/// Asks an AI whether [reason] is good enough to [what] while blocking is
/// on [because]. May throw an exception whose message is for people.
typedef UnlockJudge = Future<UnlockVerdict> Function({
  required String what,
  required String because,
  required String reason,
  required String localTime,
  required int unlocksToday,
});

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

  /// When every "while I'm focusing" rule blocks without a timer. Shared by
  /// all of the account's devices; empty when Focus hours are off.
  List<ScheduleWindow> focusHours = const [];

  /// The times Focus hours use when on; kept while they are off.
  List<ScheduleWindow> focusHoursSaved = const [];

  bool get inFocusHours => focusHours.any((w) => w.contains(now, location));

  /// Whether Grindset starts with Windows; null where it is not managed.
  bool? get windowsStartup => _windowsStartup;
  bool? _windowsStartup;
  set windowsStartup(bool? value) {
    if (value == _windowsStartup) return;
    _windowsStartup = value;
    notifyListeners();
  }

  /// Whether the first-launch walkthrough is done (or skipped) on this device.
  bool onboarded = true;

  Future<void> finishOnboarding() async {
    await store.saveSetting('onboarded', 'true');
    onboarded = true;
    notifyListeners();
  }

  /// Creates a rule from a starter during onboarding.
  Future<void> addStarterRule(String name, Set<String> sources, int? minutes) =>
      saveRule(
        ActivityRule(
          id: _uuid.v4(),
          name: name,
          sources: sources.toList(),
          dailyMinutes: minutes,
        ),
      );

  /// Strict mode: while blocking is in force, nothing can be loosened.
  /// Shared by all of the account's devices.
  bool strictMode = false;

  /// When strict mode is locked, why: "during Focus hours". Null otherwise.
  String? get strictLock => strictMode ? blockingNow : null;

  /// Why blocking is in force right now, as in "locked during Focus hours",
  /// or null when nothing blocks. A break does not count.
  String? get blockingNow {
    if (session?.focusing(now) ?? false) return 'during your focus session';
    if (inFocusHours) return 'during Focus hours';
    for (final rule in rules) {
      final reason = blockingReason(
        rule: rule,
        now: now,
        location: location,
        intervals: usage,
      );
      if (reason == null) continue;
      return reason == 'Daily budget reached'
          ? 'while a daily limit is reached'
          : 'during a scheduled block';
    }
    return null;
  }

  bool? _strictLocked;

  /// The site in the front browser's address bar, read only when its
  /// extension is not reporting (Windows).
  ({String source, String host})? _addressBar;
  ({String host, DateTime at})? _closedSite;

  /// Closes a blocked site's tab in the front browser. Returns whether it did.
  Future<bool> _closeBlockedSite(ForegroundApp browser) async {
    final host = _addressBar!.host;
    final reason = restrictionForSource('web:$host');
    if (reason == null) return false;
    // The tab takes a moment to close; do not close a second one meanwhile.
    final last = _closedSite;
    if (last != null &&
        last.host == host &&
        now.difference(last.at) < const Duration(seconds: 3)) {
      return true;
    }
    if (!await tracker.closeBrowserTab(browser.processId)) return false;
    _closedSite = (host: host, at: now);
    unawaited(
      completionAlerts?.showSiteClosed(host, reason).catchError((_) {}),
    );
    return true;
  }

  /// Told when strict mode locks or unlocks, e.g. to keep Windows running.
  Future<void> Function(bool locked)? onStrictLockChanged;
  String? _foregroundSource;
  DateTime _foregroundSince = DateTime.utc(0);

  /// A browser in front whose Grindset extension has not reported since it
  /// came to the front, while websites are blocked. Switching to a browser
  /// makes a running extension report within a moment, so this allows a few
  /// seconds' grace.
  bool _browserWithoutExtension(String source) {
    final bridge = browserBridge;
    if (bridge == null ||
        _addressBar?.source == source ||
        !source.startsWith('windows:') ||
        serviceFor(source)?.category != 'Whole browser' ||
        (websiteRestrictions()['blocked'] as List).isEmpty) {
      return false;
    }
    final since = _foregroundSource == source ? _foregroundSince : now;
    if (now.difference(since) < const Duration(seconds: 10)) return false;
    final heard = bridge.lastHeartbeat(source);
    return heard == null || heard.isBefore(since);
  }

  /// Android's uninstall screens, blocked while strict mode is locked.
  static const uninstallers = {
    'android:com.android.packageinstaller',
    'android:com.google.android.packageinstaller',
  };

  /// Throws [StrictModeLocked] when strict mode does not allow [what] now.
  void requireUnlocked(String what) {
    final lock = strictLock;
    if (lock != null) {
      throw StrictModeLocked('Strict mode: you can\'t $what $lock.');
    }
    if (needsUnlockPause) throw UnlockPauseNeeded(what);
  }

  /// Seconds to wait, with a reason, before loosening anything while
  /// blocking is in force. 0 turns the pause off. This device only.
  int unlockPause = 0;
  static const unlockPauses = [0, 30, 60, 300];

  /// After the pause is passed, the change it was for may go ahead.
  DateTime? _unlockedForChange;

  /// The AI that judges reasons, when this device can reach one.
  UnlockJudge? askAi;

  /// Time an AI allowed in one blocked app or site, by source, until when.
  /// It lifts that source's rules, even in strict mode.
  Map<String, DateTime> passes = const {};
  static const maxPass = Duration(minutes: 30);
  Timer? _passTimer;

  /// A blocked app whose block screen asked for time, for the app to ask
  /// about. Cleared by [takePassRequest].
  String? passRequest;

  void requestPassFor(String source) {
    passRequest = source;
    _changed();
  }

  String? takePassRequest() {
    final source = passRequest;
    passRequest = null;
    return source;
  }

  /// When [source]'s pass ends, or null without one.
  DateTime? passUntil(String source) {
    for (final pass in passes.entries) {
      if (now.isBefore(pass.value) && matchesSource(pass.key, source)) {
        return pass.value;
      }
    }
    return null;
  }

  /// Whether an AI can give [source] time now: it is blocked by a rule, not
  /// by strict mode's own lock.
  bool canAskForPass(String source) {
    if (askAi == null) return false;
    final reason = restrictionForSource(source);
    return reason != null && !reason.startsWith('Strict mode');
  }

  /// What blocks [source] now and from when until when, for its block
  /// screen. [from] is null for a daily limit, which ends at midnight. Null
  /// when nothing does, or when it is strict mode's own lock.
  ({String label, DateTime? from, DateTime until})? blockSpan(String source) {
    (DateTime, DateTime)? latest(Iterable<ScheduleWindow> windows) {
      (DateTime, DateTime)? found;
      for (final window in windows) {
        final span = window.span(now, location);
        if (span != null && (found == null || span.$2.isAfter(found.$2))) {
          found = span;
        }
      }
      return found;
    }

    switch (restrictionForSource(source)) {
      case 'Focus session in progress':
        final current = session!;
        return (
          label: 'Focus session',
          from: current.start,
          until: current.end,
        );
      case 'Focus hours':
        final span = latest(focusHours);
        if (span == null) return null;
        return (label: 'Focus hours', from: span.$1, until: span.$2);
      case 'Scheduled restriction':
        final span = latest([
          for (final rule in rules)
            if (rule.sources.any((s) => matchesSource(s, source)))
              ...rule.schedules,
        ]);
        if (span == null) return null;
        return (label: 'Scheduled block', from: span.$1, until: span.$2);
      case 'Daily budget reached':
        return (
          label: 'Daily limit reached',
          from: null,
          until: accountDay(now, location).$2,
        );
      default:
        return null;
    }
  }

  /// Why [source] is blocked, as in "during Focus hours".
  String blockedBecause(String source) =>
      switch (restrictionForSource(source)) {
        'Focus hours' => 'during Focus hours',
        'Focus session in progress' => 'during your focus session',
        'Daily budget reached' => 'because its daily limit is reached',
        'Scheduled restriction' => 'during a scheduled block',
        _ => 'right now',
      };

  /// Asks the AI for time in [source], called [name] for people. When it
  /// agrees, [source] opens for the minutes it gave.
  Future<UnlockVerdict> requestPass(
    String source, {
    required String name,
    required String reason,
  }) async {
    final judge = askAi;
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw ArgumentError('Give a reason.');
    if (judge == null || !canAskForPass(source)) {
      return (
        allow: false,
        message: judge == null
            ? 'The AI check isn\'t available here.'
            : '$name isn\'t blocked by a rule right now.',
        minutes: null,
      );
    }
    final local = tz.TZDateTime.from(now, location);
    final verdict = await judge(
      what: 'open $name for a few minutes',
      because: blockedBecause(source),
      reason: trimmed,
      localTime:
          '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][local.weekday - 1]} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
      unlocksToday: unlocksToday.length,
    );
    if (!verdict.allow) return verdict;
    final minutes = (verdict.minutes ?? 5).clamp(1, maxPass.inMinutes);
    final at = now;
    await _logUnlock(at, 'open $name for $minutes min', trimmed);
    passes = Map.unmodifiable({
      for (final pass in passes.entries)
        if (at.isBefore(pass.value) && pass.key != source) pass.key: pass.value,
      source: at.add(Duration(minutes: minutes)),
    });
    await _savePasses();
    if (blockedSource != null && restrictionForSource(blockedSource!) == null) {
      dismissBlock();
    }
    _changed();
    requestForegroundCheck();
    return (allow: true, message: verdict.message, minutes: minutes);
  }

  Future<void> _savePasses() async {
    await store.saveSetting(
      'unlock_passes',
      jsonEncode({
        for (final pass in passes.entries)
          pass.key: pass.value.toIso8601String(),
      }),
    );
    _schedulePassEnd();
  }

  /// Checks the front app again when the next pass ends, so its block
  /// comes back on time.
  void _schedulePassEnd() {
    _passTimer?.cancel();
    final ends = passes.values.where(now.isBefore).toList()..sort();
    if (ends.isEmpty || _disposed) return;
    _passTimer = Timer(
      ends.first.difference(now) + const Duration(seconds: 1),
      () {
        _changed();
        requestForegroundCheck();
        _schedulePassEnd();
      },
    );
  }

  /// A break: blocking is off on this device until then.
  DateTime? breakUntil;
  static const breakLength = Duration(minutes: 15);

  bool get onBreak => breakUntil != null && now.isBefore(breakUntil!);

  /// Whether loosening something now first needs the unlock pause.
  bool get needsUnlockPause =>
      unlockPause > 0 &&
      !strictMode &&
      blockingNow != null &&
      !onBreak &&
      !(_unlockedForChange != null && now.isBefore(_unlockedForChange!));

  /// The last week of passed unlock pauses, newest first.
  List<UnlockRecord> unlocks = const [];

  /// Unlocks since the start of today.
  List<UnlockRecord> get unlocksToday {
    final today = accountDay(now, location).$1;
    return [
      for (final u in unlocks)
        if (!u.at.isBefore(today)) u,
    ];
  }

  Future<void> setUnlockPause(int seconds) async {
    if (!unlockPauses.contains(seconds)) {
      throw ArgumentError('Choose one of $unlockPauses seconds.');
    }
    if (seconds < unlockPause) requireUnlocked('shorten the unlock pause');
    await store.saveSetting('unlock_pause', '$seconds');
    unlockPause = seconds;
    _changed();
  }

  /// Records a passed unlock pause. Lets the change it was for go ahead, or
  /// with [takeBreak] turns blocking off on this device for [breakLength].
  Future<void> recordUnlock(
    String what,
    String reason, {
    bool takeBreak = false,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw ArgumentError('Give a reason.');
    final at = now;
    await _logUnlock(at, what, trimmed);
    if (takeBreak) {
      breakUntil = at.add(breakLength);
      await store.saveSetting('break_until', breakUntil!.toIso8601String());
    } else {
      _unlockedForChange = at.add(const Duration(minutes: 2));
    }
    _changed();
    if (takeBreak) requestForegroundCheck();
  }

  Future<void> _logUnlock(DateTime at, String what, String reason) async {
    final kept = [
      (at: at, what: what, reason: reason),
      for (final u in unlocks)
        if (at.difference(u.at) < const Duration(days: 8)) u,
    ];
    await store.saveSetting(
      'unlock_log',
      jsonEncode([
        for (final u in kept)
          {'at': u.at.toIso8601String(), 'what': u.what, 'reason': u.reason},
      ]),
    );
    unlocks = List.unmodifiable(kept);
  }

  /// Ends a break early: blocking is back on now.
  Future<void> endBreak() async {
    breakUntil = null;
    await store.saveSetting('break_until', '');
    _changed();
    requestForegroundCheck();
  }

  Future<void> _loadUnlocks() async {
    unlockPause = int.tryParse(await store.setting('unlock_pause') ?? '') ?? 0;
    if (!unlockPauses.contains(unlockPause)) unlockPause = 0;
    breakUntil = DateTime.tryParse(await store.setting('break_until') ?? '');
    try {
      unlocks = List.unmodifiable([
        for (final u
            in jsonDecode(await store.setting('unlock_log') ?? '[]') as List)
          (
            at: DateTime.parse(u['at'] as String),
            what: u['what'] as String,
            reason: u['reason'] as String,
          ),
      ]);
    } on Object {
      unlocks = const [];
    }
    try {
      final saved =
          jsonDecode(await store.setting('unlock_passes') ?? '{}') as Map;
      passes = Map.unmodifiable({
        for (final pass in saved.entries)
          pass.key as String: DateTime.parse(pass.value as String),
      });
    } on Object {
      passes = const {};
    }
    _schedulePassEnd();
  }

  /// Minute of the day the current Focus hours end, or null outside them.
  int? get focusHoursEnd =>
      focusHours.where((w) => w.contains(now, location)).firstOrNull?.endMinute;

  /// Time left until the current Focus hours end, or null outside them.
  Duration? get focusHoursLeft {
    final end = focusHoursEnd;
    if (end == null) return null;
    final local = tz.TZDateTime.from(now, location);
    var until = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day,
    ).add(Duration(minutes: end));
    if (!until.isAfter(local)) until = until.add(const Duration(days: 1));
    return until.difference(local);
  }

  /// Minute of the day Focus hours next start today, or null if not today.
  int? get focusHoursNextStart {
    final local = tz.TZDateTime.from(now, location);
    final minute = local.hour * 60 + local.minute;
    final starts = [
      for (final w in focusHours)
        if (w.weekdays.contains(local.weekday) && w.startMinute > minute)
          w.startMinute,
    ]..sort();
    return starts.firstOrNull;
  }

  /// Light, dark or following the system, on this device only.
  ThemeMode themeMode = ThemeMode.system;
  String? budgetWarningsNotice;
  String _budgetWarningDay = '';
  final Set<String> _budgetWarnedRules = {};

  /// Notifications for these are optional ([budgetWarningsEnabled]).
  List<BudgetWarning> get budgetWarnings =>
      budgetWarningsEnabled ? nearLimits : const [];

  /// Rules at 80% of their daily limit, shown in the app whether or not
  /// notifications are on.
  List<BudgetWarning> get nearLimits => !trackingEnabled
      ? const []
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
  bool _foregroundCheckPending = false;
  Completer<void>? _refreshDone;
  bool _resetting = false;
  bool _disposed = false;
  int _ticks = 0;
  DateTime? _previousObservation;
  ({String id, String source, DateTime start})? _openInterval;
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
  bool instantBlockingAvailable = false;
  bool instantBlockingEnabled = false;
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
    await _repairFocusFlags();
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
    themeMode =
        ThemeMode.values.asNameMap()[await store.setting('theme')] ??
        ThemeMode.system;
    focusHours = await _loadFocusHours();
    focusHoursSaved = await _loadFocusHoursSaved();
    strictMode = await store.setting('strict_mode') == 'true';
    await _loadUnlocks();
    _lastAndroidImport = DateTime.tryParse(
      await store.setting('android_imported_until') ?? '',
    );
    if (tracker.isAndroid) {
      tracker.bindAndroidActions(
        onDismiss: dismissBlock,
        onStopped: () => disableTracking(notifyNative: false),
        onForegroundChanged: requestForegroundCheck,
        onPassRequested: (source) {
          if (canAskForPass(source)) requestPassFor(source);
        },
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
          final span = blockSpan(source);
          await tracker.showAndroidBlock(
            source,
            blockMessage ?? 'An activity rule is active.',
            askAi: canAskForPass(source),
            name: appDetails[source]?.label ?? sourceName(source),
            label: span?.label,
            from: span?.from,
            until: span?.until,
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
    // People who set Grindset up before onboarding existed skip it.
    onboarded =
        await store.setting('onboarded') == 'true' ||
        trackingEnabled ||
        rules.isNotEmpty ||
        await store.setting('cloud_owner') != null;
    if (tracker.isWindows) {
      tracker.bindWindowsForeground(requestForegroundCheck);
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
      focusHours = await _loadFocusHours();
      focusHoursSaved = await _loadFocusHoursSaved();
      strictMode = await store.setting('strict_mode') == 'true';
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

  Future<void> setThemeMode(ThemeMode mode) async {
    await store.saveSetting('theme', mode.name);
    themeMode = mode;
    _changed();
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
      requestForegroundCheck();
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

  /// Time per app or site over the last 7 days on all devices, most first.
  Future<List<({String source, Duration duration})>> recentUse() async {
    final from = now.subtract(const Duration(days: 7));
    final rows = await store.usage(from: from);
    final bySource = <String, List<UsageInterval>>{};
    for (final row in rows) {
      (bySource[row.source] ??= []).add(row);
    }
    return [
      for (final MapEntry(:key, :value) in bySource.entries)
        (source: key, duration: combinedUsage(value, from: from, until: now)),
    ]..sort((a, b) => b.duration.compareTo(a.duration));
  }

  Duration deviceUsage(String id) => combinedUsage(
    usage.where((i) => i.deviceId == id),
    from: accountDay(now, location).$1,
    until: now,
  );
  Duration ruleUsage(ActivityRule rule) => combinedUsage(
    usageOf(rule, usage),
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
    if (strictMode && active.focusing(now)) {
      throw StrictModeLocked(
        'Strict mode: this focus session runs to the end.',
      );
    }
    if (active.focusing(now) && needsUnlockPause) {
      throw UnlockPauseNeeded('end this focus session early');
    }
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
      throw StateError('A rule was removed. Review this profile.');
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
    requireUnlocked('switch focus profiles');
    final profile = focusProfiles.where((p) => p.id == id).firstOrNull;
    if (profile == null) throw StateError('Profile no longer exists.');
    await store.transaction(() async {
      final current = await store.rules();
      if (!profile.ruleIds.every((id) => current.any((r) => r.id == id))) {
        throw StateError(
          'A rule was removed. Edit this profile before using it.',
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
      requestForegroundCheck();
    } else {
      await refresh();
    }
  }

  /// Up to 1.6.20, rules that came from the account arrived not blocking
  /// while focusing, unlike rules made on the device. Once, those never
  /// chosen here are switched on; choices made here are kept.
  Future<void> _repairFocusFlags() async {
    if (await store.setting('focus_flags_repaired') == 'true') return;
    await store.transaction(() async {
      final flags = Map<String, dynamic>.from(
        jsonDecode(await store.setting('focus_flags') ?? '{}') as Map,
      );
      final current = await store.rules();
      final next = [
        for (final rule in current)
          rule.focusBlock || flags.containsKey(rule.id)
              ? rule
              : ActivityRule.fromJson({...rule.toJson(), 'focus_block': true}),
      ];
      await store.saveRules(next);
      for (final rule in next) {
        await sharedState.rememberFocusFlag(rule);
      }
      await store.saveSetting('focus_flags_repaired', 'true');
    });
  }

  Future<void> checkTrackingHealth() async {
    await _refreshDone?.future;
    await refresh();
  }

  Future<void> saveRule(ActivityRule rule, {int? baseRevision}) async {
    final old = rules.where((r) => r.id == rule.id).firstOrNull;
    if (old != null && !isStricter(old, rule)) {
      requireUnlocked('loosen a rule');
    }
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
    requireUnlocked('delete a rule');
    await store.transaction(() async {
      await store.saveRules((await store.rules()).where((r) => r.id != id));
      await sharedState.queue('rule', id, null, baseRevision: ruleRevision(id));
    });
    rules = await store.rules();
    _changed();
    onSharedChange?.call();
  }

  Future<List<ScheduleWindow>> _loadFocusHours() async {
    final saved = await store.setting('focus_hours');
    return saved == null ? const [] : decodeFocusHours(saved);
  }

  Future<List<ScheduleWindow>> _loadFocusHoursSaved() async {
    if (focusHours.isNotEmpty) return focusHours;
    final saved = await store.setting('focus_hours_saved');
    return saved == null ? const [] : decodeFocusHours(saved);
  }

  /// Saves Focus hours here and for the account's other devices. An empty
  /// list turns them off.
  Future<void> setFocusHours(List<ScheduleWindow> windows) async {
    if (_resetting) throw StateError('Device reset is in progress.');
    if (windows.length > 64) throw ArgumentError('Choose up to 64 times.');
    if (!coversWindows(windows, focusHours)) {
      requireUnlocked('shorten or turn off Focus hours');
    }
    // Turning them off keeps the times, to restore when turned back on.
    final saved = windows.isNotEmpty
        ? windows
        : focusHours.isNotEmpty
        ? focusHours
        : focusHoursSaved;
    final value = {
      'schedules': [for (final w in windows) w.toJson()],
      if (windows.isEmpty && saved.isNotEmpty)
        'saved': [for (final w in saved) w.toJson()],
    };
    await store.transaction(() async {
      await store.saveSetting('focus_hours', jsonEncode(value['schedules']));
      await store.saveSetting(
        'focus_hours_saved',
        jsonEncode([for (final w in saved) w.toJson()]),
      );
      await sharedState.queue('setting', 'focus_hours', value);
    });
    focusHours = List.unmodifiable(windows);
    focusHoursSaved = List.unmodifiable(saved);
    _changed();
    onSharedChange?.call();
  }

  /// Turns strict mode on or off here and on the account's other devices.
  Future<void> setStrictMode(bool enabled) async {
    if (_resetting) throw StateError('Device reset is in progress.');
    if (!enabled) requireUnlocked('turn off strict mode');
    await store.transaction(() async {
      await store.saveSetting('strict_mode', '$enabled');
      await sharedState.queue('setting', 'strict_mode', {'enabled': enabled});
    });
    strictMode = enabled;
    _changed();
    onSharedChange?.call();
  }

  Future<void> setTimezone(String value) async {
    tz.getLocation(value);
    requireUnlocked('change the timezone');
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
    // Android stopping on its own is reported with notifyNative false.
    if (notifyNative) requireUnlocked('stop tracking');
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
    instantBlockingAvailable = status.instantAvailable;
    instantBlockingEnabled = status.instantEnabled;
    trackingError = status.error;
    if (!status.enabled && blockedSource != null) dismissBlock();
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
    requireUnlocked('reset this device');
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

  void requestForegroundCheck() {
    if (_disposed || _resetting) return;
    _foregroundCheckPending = true;
    if (!_refreshing) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || _resetting) return;
    _foregroundCheckPending = false;
    _refreshing = true;
    _refreshDone = Completer<void>();
    try {
      final tick = _ticks++;
      final locked = strictLock != null;
      if (locked != _strictLocked) {
        if (tracker.isAndroid) await tracker.setAndroidStrictLock(locked);
        await onStrictLockChanged?.call(locked);
        _strictLocked = locked;
      }
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
          if (current == null) _addressBar = null;
          if (current?.source != _foregroundSource) {
            _foregroundSource = current?.source;
            _foregroundSince = now;
          }
          if (current == null && blockedSource != null) dismissBlock();
          if (blockedSource != null &&
              restrictionForSource(blockedSource!) == null) {
            dismissBlock();
          }
          if (current != null) {
            // Without the extension, the site comes from the address bar.
            final browser =
                serviceFor(current.source)?.category == 'Whole browser' &&
                browserBridge?.observationFor(current.source) == null;
            final activity = await tracker.windowsActivity(
              current.processId,
              browser: browser,
            );
            _addressBar = browser && activity.current && activity.host != null
                ? (source: current.source, host: activity.host!)
                : null;
            if (!activity.current) {
              current = null;
            } else if (_addressBar != null &&
                restrictWindowsApp != null &&
                await _closeBlockedSite(current)) {
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
      if (_foregroundCheckPending) requestForegroundCheck();
    }
  }

  Future<void> _recordBrowser(ForegroundApp? app, DateTime observed) async {
    final bar = _addressBar;
    final snapshot = app == null
        ? null
        : browserBridge?.observationFor(app.source) ??
              (bar?.source == app.source
                  ? BrowserObservation(
                      source: 'web:${bar!.host}',
                      observedAt: observed,
                      mediaPlaying: false,
                    )
                  : null);
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

  Map<String, Object> websiteRestrictions() {
    final blocked = <Map<String, String>>[];
    // Hundreds of sites share a few rules: decide each rule once.
    final reasons = <ActivityRule, String?>{};
    for (final source
        in rules
            .expand((rule) => rule.sources)
            .toSet()
            .where((source) => source.startsWith('web:'))) {
      final host = websiteHost(source.substring(4));
      if (host == null) continue;
      final reason = restrictionForSource('web:$host', reasons: reasons);
      if (trackingEnabled && reason != null) {
        final span = blockSpan('web:$host');
        blocked.add({
          'domain': host,
          'reason': reason,
          'name': sourceName('web:$host'),
          // The blocked page draws how far through the block it is.
          if (span != null) 'label': span.label,
          if (span?.from != null) 'from': span!.from!.toIso8601String(),
          if (span != null) 'until': span.until.toIso8601String(),
        });
      }
    }
    return {
      'enabled': trackingEnabled,
      'blocked': blocked,
      // The blocked page can then ask an AI for a few minutes.
      'askAi': askAi != null,
    };
  }

  /// Why [source] is blocked now, or null. [reasons] remembers each rule's
  /// answer across calls made at the same moment.
  String? restrictionForSource(
    String source, {
    Map<ActivityRule, String?>? reasons,
  }) {
    // Only these checks need the lock, and working it out visits every rule.
    final lock = uninstallers.contains(source) || source.startsWith('windows:')
        ? strictLock
        : null;
    if (lock != null && uninstallers.contains(source)) {
      return 'Strict mode: uninstalling apps is paused $lock.';
    }
    if (lock != null && _browserWithoutExtension(source)) {
      return BrowserBridge.supports(source)
          ? 'Strict mode: turn on the Grindset extension in this browser to use it $lock.'
          : 'Strict mode: Grindset can\'t check websites in this browser. Use Chrome, Edge, Firefox or Zen $lock.';
    }
    // Time an AI allowed for this one app or site, even in strict mode.
    if (passUntil(source) != null) return null;
    // A break turns rules off here; strict mode never allows one.
    if (onBreak && !strictMode) return null;
    String? reason;
    for (final rule in rules.where(
      (r) => r.sources.any((candidate) => matchesSource(candidate, source)),
    )) {
      String? decide() => blockingReason(
        rule: rule,
        now: now,
        location: location,
        intervals: usage,
        focusing: session?.focusing(now) ?? false,
        focusHours: inFocusHours,
      );
      reason = reasons == null
          ? decide()
          : reasons.containsKey(rule)
          ? reasons[rule]
          : reasons[rule] = decide();
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
    _passTimer?.cancel();
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
