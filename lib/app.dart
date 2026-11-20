import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_controller.dart';
import 'core/activity.dart';
import 'core/focus_session.dart';
import 'core/rule_presets.dart';
import 'core/service_catalog.dart';
import 'data/cloud_sync.dart';
import 'ui/appearance.dart';
import 'ui/cloud_panel.dart';
import 'ui/duration_dialog.dart';
import 'ui/desktop_shell.dart';
import 'ui/focus_screen.dart';
import 'ui/schedule_summary.dart';
import 'ui/source_label.dart';
import 'platform/windows_apps.dart';
import 'ui/rule_editor.dart';
import 'ui/rule_starters.dart';
import 'ui/updates_panel.dart';
import 'ui/tracking_health_panel.dart';
import 'ui/focus_hours_dialog.dart';
import 'ui/focus_profiles_panel.dart';
import 'ui/weekly_insights_panel.dart';

class LockinApp extends StatelessWidget {
  const LockinApp({
    super.key,
    required this.controller,
    this.cloud,
    this.startupWarning,
    this.enableStartup,
    this.exportData,
    this.resetDevice,
    this.themeMode,
  });
  final AppController controller;
  final CloudSync? cloud;
  final String? startupWarning;
  final Future<void> Function()? enableStartup;
  final Future<bool> Function()? exportData;
  final Future<void> Function()? resetDevice;

  /// Overrides the device's Appearance setting (screenshots and tests).
  final ThemeMode? themeMode;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Grindset',
      debugShowCheckedModeBanner: false,
      theme: lockinTheme(Brightness.light),
      darkTheme: lockinTheme(Brightness.dark),
      themeMode: themeMode ?? controller.themeMode,
      home: _Home(
        controller: controller,
        cloud: cloud,
        startupWarning: startupWarning,
        enableStartup: enableStartup,
        exportData: exportData,
        resetDevice: resetDevice,
      ),
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({
    required this.controller,
    this.cloud,
    this.startupWarning,
    this.enableStartup,
    this.exportData,
    this.resetDevice,
  });
  final AppController controller;
  final CloudSync? cloud;
  final String? startupWarning;
  final Future<void> Function()? enableStartup;
  final Future<bool> Function()? exportData;
  final Future<void> Function()? resetDevice;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  AppController get c => widget.controller;
  ColorScheme get colors => Theme.of(context).colorScheme;
  var _page = 0;
  var _minutes = 25;
  var _phase = SessionPhase.focus;
  bool _busy = false;
  bool _configuringNext = false;

  /// The finished session whose follow-up was already offered.
  String? _offeredAfter;
  bool _weeklyInsights = false;
  final _pageScroll = ScrollController();
  final _focusMenuKey = GlobalKey();
  static const _pages = ['Focus', 'Activity', 'Rules', 'Devices', 'Settings'];
  static const _icons = [
    Icons.timelapse_outlined,
    Icons.bar_chart_outlined,
    Icons.shield_outlined,
    Icons.devices_outlined,
    Icons.settings_outlined,
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _phase = c.session?.phase ?? SessionPhase.focus;
    _minutes = c.preferredMinutes(_phase);
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableTracking() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn on activity tracking?'),
        content: SingleChildScrollView(
          child: Text(
            'Grindset records which app is open and for how long, so your limits and focus rules can work. '
            'It never sees your screen, what you type, or page contents. History stays on this device unless you sign in to sync.\n\n'
            '${c.tracker.isAndroid
                ? 'Next, Android asks for two permissions: Usage access (find Grindset and turn it on) and notifications. A small notification stays while tracking runs; you can stop it from there.'
                : widget.enableStartup == null
                ? 'This preview does not change Windows sign-in startup.'
                : 'Grindset will start when you sign in to Windows and stay in the tray.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (allowed == true && mounted) {
      await _run(() async {
        await c.enableTracking();
        await widget.enableStartup?.call();
      });
    }
  }

  Future<void> _enableAndroidBlocking() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set up app blocking'),
        content: const SingleChildScrollView(
          child: Text(
            'When a rule applies, Grindset covers the app with a "restricted" screen. To do that, Android needs you to allow it to display over other apps.\n\n'
            'On the next screen, tap Grindset, then turn on "Allow display over other apps". Come back here when done.\n\n'
            'You can turn this off any time.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue to Settings'),
          ),
        ],
      ),
    );
    if (allowed == true && mounted) await _run(c.tracker.requestBlockingAccess);
  }

  /// Google Play requires this disclosure, with consent, before the user is
  /// sent to Accessibility settings.
  Future<void> _enableInstantBlocking() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn on instant blocking?'),
        content: const SingleChildScrollView(
          child: Text(
            'Grindset uses Android\'s Accessibility service only to notice when you switch to another app, so an app blocked by your rules is covered the moment it opens instead of a second or two later.\n\n'
            'Grindset only learns the name of the app you opened. It does not read what is on your screen, what you type, or anything inside other apps, and nothing is sent anywhere because of this.\n\n'
            'On the next screen, tap Grindset instant blocking and turn it on. You can turn it off there any time; blocking keeps working, just a little slower.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    );
    if (allowed == true && mounted) await _run(c.tracker.openInstantBlocking);
  }

  Future<void> _exportData() => _run(() async {
    final saved = await widget.exportData!();
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Private JSON archive saved.')),
      );
    }
  });

  Future<void> _resetDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Reset this device?'),
        content: const Text(
          'This permanently clears local history, rules, saved offline edits and the account link on this device. '
          'Tracking and completion alerts stop, browsers disconnect, this device signs out, and Grindset closes.\n\n'
          'Cloud records and other devices are not deleted or signed out. Export your data first if you want to keep a copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset and close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(_performReset);
  }

  Future<void> _performReset() async {
    // Block navigation while collectors, auth and SQLite are being drained.
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Resetting this device'),
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text('Stopping tracking and clearing local data...'),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      await widget.resetDevice!();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await dialog;
    }
  }

  void _pairBrowser() {
    final bridge = c.browserBridge;
    if (bridge == null) return;
    final code = bridge.beginPairing();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pair browser extension'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Load the extension/ folder from this repo in Chrome or Edge using Developer Mode. Open its options and enter this code:',
            ),
            const SizedBox(height: 24),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 32,
                letterSpacing: 6,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Expires in 5 minutes. The extension sends host identifiers and playback state only, never complete URLs or page titles.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _editFocusHours() async {
    final windows = await showDialog<List<ScheduleWindow>>(
      context: context,
      builder: (_) => FocusHoursDialog(
        windows: c.focusHours,
        timezone: c.location.name,
        focusRules: [
          for (final rule in c.rules)
            if (rule.focusBlock) rule.name,
        ],
      ),
    );
    if (windows != null && mounted) {
      await _run(() => c.setFocusHours(windows));
    }
  }

  Future<void> _editRule({ActivityRule? rule, RulePreset? preset}) async {
    final baseRevision = rule == null ? 0 : c.ruleRevision(rule.id);
    final seen = {
      ...c.usage.map((i) => i.source),
      ...c.rules.expand((r) => r.sources),
    };
    c.requestAppDetails(seen);
    final recentUse = await c.recentUse();
    if (!mounted) return;
    final result = await showDialog<ActivityRule>(
      context: context,
      // Rebuilds as installed app names and icons arrive.
      builder: (_) => ListenableBuilder(
        listenable: c,
        builder: (_, _) => RuleEditor(
          rule: rule,
          preset: preset,
          timezone: c.location.name,
          loadWindowsApps: c.tracker.isWindows ? WindowsApps.list : null,
          browseWindowsApp: c.tracker.isWindows ? WindowsApps.browse : null,
          labelFor: (source) => c.appDetails[source]?.label,
          recentUse: recentUse,
          loadInstalledApps: c.tracker.isAndroid
              ? () async => {
                  for (final MapEntry(:key, :value)
                      in (await c.tracker.androidInstalledApps()).entries)
                    'android:$key': value,
                }
              : null,
          iconFor: (sources, name, size) {
            c.requestAppDetails(sources);
            return ListenableBuilder(
              listenable: c,
              builder: (_, _) => SourceIcon(
                controller: c,
                sources: sources,
                name: name,
                size: size,
              ),
            );
          },
          sources: seen,
        ),
      ),
    );
    if (result != null && mounted) {
      await _run(() async {
        await c.saveRule(result, baseRevision: baseRevision);
        if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
      });
    }
  }

  Future<void> _deleteRule(ActivityRule rule) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${rule.name}?'),
        content: const Text('Its restrictions will no longer apply.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await _run(() => c.deleteRule(rule.id));
  }

  Future<void> _customDuration(BuildContext dialogContext) async {
    final result = await showDialog<int>(
      context: dialogContext,
      builder: (_) => DurationDialog(initialMinutes: _minutes),
    );
    if (result != null && mounted) {
      await _run(() async {
        await c.setPreferredMinutes(_phase, result);
        if (mounted) {
          setState(() {
            _minutes = result;
            _configuringNext = true;
          });
        }
      });
    }
  }

  Future<void> _endSession(BuildContext dialogContext) async {
    final yes = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text(
          'Daily budgets and scheduled restrictions will stay active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await _run(c.endSession);
  }

  String _time(DateTime instant) =>
      TimeOfDay.fromDateTime(tz.TZDateTime.from(instant, c.location))
          .format(context);

  bool get _desktopLayout =>
      !c.tracker.isAndroid && MediaQuery.sizeOf(context).width >= 840;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, if (widget.cloud != null) widget.cloud!]),
    builder: (context, _) {
      if (c.tracker.isWindows && c.blockedSource != null) {
        return Theme(
          data: lockinTheme(Brightness.dark),
          child: Builder(
            builder: (context) => Scaffold(body: _blocked(context)),
          ),
        );
      }
      final desktop = _desktopLayout;
      final workspace = _page == 0 ? _focusHome() : _secondaryPages(desktop);
      if (!desktop) return workspace;
      return Theme(
        data: _page == 0 ? lockinTheme(Brightness.dark) : Theme.of(context),
        child: DesktopShell(
          selected: _page,
          onSelected: (page) => setState(() => _page = page),
          destinations: [
            for (var i = 0; i < _pages.length; i++)
              (label: _pages[i], icon: _icons[i]),
          ],
          child: workspace,
        ),
      );
    },
  );

  Widget _secondaryPages(bool desktop) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (!desktop) _toolbar(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final padding = desktop ? 32.0 : 20.0;
                        return SingleChildScrollView(
                          key: ValueKey('page-$_page'),
                          controller: _pageScroll,
                          primary: false,
                          padding: EdgeInsets.all(padding),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0,
                                constraints.maxHeight - padding * 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: desktop ? 1240 : 760,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (widget.startupWarning != null) ...[
                                        _notice(widget.startupWarning!),
                                        const SizedBox(height: 20),
                                      ],
                                      if (c.trackingError != null) ...[
                                        _notice(c.trackingError!),
                                        const SizedBox(height: 20),
                                      ],
                                      switch (_page) {
                                        1 => _activity(),
                                        2 => _rules(),
                                        3 => _devices(),
                                        _ => _settings(),
                                      },
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (c.blockedSource != null)
                Positioned.fill(child: _blocked(context)),
            ],
          ),
        ),
        bottomNavigationBar: desktop ? null : _tabBar(context),
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CupertinoTabBar(
      currentIndex: _page,
      onTap: (index) => setState(() => _page = index),
      height: math.max(58.0, 46 + MediaQuery.textScalerOf(context).scale(12)),
      activeColor: colors.onSurface,
      inactiveColor: colors.onSurfaceVariant,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      border: Border(top: BorderSide(color: colors.outlineVariant, width: .5)),
      iconSize: 22,
      items: [
        for (var i = 0; i < _pages.length; i++)
          BottomNavigationBarItem(
            icon: Icon(_icons[i], key: ValueKey('nav-$i')),
            label: _pages[i],
          ),
      ],
    );
  }

  Widget _focusHome() {
    final theme = lockinTheme(Brightness.dark)
        .copyWith(scaffoldBackgroundColor: const Color(0xFF09090A));
    return Theme(
      data: theme,
      child: CupertinoTheme(
        data: MaterialBasedCupertinoThemeData(materialTheme: theme),
        child: Builder(
          builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: const Color(0xFF09090A),
              systemNavigationBarIconBrightness: Brightness.light,
            ),
            child: Scaffold(
              body: SafeArea(
                child: Stack(
                  children: [
                    _focus(context),
                    if (c.blockedSource != null)
                      Positioned.fill(child: _blocked(context)),
                  ],
                ),
              ),
              bottomNavigationBar: _desktopLayout ? null : _tabBar(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final setup = setupSteps(c);
    final broken = setup.any((s) => s.broken);
    final ready = setup.isNotEmpty && setup.every((s) => s.done);
    final status = !c.tracker.supported
        ? 'Timer only'
        : broken
        ? 'Needs attention'
        : ready
        ? 'Tracking on'
        : 'Finish setup';
    final statusColor = broken
        ? colors.error
        : ready
        ? colors.primary
        : colors.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: .5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Grindset',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Tooltip(
                      message: status,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _page = 4),
                        icon: Icon(
                          broken
                              ? Icons.error_outline_rounded
                              : ready
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: broken ? 15 : 10,
                          color: statusColor,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: broken
                              ? colors.error
                              : colors.onSurfaceVariant,
                        ),
                        label: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _focus(BuildContext context) {
    final active = c.session;
    final now = c.now;
    final running = active?.running(now) ?? false;
    final completed =
        active != null && !now.isBefore(active.end) && !_configuringNext;
    // After a finished focus, offer a break; after a break, offer focus. One
    // tap, never started automatically. A session ended early was stopped,
    // not finished (it is shorter than the length it started with), so the
    // same phase is offered again. Offered once, so the menu can change it.
    final finished =
        completed &&
        active.end.difference(active.start) >=
            Duration(minutes: c.preferredMinutes(active.phase));
    if (completed && _offeredAfter != active.id) {
      _offeredAfter = active.id;
      _phase = finished && active.phase == SessionPhase.focus
          ? SessionPhase.rest
          : SessionPhase.focus;
      _minutes = c.preferredMinutes(_phase);
    }
    final phase = running ? active!.phase : _phase;
    final setup = setupSteps(c);
    final setupDone = setup.where((s) => s.done).length;
    final budgetWarnings = c.budgetWarnings;
    final warnings = [
      for (final warning in budgetWarnings.take(2)) warning.message,
      if (budgetWarnings.length > 2)
        'More rules are near their daily limits. Review Rules.',
      widget.startupWarning,
      c.trackingError,
      if (c.trackingInterruption != null)
        'Tracking was interrupted. See Settings.',
    ].nonNulls;
    return FocusScreen(
      showBrand: !_desktopLayout,
      menuButtonKey: _focusMenuKey,
      remaining: completed
          ? Duration(minutes: _minutes)
          : running
          ? active!.remaining(now)
          : Duration(minutes: _minutes),
      running: running,
      actionLabel: running
          ? phase == SessionPhase.rest
                ? 'End break'
                : 'End session'
          : phase == SessionPhase.focus
          ? 'Lock in'
          : 'Start break',
      status: finished
          ? (active.phase == SessionPhase.focus ? 'Focus done' : 'Break over')
          : !running && c.focusHoursEnd != null
          ? 'Focus hours until ${TimeOfDay(hour: c.focusHoursEnd! ~/ 60, minute: c.focusHoursEnd! % 60).format(context)}'
          : null,
      warning: warnings.isEmpty ? null : warnings.join('\n\n'),
      setupLabel: setupDone == setup.length
          ? null
          : 'Finish setup · $setupDone of ${setup.length} done',
      onSetup: () => setState(() => _page = 4),
      onMenu: _busy ? null : () => _focusMenu(context, running: running),
      onAction: _busy
          ? null
          : running
          ? () => _endSession(context)
          : () => _run(() async {
              await c.startSession(Duration(minutes: _minutes), _phase);
              if (mounted) setState(() => _configuringNext = false);
            }),
    );
  }

  Future<void> _showFocusProfiles([BuildContext? presentation]) =>
      showDialog<void>(
        context: presentation ?? context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FocusProfilesPanel(controller: c),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close profiles'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _focusMenu(BuildContext context, {required bool running}) async {
    final theme = CupertinoTheme.of(context);
    const textStyle = TextStyle(fontFamily: 'Inter');
    // Nonnegative choices use the existing page indices.
    const duration = -1;
    const phase = -2;
    const profiles = -3;
    final choice = _desktopLayout
        ? await showMenu<int>(
            context: context,
            position: _desktopMenuPosition(context),
            items: [
              PopupMenuItem(
                value: profiles,
                child: Text(
                  'Focus profile · ${c.selectedFocusProfile?.name ?? 'Custom'}',
                ),
              ),
              PopupMenuItem(
                value: duration,
                enabled: !running,
                child: Text('Duration · $_minutes min'),
              ),
              PopupMenuItem(
                value: phase,
                enabled: !running,
                child: Text(
                  _phase == SessionPhase.focus
                      ? 'Switch to break · ${c.preferredMinutes(SessionPhase.rest)} min'
                      : 'Switch to focus',
                ),
              ),
            ],
          )
        : await showCupertinoModalPopup<int>(
            context: context,
            builder: (sheetContext) => CupertinoTheme(
              data: theme,
              child: CupertinoActionSheet(
                title: Text(
                  'Grindset',
                  style: textStyle.copyWith(color: const Color(0xFFE5E5EA)),
                ),
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(sheetContext, profiles),
                    child: const Text('Focus profiles', style: textStyle),
                  ),
                  if (!running) ...[
                    CupertinoActionSheetAction(
                      onPressed: () => Navigator.pop(sheetContext, duration),
                      child: Text('Duration · $_minutes min', style: textStyle),
                    ),
                    CupertinoActionSheetAction(
                      onPressed: () => Navigator.pop(sheetContext, phase),
                      child: Text(
                        _phase == SessionPhase.focus
                            ? 'Switch to break · ${c.preferredMinutes(SessionPhase.rest)} min'
                            : 'Switch to focus',
                        style: textStyle,
                      ),
                    ),
                  ],
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Cancel', style: textStyle),
                ),
              ),
            ),
          );
    if (!mounted || !context.mounted || choice == null) return;
    if (choice == profiles) {
      await _showFocusProfiles(context);
    } else if (choice == duration) {
      await _customDuration(context);
    } else if (choice == phase) {
      setState(() {
        _phase = _phase == SessionPhase.focus
            ? SessionPhase.rest
            : SessionPhase.focus;
        _minutes = c.preferredMinutes(_phase);
        _configuringNext = true;
      });
    } else {
      setState(() => _page = choice);
    }
  }

  RelativeRect _desktopMenuPosition(BuildContext context) {
    final button =
        _focusMenuKey.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      button.localToGlobal(Offset.zero, ancestor: overlay) & button.size,
      Offset.zero & overlay.size,
    );
  }

  Widget _heading(String title, {String? subtitle, Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            ?action,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ],
      ],
    ),
  );

  Widget _activity() {
    final header = <Widget>[
      _heading(
        'Activity',
        subtitle: _weeklyInsights
            ? 'This week on this device'
            : 'Today on this device',
      ),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Today'),
            selected: !_weeklyInsights,
            onSelected: (_) => setState(() => _weeklyInsights = false),
          ),
          ChoiceChip(
            label: const Text('Weekly insights'),
            selected: _weeklyInsights,
            onSelected: (_) => setState(() => _weeklyInsights = true),
          ),
        ],
      ),
      const SizedBox(height: 20),
    ];
    if (_weeklyInsights) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          WeeklyInsightsPanel(controller: c),
        ],
      );
    }
    final sources = c.usage
        .where((i) => i.deviceId == c.deviceId)
        .map((i) => i.source)
        .toSet();
    final totals = [
      for (final source in sources)
        (
          source: source,
          used: combinedUsage(
            c.usage.where(
              (i) => i.deviceId == c.deviceId && i.source == source,
            ),
            from: accountDay(c.now, c.location).$1,
            until: c.now,
          ),
        ),
    ]..sort((a, b) => b.used.compareTo(a.used));
    c.requestAppDetails(sources);
    final longest = totals.isEmpty ? Duration.zero : totals.first.used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        Row(
          children: [
            for (final (i, (label, value)) in [
              ('Screen time', c.deviceUsage(c.deviceId)),
              ('Focused', c.focusedToday),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _Section(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        durationLabel(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (totals.isEmpty)
          _empty(
            'No activity yet',
            'Enable tracking to see time spent in foreground apps.',
          ),
        for (final item in totals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SourceIcon(
                  controller: c,
                  sources: [item.source],
                  name: displayName(c, item.source),
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName(c, item.source),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            durationLabel(item.used),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: longest == Duration.zero
                              ? 0
                              : item.used.inSeconds / longest.inSeconds,
                          minHeight: 4,
                          backgroundColor: colors.surfaceContainerHighest,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!c.rules.any(
                  (rule) => rule.sources.any(
                    (source) => matchesSource(source, item.source),
                  ),
                ))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: 'Limit ${displayName(c, item.source)}',
                      child: TextButton(
                        onPressed: () => _editRule(
                          preset: RulePreset(
                            serviceFor(item.source)?.name ??
                                displayName(c, item.source),
                            {...?serviceFor(item.source)?.sources, item.source},
                          ),
                        ),
                        child: const Text('Limit'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _rules() {
    final saved = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your rules', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (c.rules.isEmpty)
          _empty('No rules yet', 'Pick a suggested app or add your own.')
        else
          _savedRules(),
      ],
    );
    final starters = RuleStarters(
      rules: c.rules,
      collapsed: c.rules.isNotEmpty,
      onSelected: (preset) => _editRule(preset: preset),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Rules',
          subtitle: 'Limit apps and websites on all your devices.',
          action: TextButton.icon(
            onPressed: () => _editRule(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add rule'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _editFocusHours,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(
                c.focusHours.isEmpty ? 'Focus hours' : 'Focus hours: on',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showFocusProfiles(),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                MediaQuery.sizeOf(context).width < 480
                    ? 'Profiles'
                    : 'Focus profiles',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (c.budgetWarnings.isNotEmpty) ...[
          _notice(
            c.budgetWarnings.map((warning) => warning.message).join('\n'),
          ),
          const SizedBox(height: 16),
        ],
        if (!c.trackingEnabled) ...[
          _notice(
            'Rules only work while tracking is on. Turn it on in Settings.',
          ),
          const SizedBox(height: 20),
        ],
        if (c.tracker.isAndroid && !c.androidBlockingEnabled) ...[
          _notice('To block apps, finish app blocking setup in Settings.'),
          const SizedBox(height: 20),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >=
                820 *
                    math.max(
                      1,
                      MediaQuery.textScalerOf(context).scale(14) / 14,
                    );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: saved),
                      const SizedBox(width: 24),
                      Expanded(flex: 2, child: starters),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (c.rules.isNotEmpty) ...[
                        saved,
                        const SizedBox(height: 24),
                      ],
                      starters,
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _savedRules() {
    return _Section(
      child: Column(
        children: [
          for (var i = 0; i < c.rules.length; i++) ...[
            if (i > 0) const Divider(indent: 18, endIndent: 18),
            _ruleCard(c.rules[i]),
            if (missingDesktopSources(c.rules[i].sources).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey('desktop-coverage-${c.rules[i].id}'),
                    onPressed: () => _editRule(
                      rule: ActivityRule.fromJson({
                        ...c.rules[i].toJson(),
                        'sources': {
                          ...c.rules[i].sources,
                          ...missingDesktopSources(c.rules[i].sources),
                        }.toList(),
                      }),
                    ),
                    icon: const Icon(Icons.desktop_windows_outlined, size: 18),
                    label: const Text('Add desktop coverage'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _ruleCard(ActivityRule rule) {
    c.requestAppDetails(rule.sources);
    // What the rule does, in the editor's words. The daily limit has its own
    // bar below, so it is only named here when nothing else blocks.
    final summary = [
      if (rule.focusBlock) 'Blocked while you focus',
      for (final window in rule.schedules.take(2))
        'Blocked ${scheduleSummary(context, window)}',
      if (rule.schedules.length > 2) '+${rule.schedules.length - 2} more times',
      if (!rule.focusBlock &&
          rule.schedules.isEmpty &&
          rule.dailyMinutes == null)
        'Tracked only, never blocked',
    ].join(' · ');
    return InkWell(
      onTap: () => _editRule(rule: rule),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 6, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SourceIcon(
                  controller: c,
                  sources: rule.sources.toList(),
                  name: rule.name,
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.name,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options for ${rule.name}',
                  icon: const Icon(Icons.more_horiz_rounded, size: 21),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editRule(rule: rule);
                    } else {
                      _deleteRule(rule);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            if (rule.dailyMinutes case final limit?)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _budgetBar(c.ruleUsage(rule), limit),
              ),
          ],
        ),
      ),
    );
  }

  Widget _budgetBar(Duration used, int limitMinutes) {
    final limit = Duration(minutes: limitMinutes);
    final over = used >= limit;
    final color = over ? colors.error : colors.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: limit == Duration.zero
                  ? 1
                  : (used.inSeconds / limit.inSeconds).clamp(0, 1),
              minHeight: 6,
              backgroundColor: colors.surfaceContainerHighest,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            over
                ? 'Daily limit reached · ${durationLabel(used)} of ${durationLabel(limit)}'
                : '${durationLabel(Duration(minutes: limit.inMinutes - used.inMinutes))} left today · ${durationLabel(used)} of ${durationLabel(limit)}',
            style: TextStyle(
              fontSize: 13,
              color: over ? colors.error : colors.onSurfaceVariant,
              fontWeight: over ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _devices() {
    final remote =
        widget.cloud?.devices.where((d) => d['id'] != c.deviceId).toList() ??
        [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Devices',
          subtitle: 'Confirmed usage only. Disconnected devices may have unsynced activity.',
        ),
        _Section(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  c.tracker.isAndroid
                      ? Icons.phone_android_outlined
                      : Icons.desktop_windows_outlined,
                  size: 23,
                ),
                title: const Text('This device'),
                subtitle: Text(
                  c.tracker.isWindows
                      ? 'Windows'
                      : c.tracker.isAndroid
                      ? 'Android'
                      : 'Native tracking unavailable',
                ),
                trailing: Text(
                  durationLabel(c.deviceUsage(c.deviceId)),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              for (final device in remote) ...[
                const Divider(indent: 18, endIndent: 18),
                ListTile(
                  leading: const Icon(Icons.devices_outlined, size: 23),
                  title: Text(device['label'] as String),
                  subtitle: Text(
                    'Last contacted: ${_contactTime(device['last_seen_at'] as String?)}\nMay have unsynced activity.',
                  ),
                  trailing: Text(
                    durationLabel(c.deviceUsage(device['id'] as String)),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (remote.isEmpty)
          _empty(
            'No other devices connected',
            'Sign in and sync usage on your other device to see it here.',
          ),
      ],
    );
  }

  String _contactTime(String? value) {
    final instant = value == null ? null : DateTime.tryParse(value);
    if (instant == null) return 'Unknown';
    final local = tz.TZDateTime.from(instant, c.location);
    return '${local.day} ${_months[local.month - 1]} at ${_time(instant)}';
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('Settings'),
      _Section(
        padding: const EdgeInsets.all(20),
        child: TrackingHealthPanel(
          controller: c,
          onTracking: _busy || !c.tracker.supported ? null : _enableTracking,
          onBrowser: c.tracker.isWindows && c.browserBridge?.isListening == true
              ? _pairBrowser
              : null,
          onAppBlocking: c.tracker.isAndroid ? _enableAndroidBlocking : null,
          onInstantBlocking: c.tracker.isAndroid
              ? _enableInstantBlocking
              : null,
          onRules: () => setState(() => _page = 2),
        ),
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >=
                  800 *
                      math.max(
                        1,
                        MediaQuery.textScalerOf(context).scale(14) / 14,
                      )
              ? 2
              : 1;
          final width = (constraints.maxWidth - 20 * (columns - 1)) / columns;
          return Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              for (final card in _settingsCards())
                SizedBox(width: width, child: card),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      _notice(
        'Blocking helps you keep your own rules. It is not a lock: you can always turn it off, and your phone or PC may stop Grindset in the background.',
      ),
    ],
  );

  List<Widget> _settingsCards() => [
    // While tracking is off, the setup checklist above covers turning it on.
    if (c.trackingEnabled || !c.tracker.supported)
      _Section(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity tracking',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              !c.tracker.supported
                  ? 'Tracking needs Windows or Android.'
                  : !c.trackingEnabled
                  ? 'Off. Nothing is recorded.'
                  : !c.accessGranted
                  ? 'Waiting for permission.'
                  : c.tracker.isAndroid && !c.backgroundTrackingRunning
                  ? 'Stopped. Turn it on again to resume.'
                  : 'On. Grindset records which app is open and for how long.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (c.trackingInterruption != null) ...[
              const SizedBox(height: 12),
              Text(c.trackingInterruption!),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(c.dismissTrackingInterruption),
                child: const Text('Dismiss'),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || !c.tracker.supported
                      ? null
                      : _enableTracking,
                  child: Text(
                    c.trackingEnabled ? 'Permissions' : 'Turn on tracking',
                  ),
                ),
                if (c.trackingEnabled)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => c.disableTracking()),
                    child: const Text('Stop tracking'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Grindset never sees your screen, what you type, or page contents.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    _Section(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Budget warnings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            value: c.budgetWarningsEnabled,
            onChanged: _busy
                ? null
                : (value) => _run(() => c.setBudgetWarningsEnabled(value)),
          ),
          const Text(
            'A heads-up once a day when an app reaches 80% of its daily limit.',
          ),
          if (c.budgetWarningsNotice != null)
            Text(
              c.budgetWarningsNotice!,
              style: TextStyle(color: colors.error),
            ),
        ],
      ),
    ),
    if (c.completionAlerts != null) ...[
      _Section(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Timer notifications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              value: c.completionAlertsEnabled,
              onChanged: _busy
                  ? null
                  : (value) => _run(() => c.setCompletionAlertsEnabled(value)),
            ),
            const Text('Notify me when a focus or break timer ends.'),
            if (c.completionAlertsNotice != null) ...[
              const SizedBox(height: 12),
              Text(
                c.completionAlertsNotice!,
                style: TextStyle(color: colors.tertiary),
              ),
            ],
            if (c.completionAlertsEnabled) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => c.setCompletionAlertsEnabled(true)),
                child: const Text('Notification permission'),
              ),
            ],
          ],
        ),
      ),
    ],
    if (c.tracker.isWindows && c.browserBridge != null) ...[
      _Section(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Browser extension',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Pair Chrome or Edge to track and block websites. Only the site name is shared, never full addresses or page titles.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _pairBrowser,
                  child: const Text('Pair browser extension'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(c.browserBridge!.disconnect),
                  child: const Text('Disconnect browsers'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
    _Section(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timezone', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            'Daily limits reset at midnight in this timezone. Schedules use it too.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<String>(
              width: math.min(420, constraints.maxWidth),
              initialSelection: c.timezone,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 280,
              label: const Text('Timezone'),
              dropdownMenuEntries: [
                for (final zone
                    in (tz.timeZoneDatabase.locations.keys.toList()..sort()))
                  DropdownMenuEntry(value: zone, label: zone),
              ],
              onSelected: (zone) {
                if (zone != null) _run(() => c.setTimezone(zone));
              },
            ),
          ),
        ],
      ),
    ),
    _Section(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {c.themeMode},
              onSelectionChanged: (value) =>
                  _run(() => c.setThemeMode(value.single)),
            ),
          ),
        ],
      ),
    ),
    _Section(
      padding: const EdgeInsets.all(20),
      child: CloudPanel(
        controller: c,
        cloud: widget.cloud,
        onChanged: () => setState(() {}),
        resetDevice: widget.resetDevice == null ? null : _performReset,
      ),
    ),
    _Section(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data on this device',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Export a copy of your history and rules, or erase everything on this device. To switch accounts, export first, then reset.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || widget.exportData == null
                    ? null
                    : _exportData,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export data'),
              ),
              TextButton(
                onPressed: _busy || widget.resetDevice == null
                    ? null
                    : _resetDevice,
                style: TextButton.styleFrom(foregroundColor: colors.error),
                child: const Text('Reset this device'),
              ),
            ],
          ),
        ],
      ),
    ),
    const _Section(padding: EdgeInsets.all(20), child: UpdatesPanel()),
  ];

  Widget _blocked(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 28,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 22),
                Text(
                  '${displayName(c, c.blockedSource!)} is restricted',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                Text(
                  c.blockMessage ?? 'An active rule is blocking this app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: c.dismissBlock,
                  child: Text(
                    c.tracker.isWindows
                        ? 'Use other apps'
                        : 'Return to Grindset',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  c.tracker.isWindows
                      ? 'Restricted apps stay minimized. Other apps and Windows controls remain available.'
                      : 'Tracking stays on. Other restrictions remain active.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(String title, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 46),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(
          message,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    ),
  );

  Widget _notice(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: colors.tertiary,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}
