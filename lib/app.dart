import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_controller.dart';
import 'core/activity.dart';
import 'core/focus_session.dart';
import 'data/cloud_sync.dart';
import 'ui/cloud_panel.dart';
import 'ui/duration_dialog.dart';
import 'ui/rule_editor.dart';

const _green = Color(0xFFC0F299);
const _muted = Color(0xFF99A8B4);
const _panel = Color(0xFF151E27);
const _background = Color(0xFF0C1116);

String durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  return minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';
}

String _clockLabel(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds >= 3600) {
    return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class LockinApp extends StatelessWidget {
  const LockinApp({
    super.key,
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lockin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        primary: _green,
        onPrimary: _background,
        surface: _panel,
        onSurface: Color(0xFFEAF0F4),
        secondary: _green,
      ),
      dividerColor: const Color(0xFF29343D),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF34434E)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: 'Inter',
        bodyColor: const Color(0xFFEAF0F4),
        displayColor: const Color(0xFFEAF0F4),
      ),
    ),
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
  var _page = 0;
  var _minutes = 25;
  var _phase = SessionPhase.focus;
  bool _busy = false;
  bool _configuringNext = false;

  @override
  void initState() {
    super.initState();
    final previous = c.session;
    if (previous != null) {
      _phase = previous.phase;
      _minutes = previous.end
          .difference(previous.start)
          .inMinutes
          .clamp(1, 1440);
    }
  }

  static const _pages = ['Focus', 'Activity', 'Rules', 'Devices', 'Settings'];
  static const _icons = [
    Icons.center_focus_strong_rounded,
    Icons.bar_chart_rounded,
    Icons.shield_outlined,
    Icons.devices_rounded,
    Icons.tune_rounded,
  ];

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
            'Your history is stored locally. Cloud uploads require configured Supabase and sign-in.',
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
    final confirm = await showDialog<bool>(
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
    if (confirm == true && mounted) await _run(c.endSession);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final desktop = MediaQuery.sizeOf(context).width >= 900;
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (desktop) _sidebar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(desktop ? 32 : 18),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!desktop)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _brand(),
                                ),
                              _header(desktop),
                              const SizedBox(height: 28),
                              if (widget.startupWarning != null) ...[
                                _notice(widget.startupWarning!),
                                const SizedBox(height: 16),
                              ],
                              if (c.trackingError != null) ...[
                                _notice(c.trackingError!),
                                const SizedBox(height: 16),
                              ],
                              switch (_page) {
                                0 => _focus(desktop),
                                1 => _activity(),
                                2 => _rules(),
                                3 => _devices(),
                                _ => _settings(),
                              },
                              const SizedBox(height: 24),
                              const Text(
                                'LOCAL-FIRST BY DESIGN',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
            : NavigationBar(
                selectedIndex: _page,
                backgroundColor: _panel,
                indicatorColor: _green.withValues(alpha: .14),
                onDestinationSelected: (v) => setState(() => _page = v),
                destinations: [
                  for (var i = 0; i < _pages.length; i++)
                    NavigationDestination(
                      icon: Icon(_icons[i]),
                      label: _pages[i],
                    ),
                ],
              ),
      );
    },
  );

  Widget _brand() => const Row(
    children: [
      Icon(Icons.center_focus_strong_rounded, color: _green, size: 30),
      SizedBox(width: 10),
      Text(
        'lockin',
        style: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: -.9,
        ),
      ),
    ],
  );

  Widget _sidebar() => Container(
    width: 216,
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: Color(0xFF25303A))),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 42),
          child: _brand(),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 12),
          child: Text(
            'YOUR SPACE',
            style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.8),
          ),
        ),
        for (var i = 0; i < _pages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(_icons[i], size: 21),
              title: Text(_pages[i], style: const TextStyle(fontSize: 14)),
              selected: _page == i,
              selectedColor: _green,
              selectedTileColor: _green.withValues(alpha: .09),
              onTap: () => setState(() => _page = i),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 17, color: _green),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your time, your data',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Stored on your device first.',
                      style: TextStyle(fontSize: 10, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _header(bool desktop) {
    final date = tz.TZDateTime.from(c.now, c.location);
    final day = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][date.weekday - 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$day / ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}',
          style: const TextStyle(
            fontSize: 12,
            color: _muted,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          [
            'Your time. On purpose.',
            'See where your day goes.',
            'Make distraction a decision.',
            'One person. Every device.',
            'Make Lockin yours.',
          ][_page],
          style: TextStyle(
            fontSize: desktop ? 32 : 25,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -.9,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              _page == 0
                  ? 'One clear intention. A little less noise.'
                  : 'Today in ${c.timezone}',
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
            if (_page == 0)
              InkWell(
                onTap: () => setState(() => _page = 4),
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: c.accessGranted && c.trackingEnabled
                          ? _green
                          : const Color(0xFFE6BD78),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      c.accessGranted && c.trackingEnabled
                          ? 'Tracking enabled'
                          : 'Tracking setup required',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _focus(bool desktop) {
    final timer = _timerCard();
    final summary = Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TODAY, DELIBERATELY',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                durationLabel(c.focusedToday),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.5,
                ),
              ),
              const Text(
                'in focus sessions',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const Divider(height: 36),
              Row(
                children: [
                  const Icon(Icons.devices_rounded, color: _muted, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${durationLabel(c.deviceUsage(c.deviceId))} usage on this device',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: _green, size: 25),
              const SizedBox(height: 16),
              Text(
                c.rules.isEmpty
                    ? 'Set your boundaries.'
                    : '${c.rules.length} activity rules',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                c.rules.isEmpty
                    ? 'Choose the apps you want a little distance from. You stay in control.'
                    : 'Session blocks, daily budgets, and schedules live here.',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _page = 2),
                child: Text(
                  c.rules.isEmpty ? 'Set up activities' : 'Manage activities',
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      children: [
        if (desktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: timer),
              const SizedBox(width: 22),
              SizedBox(width: 272, child: summary),
            ],
          )
        else ...[
          timer,
          const SizedBox(height: 18),
          summary,
        ],
        const SizedBox(height: 18),
        _notice(
          'Build checkpoint: timers and local accounting are working. Windows interruption-based blocking is experimental. Android blocking, browser integration and shared session/rule sync are not connected yet.',
          icon: Icons.construction_rounded,
        ),
      ],
    );
  }

  Widget _timerCard() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final active = c.session;
    final running = active?.running(c.now) ?? false;
    final completed =
        active != null && !c.now.isBefore(active.end) && !_configuringNext;
    final phase = running ? active!.phase : _phase;
    final remaining = completed
        ? Duration.zero
        : running
        ? active!.remaining(c.now)
        : Duration(minutes: _minutes);
    final total = running
        ? active!.end.difference(active.start)
        : Duration(minutes: _minutes);
    final value = (remaining.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    return _Panel(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.circle, color: _green, size: 7),
              const SizedBox(width: 8),
              Text(
                completed
                    ? 'SESSION COMPLETE'
                    : running
                    ? 'IN YOUR FOCUS ZONE'
                    : 'A FRESH START',
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.6,
                  color: _muted,
                ),
              ),
              const Spacer(),
              const Icon(Icons.more_time_rounded, color: _muted, size: 20),
            ],
          ),
          const SizedBox(height: 24),
          SegmentedButton<SessionPhase>(
            segments: const [
              ButtonSegment(
                value: SessionPhase.focus,
                label: Text('Focus'),
                icon: Icon(Icons.bolt_rounded, size: 16),
              ),
              ButtonSegment(
                value: SessionPhase.rest,
                label: Text('Break'),
                icon: Icon(Icons.coffee_rounded, size: 16),
              ),
            ],
            selected: {phase},
            onSelectionChanged: running
                ? null
                : (v) => setState(() {
                    _phase = v.first;
                    _minutes = _phase == SessionPhase.focus ? 25 : 5;
                    _configuringNext = true;
                  }),
          ),
          SizedBox(height: compact ? 24 : 30),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(
                compact ? 220.0 : 260.0,
                constraints.maxWidth - 8,
              );
              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 5,
                        backgroundColor: const Color(0xFF2C3A43),
                        strokeCap: StrokeCap.round,
                        semanticsLabel:
                            'Time remaining: ${remaining.inMinutes} minutes ${remaining.inSeconds % 60} seconds',
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _clockLabel(remaining),
                          style: TextStyle(
                            fontSize:
                                size *
                                (_clockLabel(remaining).length > 5 ? .16 : .23),
                            fontWeight: FontWeight.w500,
                            letterSpacing: -2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          phase == SessionPhase.focus
                              ? 'Make this time yours.'
                              : 'Give your mind some room.',
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: compact ? 20 : 28),
          if (!running)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 4,
              children: [
                for (final value
                    in (_phase == SessionPhase.focus
                        ? [25, 45, 60]
                        : [5, 10, 15]))
                  ChoiceChip(
                    label: Text(
                      '${value}m',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _minutes == value,
                    onSelected: (_) => setState(() {
                      _minutes = value;
                      _configuringNext = true;
                    }),
                  ),
                ActionChip(
                  label: const Text('Custom', style: TextStyle(fontSize: 12)),
                  onPressed: _customDuration,
                ),
              ],
            )
          else
            Text(
              '${active!.label} / ${durationLabel(total)}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: running
                ? OutlinedButton.icon(
                    onPressed: _busy ? null : _endSession,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('End session'),
                  )
                : FilledButton.icon(
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
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      _phase == SessionPhase.focus
                          ? 'Start focus'
                          : 'Start break',
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            completed
                ? 'Session complete. Choose your next phase when ready.'
                : running
                ? 'The timer keeps its deadline when this window closes.'
                : 'No auto-start. Begin when you are ready.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _activity() {
    final totals = <String, Duration>{};
    for (final source
        in c.usage
            .where((i) => i.deviceId == c.deviceId)
            .map((i) => i.source)
            .toSet()) {
      totals[source] = combinedUsage(
        c.usage.where((i) => i.deviceId == c.deviceId && i.source == source),
        from: accountDay(c.now, c.location).$1,
        until: c.now,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'This device today',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                durationLabel(c.deviceUsage(c.deviceId)),
                style: const TextStyle(fontSize: 20, color: _green),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Foreground apps only. Device totals are never added to your focus-session duration.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          if (sorted.isEmpty)
            _empty(
              Icons.bar_chart_rounded,
              'A clear slate.',
              'Your real app usage will appear here after tracking is enabled.',
            ),
          for (final entry in sorted)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.apps_rounded, size: 20, color: _muted),
                      const SizedBox(width: 12),
                      Expanded(child: Text(sourceName(entry.key))),
                      Text(
                        durationLabel(entry.value),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: c.deviceUsage(c.deviceId).inSeconds > 0
                          ? (entry.value.inSeconds /
                                    c.deviceUsage(c.deviceId).inSeconds)
                                .clamp(0.0, 1.0)
                          : 0,
                      backgroundColor: const Color(0xFF26333D),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rules() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => _editRule(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add activity'),
          ),
          const Text(
            'Any active rule can block. Breaks do not lift daily limits.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (!c.tracker.isWindows) ...[
        _notice(
          'Rule accounting is available. Native app blocking on this platform is not connected yet.',
        ),
        const SizedBox(height: 18),
      ],
      if (c.rules.isEmpty)
        _Panel(
          child: _empty(
            Icons.shield_outlined,
            'A little structure goes a long way.',
            'Create an activity, choose its apps, and set the boundaries that help you.',
          ),
        ),
      for (final rule in c.rules)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: _green, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        rule.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit ${rule.name}',
                      onPressed: () => _editRule(rule),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Delete ${rule.name}',
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Delete ${rule.name}?'),
                            content: const Text(
                              'Its restrictions will no longer apply.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true && mounted) {
                          await _run(() => c.deleteRule(rule.id));
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  rule.sources.map(sourceName).join(' / '),
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (rule.focusBlock)
                      const Chip(
                        label: Text(
                          'Focus block',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    if (rule.dailyMinutes != null)
                      Chip(
                        label: Text(
                          '${durationLabel(c.ruleUsage(rule))} / ${rule.dailyMinutes}m daily',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    if (rule.schedules.isNotEmpty)
                      const Chip(
                        label: Text(
                          'Scheduled',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _devices() {
    final remote =
        widget.cloud?.devices.where((d) => d['id'] != c.deviceId).toList() ??
        [];
    return Column(
      children: [
        _Panel(
          child: Row(
            children: [
              Icon(
                c.tracker.isAndroid
                    ? Icons.phone_android_rounded
                    : Icons.desktop_windows_outlined,
                color: _green,
                size: 32,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This device',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.tracker.isWindows
                          ? 'Windows'
                          : c.tracker.isAndroid
                          ? 'Android'
                          : 'Unsupported tracking platform',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                durationLabel(c.deviceUsage(c.deviceId)),
                style: const TextStyle(fontSize: 22),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (remote.isEmpty)
          _Panel(
            child: _empty(
              Icons.devices_rounded,
              'A place for your other device.',
              'Configure Supabase and sync usage on both devices. No device is marked live without confirmed data.',
            ),
          ),
        for (final device in remote)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device['label'] as String,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${durationLabel(c.deviceUsage(device['id'] as String))} confirmed today',
                    style: const TextStyle(color: _green),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Last contacted: ${device['last_seen_at']}',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  const Text(
                    'May have unsynced activity. No activity is inferred after its last observation.',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activity tracking',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              !c.tracker.supported
                  ? 'Native tracking is available on Windows and Android only.'
                  : !c.trackingEnabled
                  ? 'Not enabled. No usage is being collected.'
                  : c.accessGranted
                  ? 'Usage access is available.'
                  : 'Waiting for system permission.',
              style: const TextStyle(color: _muted, height: 1.6),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || !c.tracker.supported ? null : _enableTracking,
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(
                c.trackingEnabled
                    ? 'Review tracking permission'
                    : 'Enable tracking',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No screenshots. No page titles. No keystrokes.',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 8),
            const Text(
              'Checkpoint: Windows idle/media handling and crash recovery still need work. Android imports OS usage history when open; a persistent journal and native blocking are not implemented yet.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFE6BD78),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Day boundaries',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Daily budgets and schedules use this timezone. Account-wide synchronization is pending.',
              style: TextStyle(color: _muted, fontSize: 12),
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
      _Panel(
        child: CloudPanel(
          controller: c,
          cloud: widget.cloud,
          onChanged: () => setState(() {}),
        ),
      ),
    ],
  );

  Widget _blocked() => Material(
    color: _background.withValues(alpha: .98),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, color: _green, size: 56),
              const SizedBox(height: 26),
              Text(
                '${sourceName(c.blockedSource!)} can wait.',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                c.blockMessage ?? 'A boundary you chose.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: c.dismissBlock,
                child: const Text('Return to Lockin'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => _run(c.overrideBlock),
                child: const Text('Allow this app for 5 minutes'),
              ),
              const SizedBox(height: 18),
              const Text(
                'Tracking stays on. Other restrictions remain active.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _empty(IconData icon, String title, String description) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          children: [
            Icon(icon, size: 36, color: _muted),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.7, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _notice(String text, {IconData icon = Icons.info_outline_rounded}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF202323),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF514A35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFE6BD78), size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFDECBA6),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF26323D)),
    ),
    child: child,
  );
}
