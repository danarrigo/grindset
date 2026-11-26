import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/rule_presets.dart';
import '../core/service_catalog.dart';
import 'tracking_health_panel.dart';

/// First launch: what Grindset does, what to limit, the permissions rules
/// need, then optional extras. Shown once; every step can be skipped.
class Onboarding extends StatefulWidget {
  const Onboarding({
    super.key,
    required this.controller,
    required this.onTracking,
    required this.onDone,
    this.onAppBlocking,
    this.onInstantBlocking,
    this.onFocusHours,
    this.onBrowser,
    this.onSignIn,
    this.signedIn = false,
  });

  final AppController controller;
  final VoidCallback onTracking;
  final VoidCallback? onAppBlocking;
  final VoidCallback? onInstantBlocking;
  final VoidCallback? onFocusHours;

  /// Pairs the browser extension (Windows).
  final VoidCallback? onBrowser;

  /// Finishes onboarding and opens sign-in.
  final VoidCallback? onSignIn;
  final bool signedIn;
  final VoidCallback onDone;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  static const _limits = <(String, int?)>[
    ('15 min', 15),
    ('30 min', 30),
    ('1 hour', 60),
    ('No limit', null),
  ];
  var _step = 0;
  final _picked = <String>{};
  int? _minutes = 30;
  bool _saving = false;

  AppController get c => widget.controller;

  /// No permissions step where tracking is unsupported (tests, previews).
  int get _steps => c.tracker.supported ? 4 : 3;

  int get _screen => !c.tracker.supported && _step >= 2 ? _step + 1 : _step;

  List<RulePreset> get _presets => [
    for (final preset in individualRulePresets)
      if (preset.sources.any(
        (s) => c.tracker.isAndroid
            ? s.startsWith('android:')
            : s.startsWith('web:') || s.startsWith('windows:'),
      ))
        preset,
  ].take(12).toList();

  /// Whole groups sharing one limit. The rest are in Rules > Add.
  static final _groups = [
    for (final name in const [
      'Social media',
      'Video and streaming',
      'Games',
      'Shopping',
    ])
      categoryPresets.firstWhere((preset) => preset.name == name),
  ];

  /// The picked group that already includes [preset], if any.
  RulePreset? _groupOf(RulePreset preset) => _groups
      .where(
        (group) =>
            _picked.contains(group.name) &&
            preset.sources.every(group.sources.contains),
      )
      .firstOrNull;

  Future<void> _next() async {
    if (_screen == 1 && _picked.isNotEmpty) {
      setState(() => _saving = true);
      try {
        for (final preset in [..._groups, ..._presets]) {
          if (_picked.contains(preset.name) &&
              (preset.isCategory || _groupOf(preset) == null)) {
            await c.addStarterRule(preset.name, preset.sources, _minutes);
          }
        }
        _picked.clear();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
        }
        return;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    if (_step == _steps - 1) {
      widget.onDone();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final last = _step == _steps - 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Text(
                          'Grindset',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_step + 1} of $_steps',
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _steps,
                      minHeight: 4,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey('onboarding-$_step'),
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: switch (_screen) {
                        0 => _welcome(context),
                        1 => _distractions(context),
                        2 => _permissions(context),
                        _ => _extras(context),
                      },
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('onboarding-next'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _saving ? null : _next,
                    child: Text(
                      _step == 0
                          ? 'Get started'
                          : last
                          ? 'Start focusing'
                          : 'Continue',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 44,
                    child: _step == 0 || last
                        ? null
                        : TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _picked.clear();
                                    _step++;
                                  }),
                            child: const Text('Skip'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String title, String subtitle) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: text.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _welcome(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        context,
        'Less scrolling, more done.',
        'Grindset keeps distracting apps and websites out of your way, on your phone and your PC.',
      ),
      for (final (icon, title, body) in const [
        (
          Icons.timer_outlined,
          'Lock in',
          'Start a focus session and distractions are blocked until it ends.',
        ),
        (
          Icons.hourglass_bottom_rounded,
          'Daily limits',
          'Give apps a daily allowance. Once it is used up, they are blocked until tomorrow.',
        ),
        (
          Icons.schedule_rounded,
          'Focus hours',
          'Block distractions at set times, like your work or study hours.',
        ),
      ])
        _Feature(icon: icon, title: title, body: body),
    ],
  );

  Widget _distractions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    FilterChip chip(RulePreset preset, {bool covered = false}) => FilterChip(
      label: Text(preset.name),
      selected: covered || _picked.contains(preset.name),
      onSelected: covered
          ? null
          : (on) => setState(
              () => on ? _picked.add(preset.name) : _picked.remove(preset.name),
            ),
    );
    final anyCovered = _presets.any((preset) => _groupOf(preset) != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          context,
          'What pulls you away?',
          'Pick the apps and sites to limit. They are also blocked while you focus.',
        ),
        Text('Groups', style: text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final group in _groups) chip(group)],
        ),
        const SizedBox(height: 20),
        Text('Apps', style: text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              chip(preset, covered: _groupOf(preset) != null),
          ],
        ),
        if (anyCovered) ...[
          const SizedBox(height: 10),
          Text(
            'Apps in a group you picked share its limit.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 28),
        Text('Daily limit', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int?>(
            showSelectedIcon: false,
            segments: [
              for (final (label, minutes) in _limits)
                ButtonSegment(value: minutes, label: Text(label)),
            ],
            selected: {_minutes},
            onSelectionChanged: (value) =>
                setState(() => _minutes = value.first),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _minutes == null ? 'Only blocked while you focus.' : 'Each app gets its own daily limit, and each group one limit for all its apps. You can change it later in Rules.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _permissions(BuildContext context) {
    final steps = setupSteps(
      c,
      onTracking: widget.onTracking,
      onAppBlocking: widget.onAppBlocking,
      onInstantBlocking: widget.onInstantBlocking,
    ).where((s) => s.title != 'Rules' && s.title != 'Browser extension');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          context,
          'Let Grindset see what is open',
          c.tracker.isAndroid
              ? 'Rules can only work once Grindset can tell which app is open and cover it when it is blocked.'
              : 'Rules can only work once Grindset can tell which app is open. It starts with Windows and stays in the tray.',
        ),
        for (final step in steps)
          _Row(
            done: step.done,
            title: step.title,
            body: step.status,
            action: step.action,
            onAction: step.onAction,
          ),
        const SizedBox(height: 8),
        Text(
          'Grindset never sees your screen, what you type, or page contents.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _extras(BuildContext context) {
    final hours = c.focusHours.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          context,
          'A few extras',
          'All optional. You can find them later in Settings.',
        ),
        if (widget.onFocusHours != null)
          _Row(
            done: hours,
            title: 'Focus hours',
            body: hours
                ? 'On. Distractions are blocked at your set times.'
                : 'Block distractions automatically at set times.',
            action: hours ? 'Change' : 'Set up',
            onAction: widget.onFocusHours,
          ),
        if (widget.onBrowser != null)
          _Row(
            done: false,
            title: 'Browser extension',
            body: 'Websites are blocked without it. With it, a blocked site shows a block page instead of its tab closing.',
            action: 'Pair',
            onAction: widget.onBrowser,
          ),
        if (widget.onSignIn != null)
          _Row(
            done: widget.signedIn,
            title: 'Sync your devices',
            body: widget.signedIn ? 'Signed in.' : 'Sign in so rules and daily limits are shared between your phone and PC.',
            action: widget.signedIn ? null : 'Sign in',
            onAction: widget.onSignIn,
          ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.done,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });
  final bool done;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: done ? colors.primary : colors.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
