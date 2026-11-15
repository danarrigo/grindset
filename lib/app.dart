import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_controller.dart';
import 'core/activity.dart';
import 'core/focus_session.dart';
import 'core/rule_presets.dart';
import 'data/cloud_sync.dart';
import 'ui/appearance.dart';
import 'ui/cloud_panel.dart';
import 'ui/duration_dialog.dart';
import 'ui/desktop_shell.dart';
import 'ui/focus_screen.dart';
import 'ui/schedule_summary.dart';
import 'platform/windows_apps.dart';
import 'ui/rule_editor.dart';
import 'ui/rule_starters.dart';
import 'ui/updates_panel.dart';
import 'ui/tracking_health_panel.dart';
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
    this.themeMode = ThemeMode.system,
  });
  final AppController controller;
  final CloudSync? cloud;
  final String? startupWarning;
  final Future<void> Function()? enableStartup;
  final Future<bool> Function()? exportData;
  final Future<void> Function()? resetDevice;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Grindset',
    debugShowCheckedModeBanner: false,
    theme: lockinTheme(Brightness.light),
    darkTheme: lockinTheme(Brightness.dark),
    themeMode: themeMode,
    home: _Home(
      controller: controller,
      cloud: cloud,
      startupWarning: startupWarning,
      enableStartup: enableStartup,
      exportData: exportData,
      resetDevice: resetDevice,
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
        title: const Text('Enable activity tracking?'),
        content: SingleChildScrollView(
          child: Text(
            'Grindset reads foreground app identifiers and usage timestamps throughout the day. '
            'It does not read page titles, screenshots, keystrokes or window contents.\n\n'
            '${c.tracker.isWindows && widget.enableStartup == null ? 'This isolated preview does not change Windows sign-in startup.' : 'Windows will start Grindset at sign-in and keep it in the tray.'} '
            'Android requires Usage Access and notifications, '
            'then keeps a visible background service running when you close the UI. You can stop it from Settings or its notification. '
            'App blocking requires a separate, optional Accessibility permission.\n\n'
            'History is stored locally. Cloud uploads require configured Supabase and sign-in.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable tracking'),
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
        title: const Text('Enable app blocking?'),
        content: const SingleChildScrollView(
          child: Text(
            'Grindset uses Accessibility only to identify the foreground app package and display a blocking screen when one of your rules applies. '
            'It does not read screen contents, typed text, screenshots or keystrokes.\n\n'
            'This is voluntary enforcement. You can disable Accessibility, stop tracking or uninstall Grindset at any time. Android Settings remains accessible.\n\n'
            'After continuing, choose Grindset app blocking in Android Accessibility settings and enable it yourself.',
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
    await _run(() async {
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
    });
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

  Future<void> _editRule({
    ActivityRule? rule,
    RulePreset? preset,
    bool scheduledFocus = false,
  }) async {
    final baseRevision = rule == null ? 0 : c.ruleRevision(rule.id);
    final result = await showDialog<ActivityRule>(
      context: context,
      builder: (_) => RuleEditor(
        rule: rule,
        preset: preset,
        scheduledFocus: scheduledFocus,
        timezone: c.location.name,
        loadWindowsApps: c.tracker.isWindows ? WindowsApps.list : null,
        browseWindowsApp: c.tracker.isWindows ? WindowsApps.browse : null,
        sources: {
          ...c.usage.map((i) => i.source),
          ...c.rules.expand((r) => r.sources),
        },
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

  void _buildStatus([BuildContext? dialogContext]) {
    showDialog<void>(
      context: dialogContext ?? context,
      builder: (context) => AlertDialog(
        title: const Text('Preview build'),
        content: const SingleChildScrollView(
          child: Text(
            'Timers, local storage and usage accounting are implemented.\n\n'
            'Windows foreground tracking and interruption-based blocking still need native device testing. '
            'The idle/media probe needs native validation; crash recovery is unfinished.\n\n'
            'Android uses an opt-in foreground service and a persistent background journal. '
            'App blocking requires the separate Accessibility service. Both remain subject to Android stopping the process or permissions being revoked.\n\n'
            'Windows websites require the paired Chrome/Edge extension. Account state and confirmed usage sync automatically while signed in. Offline rule conflicts require review; the confirmed shared focus session wins.\n\n'
            'No activity is invented for disconnected devices.',
          ),
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
                                const SizedBox(height: 28),
                                TextButton(
                                  onPressed: _buildStatus,
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.onSurfaceVariant,
                                  ),
                                  child: const Text(
                                    'Preview build',
                                    style: TextStyle(fontSize: 12),
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
        bottomNavigationBar: desktop
            ? null
            : CupertinoTabBar(
                currentIndex: _page,
                onTap: (index) => setState(() => _page = index),
                height: math.max(
                  58.0,
                  46 + MediaQuery.textScalerOf(context).scale(12),
                ),
                activeColor: colors.onSurface,
                inactiveColor: colors.onSurfaceVariant,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: colors.outlineVariant, width: .5),
                ),
                iconSize: 22,
                items: [
                  for (var i = 0; i < _pages.length; i++)
                    BottomNavigationBarItem(
                      icon: Icon(_icons[i], key: ValueKey('nav-$i')),
                      label: _pages[i],
                    ),
                ],
              ),
      ),
    );
  }

  Widget _focusHome() {
    final theme = lockinTheme(
      Brightness.dark,
      accent: const Color(0xFFFF9F0A),
    ).copyWith(scaffoldBackgroundColor: const Color(0xFF09090A));
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final status = c.trackingError != null
        ? 'Tracking interrupted'
        : !c.tracker.supported
        ? 'Timer only'
        : !c.trackingEnabled
        ? 'Tracking off'
        : !c.accessGranted
        ? 'Permission needed'
        : 'Usage access on';
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
                          c.trackingError != null
                              ? Icons.error_outline_rounded
                              : Icons.circle_outlined,
                          size: 13,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: c.trackingError != null
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
    final phase = running ? active!.phase : _phase;
    final warnings = [
      widget.startupWarning,
      c.trackingError,
      if (c.trackingInterruption != null)
        'A tracking interruption needs review in Settings.',
    ].nonNulls;
    return FocusScreen(
      showBrand: !_desktopLayout,
      menuButtonKey: _focusMenuKey,
      remaining: completed
          ? Duration.zero
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
      status: completed ? 'Session complete' : null,
      warning: warnings.isEmpty ? null : warnings.join('\n\n'),
      buildLabel:
          c.trackingEnabled &&
              c.accessGranted &&
              (c.tracker.isWindows ||
                  (c.backgroundTrackingRunning && c.androidBlockingEnabled))
          ? 'Preview build'
          : 'Timer only · Preview build',
      onStatus: () => _buildStatus(context),
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
                  if (!_desktopLayout)
                    for (var i = 1; i < _pages.length; i++)
                      CupertinoActionSheetAction(
                        key: ValueKey('nav-$i'),
                        onPressed: () => Navigator.pop(sheetContext, i),
                        child: Text(_pages[i], style: textStyle),
                      ),
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
            ? 'Recorded insights on this device'
            : 'This device today · ${c.timezone}',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        for (final (label, value) in [
          ('Total usage', c.deviceUsage(c.deviceId)),
          ('Focused today', c.focusedToday),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    durationLabel(value),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
        const Divider(),
        if (totals.isEmpty)
          _empty(
            'No activity yet',
            'Enable tracking to see time spent in foreground apps.',
          ),
        for (final item in totals)
          Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: Icon(
                  Icons.apps_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                title: Text(sourceName(item.source)),
                trailing: Text(
                  durationLabel(item.used),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Divider(),
            ],
          ),
        if (totals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              'Foreground usage only. Focus time and device usage are reported separately.',
              style: Theme.of(context).textTheme.bodySmall,
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
          _empty('No saved rules', 'Choose a starter or add your own activity.')
        else
          _savedRules(),
      ],
    );
    final starters = RuleStarters(
      rules: c.rules,
      onSelected: (preset) => _editRule(preset: preset),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Rules',
          subtitle: 'Control apps and websites across your devices.',
          action: TextButton.icon(
            onPressed: () => _editRule(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add activity'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _editRule(scheduledFocus: true),
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text('Schedule focus hours'),
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
        if (!c.trackingEnabled) ...[
          _notice(
            'Tracking is off. Enable tracking in Settings to enforce these rules.',
          ),
          const SizedBox(height: 20),
        ],
        if (c.tracker.isAndroid && !c.androidBlockingEnabled) ...[
          _notice(
            'Android app blocking also needs the Accessibility permission in Settings.',
          ),
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
                    children: [saved, const SizedBox(height: 24), starters],
                  );
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Any active restriction can block an activity. Existing individual limits still apply alongside a combined rule.',
          style: Theme.of(context).textTheme.bodySmall,
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
            ListTile(
              onTap: () => _editRule(rule: c.rules[i]),
              title: Text(c.rules[i].name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    [
                      if (c.rules[i].sources.any(
                        (s) => s.startsWith('windows:'),
                      ))
                        'Windows apps',
                      if (c.rules[i].sources.any((s) => s.startsWith('web:')))
                        'Websites',
                      if (c.rules[i].sources.any(
                        (s) => s.startsWith('android:'),
                      ))
                        'Android apps',
                    ].join(' + '),
                    if (c.rules[i].focusBlock) 'During focus',
                    if (c.rules[i].dailyMinutes != null)
                      '${durationLabel(c.ruleUsage(c.rules[i]))} of ${c.rules[i].dailyMinutes} min today',
                    for (final window in c.rules[i].schedules.take(2))
                      scheduleSummary(context, window),
                    if (c.rules[i].schedules.length > 2)
                      '+${c.rules[i].schedules.length - 2} more windows',
                    if (c.rules[i].schedules.isNotEmpty) c.location.name,
                  ].join(' · '),
                ),
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Options for ${c.rules[i].name}',
                icon: const Icon(Icons.more_horiz_rounded, size: 21),
                onSelected: (value) {
                  if (value == 'edit') {
                    _editRule(rule: c.rules[i]);
                  } else {
                    _deleteRule(c.rules[i]);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
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
          onAccessibility: c.tracker.isAndroid ? _enableAndroidBlocking : null,
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
        'Background operation and blocking are experimental and can be interrupted by the OS, force-stop or permission revocation. Website blocking needs the paired extension. Enforcement is voluntary, not tamper-proof.',
      ),
    ],
  );

  List<Widget> _settingsCards() => [
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
                ? 'Native tracking requires Windows or Android.'
                : !c.trackingEnabled
                ? 'Not enabled. No usage is being collected.'
                : !c.accessGranted
                ? 'Waiting for system permission.'
                : c.tracker.isAndroid
                ? c.backgroundTrackingRunning
                      ? 'Background service is running.'
                      : 'Background service is stopped.'
                : 'Foreground activity tracking is enabled.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (c.trackingInterruption != null) ...[
            const SizedBox(height: 12),
            Text(c.trackingInterruption!),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(c.dismissTrackingInterruption),
              child: const Text('Dismiss interruption notice'),
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
                  c.trackingEnabled ? 'Review permission' : 'Enable tracking',
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
            'No screenshots, page titles or keystrokes.',
            style: Theme.of(context).textTheme.bodySmall,
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
              title: const Text('Completion notifications'),
              value: c.completionAlertsEnabled,
              onChanged: _busy
                  ? null
                  : (value) => _run(() => c.setCompletionAlertsEnabled(value)),
            ),
            const Text(
              'An OS-scheduled alert when your focus or break timer finishes. This does not enable activity tracking or start the next phase.',
            ),
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
                child: const Text('Review notification permission'),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Delivery depends on OS notification settings and battery restrictions. Android exact alarms need separate permission; otherwise alerts may arrive late.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
              'Pair Chrome or Edge to track foreground website hosts and apply your website rules. No titles, paths, queries or complete URLs are sent.',
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
            const SizedBox(height: 12),
            Text(
              'The native app and extension must remain connected for website blocking. Internet access is not required for local rules.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ],
    if (c.tracker.isAndroid) ...[
      _Section(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App blocking', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              c.androidBlockingEnabled
                  ? 'Accessibility service is connected. Tracking must also be enabled for rules to apply.'
                  : 'Not enabled. Usage Access alone cannot block apps.',
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy ? null : _enableAndroidBlocking,
              child: Text(
                c.androidBlockingEnabled
                    ? 'Review Accessibility'
                    : 'Enable app blocking',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Package identifiers only, never screen contents. This is voluntary and can be disabled in Android Settings.',
              style: Theme.of(context).textTheme.bodySmall,
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
            'Daily limits and schedules use this account timezone. It synchronizes while signed in; offline changes reconcile on connection.',
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
      child: CloudPanel(
        controller: c,
        cloud: widget.cloud,
        onChanged: () => setState(() {}),
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
            'Signing out keeps local history linked to its original account. To use a different account, export what you need, then reset this device and reopen Grindset.',
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
          const SizedBox(height: 12),
          Text(
            'The JSON archive includes history, rules and saved offline edits, but no auth credentials or browser pairing keys. It contains private app/domain identifiers and timestamps; store it securely.',
            style: Theme.of(context).textTheme.bodySmall,
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
                  '${sourceName(c.blockedSource!)} is restricted',
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
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => _run(c.overrideBlock),
                  child: const Text('Allow this app for 5 minutes'),
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
