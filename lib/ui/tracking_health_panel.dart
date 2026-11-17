import 'package:flutter/material.dart';

import '../app_controller.dart';

/// One setup step: done, needing action, or broken.
typedef SetupStep = ({
  String title,
  String status,
  bool done,
  bool broken,
  String? action,
  VoidCallback? onAction,
});

/// The steps a person must complete before rules can work on this device.
List<SetupStep> setupSteps(
  AppController c, {
  VoidCallback? onTracking,
  VoidCallback? onBrowser,
  VoidCallback? onAppBlocking,
  VoidCallback? onRules,
}) {
  if (!c.tracker.supported) return const [];
  final ruleCount = c.rules
      .where(
        (r) =>
            (r.focusBlock ||
                r.dailyMinutes != null ||
                r.schedules.isNotEmpty) &&
            r.sources.any(
              (s) => c.tracker.isWindows
                  ? s.startsWith('windows:') || s.startsWith('web:')
                  : s.startsWith('android:'),
            ),
      )
      .length;
  final trackingBroken =
      c.trackingEnabled &&
      (c.trackingError != null ||
          !c.accessGranted ||
          (c.tracker.isAndroid && !c.backgroundTrackingRunning));
  final trackingDone = c.trackingEnabled && !trackingBroken;
  final bridge = c.browserBridge;
  final browserSeen =
      bridge?.lastPolicyRequestAt != null &&
      c.now.difference(bridge!.lastPolicyRequestAt!) <=
          const Duration(seconds: 75);
  return [
    (
      title: 'Activity tracking',
      status: trackingDone
          ? 'On'
          : trackingBroken
          ? (c.trackingError ??
                'Stopped. A permission may have been turned off.')
          : 'Off. Rules only work while this is on.',
      done: trackingDone,
      broken: trackingBroken,
      action: trackingDone ? null : (trackingBroken ? 'Fix' : 'Turn on'),
      onAction: onTracking,
    ),
    if (c.tracker.isAndroid)
      (
        title: 'App blocking',
        status: c.androidBlockingEnabled
            ? 'Ready'
            : 'Not set up. Needed to cover blocked apps.',
        done: c.androidBlockingEnabled,
        broken: false,
        action: c.androidBlockingEnabled ? null : 'Set up',
        onAction: onAppBlocking,
      ),
    if (c.tracker.isWindows)
      (
        title: 'App blocking',
        status: !c.trackingEnabled
            ? 'Starts when tracking is on.'
            : c.windowsForegroundEventsActive
            ? 'Ready'
            : 'Not working. Restart Grindset.',
        done: c.trackingEnabled && c.windowsForegroundEventsActive,
        broken: c.trackingEnabled && !c.windowsForegroundEventsActive,
        action: null,
        onAction: null,
      ),
    if (c.tracker.isWindows)
      (
        title: 'Browser extension',
        status: bridge?.isListening != true
            ? 'Unavailable. Restart Grindset.'
            : browserSeen
            ? 'Connected'
            : 'Not connected. Needed to block websites.',
        done: browserSeen,
        broken: bridge?.isListening != true,
        action: browserSeen || bridge?.isListening != true ? null : 'Pair',
        onAction: onBrowser,
      ),
    (
      title: 'Rules',
      status: ruleCount == 0
          ? 'No rules yet.'
          : ruleCount == 1
          ? '1 rule'
          : '$ruleCount rules',
      done: ruleCount > 0,
      broken: false,
      action: ruleCount == 0 ? 'Add rule' : null,
      onAction: onRules,
    ),
  ];
}

class TrackingHealthPanel extends StatefulWidget {
  const TrackingHealthPanel({
    super.key,
    required this.controller,
    this.onTracking,
    this.onBrowser,
    this.onAppBlocking,
    this.onRules,
  });
  final AppController controller;
  final VoidCallback? onTracking;
  final VoidCallback? onBrowser;
  final VoidCallback? onAppBlocking;
  final VoidCallback? onRules;
  @override
  State<TrackingHealthPanel> createState() => _TrackingHealthPanelState();
}

class _TrackingHealthPanelState extends State<TrackingHealthPanel> {
  bool _checking = false;
  String? _error;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.controller.checkTrackingHealth();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not check: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final colors = Theme.of(context).colorScheme;
      final steps = setupSteps(
        c,
        onTracking: widget.onTracking,
        onBrowser: widget.onBrowser,
        onAppBlocking: widget.onAppBlocking,
        onRules: widget.onRules,
      );
      final done = steps.where((s) => s.done).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  steps.isEmpty
                      ? 'Setup'
                      : done == steps.length
                      ? 'All set'
                      : 'Setup · $done of ${steps.length} done',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Check now',
                onPressed: _checking ? null : _check,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (steps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Tracking and blocking need Windows or Android.'),
            ),
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _marker(colors, i + 1, step),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          step.status,
                          style: TextStyle(
                            fontSize: 13,
                            color: step.broken
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (step.action != null && step.onAction != null) ...[
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: step.onAction,
                      child: Text(step.action!),
                    ),
                  ],
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
        ],
      );
    },
  );

  Widget _marker(ColorScheme colors, int number, SetupStep step) => Container(
    width: 28,
    height: 28,
    margin: const EdgeInsets.only(top: 1),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: step.done
          ? const Color(0xFF30D158)
          : step.broken
          ? colors.error
          : null,
      border: step.done || step.broken
          ? null
          : Border.all(color: colors.outline, width: 1.5),
    ),
    child: step.done
        ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
        : step.broken
        ? Icon(Icons.priority_high_rounded, size: 18, color: colors.onError)
        : Text(
            '$number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
  );
}
