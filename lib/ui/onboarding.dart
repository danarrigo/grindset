import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/rule_presets.dart';
import '../core/service_catalog.dart';
import 'source_label.dart';
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
    this.onHaveAccount,
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

  /// Signs in to an existing account; true once signed in. Its rules come
  /// from the account, so picking apps is skipped.
  final Future<bool> Function()? onHaveAccount;
  final bool signedIn;
  final VoidCallback onDone;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  static const _limits = <(String, int?)>[
    ('15 min', 15),
    ('30 min', 30),
    ('1 hr', 60),
    ('None', null),
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

  Future<void> _haveAccount() async {
    setState(() => _saving = true);
    try {
      final signedIn = await widget.onHaveAccount!();
      // Straight to permissions, which every device still needs.
      if (signedIn && mounted) setState(() => _step = 2);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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

  /// What the continue button says on the picking step.
  String get _limitLabel {
    final groups = _groups.where((g) => _picked.contains(g.name)).length;
    final apps = _presets
        .where((p) => _picked.contains(p.name) && _groupOf(p) == null)
        .length;
    String count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    if (groups == 0 && apps == 0) return 'Continue';
    if (groups == 0) return 'Limit ${count(apps, 'app')}';
    if (apps == 0) return 'Limit ${count(groups, 'group')}';
    return 'Limit ${count(groups, 'group')} and ${count(apps, 'app')}';
  }

  @override
  Widget build(BuildContext context) {
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
                  // The welcome screen leads with the preview, not progress.
                  if (_step > 0)
                    Semantics(
                      label: 'Step ${_step + 1} of $_steps',
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            for (var i = 0; i < _steps; i++) ...[
                              if (i > 0) const SizedBox(width: 4),
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  height: 4,
                                  color: i <= _step
                                      ? colors.primary
                                      : colors.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey('onboarding-$_step'),
                      padding: EdgeInsets.only(
                        top: _step == 0 ? 20 : 36,
                        bottom: 24,
                      ),
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
                      minimumSize: const Size.fromHeight(54),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: _saving ? null : _next,
                    child: Text(
                      _step == 0
                          ? 'Get started'
                          : last
                          ? 'Start focusing'
                          : _screen == 1
                          ? _limitLabel
                          : 'Continue',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 44,
                    child: _step == 0 && widget.onHaveAccount != null
                        ? TextButton(
                            onPressed: _saving ? null : _haveAccount,
                            child: const Text('I already have an account'),
                          )
                        : _step == 0 || last
                        ? null
                        : TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _picked.clear();
                                    _step++;
                                  }),
                            child: const Text('Skip for now'),
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
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.4,
            height: 1.05,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 16,
            height: 1.45,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _welcome(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Preview(controller: c, apps: _presets.take(3).toList()),
      const SizedBox(height: 36),
      _title(
        context,
        'Less scrolling.\nMore done.',
        'Lock in, and the apps that pull you away stay shut until you\'re done. On your phone and your PC.',
      ),
    ],
  );

  Widget _distractions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    void toggle(String name) => setState(
      () => _picked.contains(name) ? _picked.remove(name) : _picked.add(name),
    );
    final anyCovered = _presets.any((preset) => _groupOf(preset) != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          context,
          'What pulls\nyou away?',
          'Tap the ones that eat your time. They are blocked while you focus.',
        ),
        LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth - 3 * 8) / 4;
            return Wrap(
              spacing: 8,
              runSpacing: 18,
              children: [
                for (final preset in _presets)
                  SizedBox(
                    width: width,
                    child: _AppPick(
                      key: ValueKey('pick-${preset.name}'),
                      controller: c,
                      preset: preset,
                      selected:
                          _picked.contains(preset.name) ||
                          _groupOf(preset) != null,
                      covered: _groupOf(preset) != null,
                      onTap: () => toggle(preset.name),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        const _Heading('Or whole groups'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in _groups)
              FilterChip(
                label: Text(group.name),
                selected: _picked.contains(group.name),
                onSelected: (_) => toggle(group.name),
              ),
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
        const _Heading('Daily allowance'),
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
          _minutes == null ? 'Only blocked while you focus.' : 'Each app gets this much a day, and each group this much for all its apps. Change it later in Rules.',
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );
}

/// One app to tap: its real icon, a check once picked.
class _AppPick extends StatelessWidget {
  const _AppPick({
    super.key,
    required this.controller,
    required this.preset,
    required this.selected,
    required this.covered,
    required this.onTap,
  });
  final AppController controller;
  final RulePreset preset;
  final bool selected;

  /// Picked through a group: shown included, not tappable.
  final bool covered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !covered,
      label: preset.name,
      excludeSemantics: true,
      child: InkWell(
        onTap: covered ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: selected ? 1 : .5,
                    child: SourceIcon(
                      controller: controller,
                      sources: preset.sources.toList(),
                      name: preset.name,
                      size: 56,
                    ),
                  ),
                  Positioned(
                    right: -5,
                    bottom: -5,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      scale: selected ? 1 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: covered ? colors.outline : colors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What Grindset does, shown rather than told: a focus timer with the
/// apps it keeps shut. Always dark, like the block screen.
class _Preview extends StatelessWidget {
  const _Preview({required this.controller, required this.apps});
  final AppController controller;
  final List<RulePreset> apps;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFF5F5F7);
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111113),
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Focus',
              style: TextStyle(color: Color(0xFFB1B1B7), fontSize: 14),
            ),
            const Text(
              '24:13',
              style: TextStyle(
                color: ink,
                fontSize: 76,
                fontWeight: FontWeight.w200,
                letterSpacing: -3,
                height: 1.15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 28),
            for (final app in apps)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    SourceIcon(
                      controller: controller,
                      sources: app.sources.toList(),
                      name: app.name,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        app.name,
                        style: const TextStyle(color: ink, fontSize: 15),
                      ),
                    ),
                    const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF30D158),
                      size: 18,
                    ),
                  ],
                ),
              ),
          ],
        ),
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
