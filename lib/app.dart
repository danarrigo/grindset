import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_controller.dart';
import 'core/activity.dart';
import 'core/focus_session.dart';
import 'data/cloud_sync.dart';
import 'ui/appearance.dart';
import 'ui/cloud_panel.dart';
import 'ui/duration_dialog.dart';
import 'ui/rule_editor.dart';

String durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return '$minutes min';
  return minutes % 60 == 0
      ? '${minutes ~/ 60} hr'
      : '${minutes ~/ 60} hr ${minutes % 60} min';
}

String _clockLabel(Duration duration) {
  final seconds = duration.inSeconds;
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$remainder'
      : '${seconds ~/ 60}:$remainder';
}

class LockinApp extends StatelessWidget {
  const LockinApp({
    super.key,
    required this.controller,
    this.cloud,
    this.startupWarning,
    this.enableStartup,
    this.themeMode = ThemeMode.system,
  });
  final AppController controller;
  final CloudSync? cloud;
  final String? startupWarning;
  final Future<void> Function()? enableStartup;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lockin',
    debugShowCheckedModeBanner: false,
    theme: lockinTheme(Brightness.light),
    darkTheme: lockinTheme(Brightness.dark),
    themeMode: themeMode,
    home: _Home(
      controller: controller,
      cloud: cloud,
      startupWarning: startupWarning,
      enableStartup: enableStartup,
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({
    required this.controller,
    this.cloud,
    this.startupWarning,
    this.enableStartup,
  });
  final AppController controller;
  final CloudSync? cloud;
  final String? startupWarning;
  final Future<void> Function()? enableStartup;
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
        content: const SingleChildScrollView(
          child: Text(
            'Lockin reads foreground app identifiers and usage timestamps throughout the day. '
            'It does not read page titles, screenshots, keystrokes or window contents.\n\n'
            'Windows will start Lockin at sign-in and keep it in the tray. Android requires Usage Access in Settings. '
            'This permission does not enable Android app blocking.\n\n'
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

  Future<void> _editRule([ActivityRule? rule]) async {
    final result = await showDialog<ActivityRule>(
      context: context,
      builder: (_) => RuleEditor(
        rule: rule,
        sources: {
          ...c.usage.map((i) => i.source),
          ...c.rules.expand((r) => r.sources),
        },
      ),
    );
    if (result != null && mounted) await _run(() => c.saveRule(result));
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

  Future<void> _customDuration() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => DurationDialog(initialMinutes: _minutes),
    );
    if (result != null && mounted) {
      setState(() {
        _minutes = result;
        _configuringNext = true;
      });
    }
  }

  Future<void> _endSession() async {
    final yes = await showDialog<bool>(
      context: context,
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

  void _buildStatus() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview build'),
        content: const SingleChildScrollView(
          child: Text(
            'Timers, local storage and usage accounting are implemented.\n\n'
            'Windows foreground tracking and interruption-based blocking still need native device testing. '
            'Idle/media handling and crash recovery are unfinished.\n\n'
            'Android imports OS usage history while open. Native blocking and a persistent background journal are not connected.\n\n'
            'Website integration and shared session, rule and timezone sync are not connected. Usage sync is manual.\n\n'
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
  String get _today {
    final local = tz.TZDateTime.from(c.now, c.location);
    final weekday = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][local.weekday - 1];
    return '$weekday, ${local.day} ${_months[local.month - 1]}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final desktop =
          MediaQuery.sizeOf(context).width >= 760 * math.max(1, textScale);
      final dark = Theme.of(context).brightness == Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Theme.of(context)
                  .scaffoldBackgroundColor,
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
                    _toolbar(desktop),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final padding = desktop ? 32.0 : 20.0;
                          return SingleChildScrollView(
                            key: ValueKey('page-$_page'),
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
                                mainAxisAlignment: _page == 0
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: _page == 0 ? 430 : 760,
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
                                          0 => _focus(),
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
                if (c.blockedSource != null) Positioned.fill(child: _blocked()),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : CupertinoTabBar(
                  currentIndex: _page,
                  onTap: (index) => setState(() => _page = index),
                  height: 58,
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
    },
  );

  Widget _toolbar(bool desktop) {
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
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 32 : 20,
        vertical: 10,
      ),
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
                    'Lockin',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
                if (desktop)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        Semantics(
                          selected: _page == i,
                          child: TextButton(
                            key: ValueKey('nav-$i'),
                            onPressed: () => setState(() => _page = i),
                            style: TextButton.styleFrom(
                              foregroundColor: _page == i
                                  ? colors.onSurface
                                  : colors.onSurfaceVariant,
                            ),
                            child: Text(
                              _pages[i],
                              style: TextStyle(
                                fontWeight: _page == i
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: desktop ? 170 : 180),
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

  Widget _focus() {
    final active = c.session;
    final running = active?.running(c.now) ?? false;
    final completed =
        active != null && !c.now.isBefore(active.end) && !_configuringNext;
    final phase = running ? active!.phase : _phase;
    final limits =
        c.rules
            .where((r) => r.dailyMinutes != null)
            .map(
              (rule) => (
                rule: rule,
                remaining:
                    Duration(minutes: rule.dailyMinutes!) - c.ruleUsage(rule),
              ),
            )
            .toList()
          ..sort((a, b) => a.remaining.compareTo(b.remaining));
    final nearest = limits.firstOrNull;
    final budgetValue = nearest == null
        ? 'None set'
        : nearest.remaining <= Duration.zero
        ? 'Limit reached'
        : nearest.remaining.inMinutes == 0
        ? '<1 min left'
        : '${durationLabel(nearest.remaining)} left';
    final hint = !c.tracker.isWindows
        ? 'Timer only. App blocking is not connected yet.'
        : !c.trackingEnabled || !c.accessGranted
        ? 'Enable tracking to apply Windows blocking rules.'
        : 'Windows app blocking is experimental.';

    return Column(
      children: [
        Text(
          completed
              ? 'Session complete'
              : phase == SessionPhase.focus
              ? 'Focus'
              : 'Break',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          running ? 'Ends at ${_time(active!.end)}' : _today,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 30),
        if (!running) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: CupertinoSlidingSegmentedControl<SessionPhase>(
              groupValue: _phase,
              backgroundColor: colors.surfaceContainerHighest,
              thumbColor: colors.surface,
              padding: const EdgeInsets.all(3),
              children: {
                for (final value in SessionPhase.values)
                  value: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: Text(
                      value == SessionPhase.focus ? 'Focus' : 'Break',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: colors.onSurface,
                        fontWeight: _phase == value
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              },
              onValueChanged: (value) {
                if (value != null) {
                  setState(() {
                    _phase = value;
                    _minutes = c.preferredMinutes(value);
                    _configuringNext = true;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (running || completed) ...[
          Semantics(
            label: 'Time remaining',
            value: _clockLabel(
              completed ? Duration.zero : active!.remaining(c.now),
            ),
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _clockLabel(
                    completed ? Duration.zero : active.remaining(c.now),
                  ),
                  style: const TextStyle(
                    fontSize: 76,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -3,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (!running) ...[_durationPicker(), const SizedBox(height: 18)],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: running
                ? OutlinedButton(
                    onPressed: _busy ? null : _endSession,
                    child: const Text('End session'),
                  )
                : FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await c.startSession(
                              Duration(minutes: _minutes),
                              _phase,
                            );
                            if (mounted) {
                              setState(() => _configuringNext = false);
                            }
                          }),
                    child: Text(
                      _phase == SessionPhase.focus ? 'Lock in' : 'Start break',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 38),
        const Divider(),
        const SizedBox(height: 24),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _metric('Focused today', durationLabel(c.focusedToday)),
              ),
              VerticalDivider(
                width: 28,
                thickness: .5,
                color: colors.outlineVariant,
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _page = 2),
                  borderRadius: BorderRadius.circular(8),
                  child: _metric(
                    nearest == null ? 'Daily limits' : 'Closest limit',
                    budgetValue,
                    detail: nearest?.rule.name,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _durationPicker() {
    final presets = {
      ...(_phase == SessionPhase.focus ? [25, 45, 60] : [5, 10, 15]),
      _minutes,
    }.toList()..sort();
    return PopupMenuButton<int>(
      key: const ValueKey('duration-picker'),
      tooltip: 'Change duration',
      initialValue: _minutes,
      onSelected: (value) {
        if (value == -1) {
          _customDuration();
        } else {
          setState(() {
            _minutes = value;
            _configuringNext = true;
          });
        }
      },
      itemBuilder: (_) => [
        for (final value in presets)
          PopupMenuItem(
            value: value,
            child: Row(
              children: [
                Text('$value min'),
                const SizedBox(width: 32),
                if (value == _minutes)
                  Icon(Icons.check_rounded, size: 18, color: colors.primary),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: -1, child: Text('Custom duration...')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_minutes min',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w500,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 19,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {String? detail}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w500,
            letterSpacing: -.4,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ],
    ),
  );

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
        _heading('Activity', subtitle: 'This device today · ${c.timezone}'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total usage',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            Text(
              durationLabel(c.deviceUsage(c.deviceId)),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 18),
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

  Widget _rules() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'Rules',
        subtitle: 'Focus blocks, daily limits and schedules.',
        action: TextButton.icon(
          onPressed: () => _editRule(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add activity'),
        ),
      ),
      if (!c.tracker.isWindows) ...[
        _notice('Native app blocking is not connected on this platform yet.'),
        const SizedBox(height: 20),
      ],
      if (c.rules.isEmpty)
        _empty(
          'No activities added',
          'Add an activity to choose which apps to restrict and when.',
        ),
      if (c.rules.isNotEmpty)
        _Section(
          child: Column(
            children: [
              for (var i = 0; i < c.rules.length; i++) ...[
                if (i > 0) const Divider(indent: 18, endIndent: 18),
                ListTile(
                  onTap: () => _editRule(c.rules[i]),
                  title: Text(c.rules[i].name),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      [
                        if (c.rules[i].focusBlock) 'During focus',
                        if (c.rules[i].dailyMinutes != null)
                          '${durationLabel(c.ruleUsage(c.rules[i]))} of ${c.rules[i].dailyMinutes} min today',
                        if (c.rules[i].schedules.isNotEmpty) 'Scheduled',
                      ].join(' · '),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Options for ${c.rules[i].name}',
                    icon: const Icon(Icons.more_horiz_rounded, size: 21),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editRule(c.rules[i]);
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
              ],
            ],
          ),
        ),
      const SizedBox(height: 20),
      Text(
        'Any active restriction can block an activity. Breaks pause focus rules only.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

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
                  : c.accessGranted
                  ? 'Usage access is available.'
                  : 'Waiting for system permission.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy || !c.tracker.supported ? null : _enableTracking,
              child: Text(
                c.trackingEnabled ? 'Review permission' : 'Enable tracking',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No screenshots, page titles or keystrokes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _Section(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timezone', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              'Daily limits and schedules use this day boundary. Account-wide timezone sync is pending.',
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
      const SizedBox(height: 18),
      _Section(
        padding: const EdgeInsets.all(20),
        child: CloudPanel(
          controller: c,
          cloud: widget.cloud,
          onChanged: () => setState(() {}),
        ),
      ),
      const SizedBox(height: 24),
      _notice(
        'This build is not ready for continuous background enforcement. Android blocking, persistent journaling, browser integration and shared timer/rule sync are unfinished. Windows idle handling and crash recovery need work.',
      ),
    ],
  );

  Widget _blocked() => Material(
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
                child: const Text('Return to Lockin'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _run(c.overrideBlock),
                child: const Text('Allow this app for 5 minutes'),
              ),
              const SizedBox(height: 20),
              Text(
                'Tracking stays on. Other restrictions remain active.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
          style: TextStyle(fontSize: 12, color: colors.tertiary, height: 1.6),
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
