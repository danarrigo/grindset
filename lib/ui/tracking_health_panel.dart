import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'rule_editor.dart';

import '../app_controller.dart';

enum _Health { ready, attention, unknown, off }

class TrackingHealthPanel extends StatefulWidget {
  const TrackingHealthPanel({
    super.key,
    required this.controller,
    this.onTracking,
    this.onBrowser,
    this.onAccessibility,
  });
  final AppController controller;
  final VoidCallback? onTracking;
  final VoidCallback? onBrowser;
  final VoidCallback? onAccessibility;
  @override
  State<TrackingHealthPanel> createState() => _TrackingHealthPanelState();
}

class _TrackingHealthPanelState extends State<TrackingHealthPanel> {
  bool _checking = false;
  String? _error;
  bool _recent(DateTime? time, Duration limit) {
    if (time == null) return false;
    final age = widget.controller.now.difference(time);
    return !age.isNegative && age <= limit;
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.controller.checkTrackingHealth();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not check tracking: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Widget _row(String title, String status, String detail, _Health state) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        switch (state) {
          _Health.ready => Icons.check_circle_outline_rounded,
          _Health.attention => Icons.warning_amber_rounded,
          _Health.unknown => Icons.help_outline_rounded,
          _Health.off => Icons.pause_circle_outline_rounded,
        },
        color: state == _Health.attention
            ? colors.error
            : colors.onSurfaceVariant,
      ),
      title: Text('$title: $status'),
      subtitle: Text(detail),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final fresh = _recent(c.runtimeCheckedAt, const Duration(seconds: 15));
      final configured = c.rules
          .where(
            (r) =>
                (r.focusBlock ||
                    r.dailyMinutes != null ||
                    r.schedules.isNotEmpty) &&
                r.sources.any(
                  (s) => c.tracker.isWindows
                      ? s.startsWith('windows:') || s.startsWith('web:')
                      : c.tracker.isAndroid && s.startsWith('android:'),
                ),
          )
          .length;
      final bridge = c.browserBridge;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Tracking health',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton.icon(
                onPressed: _checking ? null : _check,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_checking ? 'Checking…' : 'Check now'),
              ),
            ],
          ),
          if (!c.tracker.supported)
            _row(
              'Collector',
              'Unavailable',
              'Native checks require Windows or Android. Timer-only previews cannot verify blocking.',
              _Health.unknown,
            )
          else if (!c.trackingEnabled)
            _row(
              'Collector',
              'Off',
              'No activity is collected and restrictions are not enforced.',
              _Health.off,
            )
          else if (c.trackingError != null)
            _row(
              'Collector',
              'Needs attention',
              c.trackingError!,
              _Health.attention,
            )
          else if (!c.accessGranted)
            _row(
              'Collector',
              'Permission required',
              'Review tracking permission below.',
              _Health.attention,
            )
          else if (c.tracker.isAndroid && !c.backgroundTrackingRunning)
            _row(
              'Collector',
              'Service stopped',
              'Restart tracking and review Android notification/background permissions.',
              _Health.attention,
            )
          else
            _row(
              'Collector',
              fresh ? 'Recent check' : 'Not recently verified',
              fresh
                  ? 'The collector loop responded within the last 15 seconds.'
                  : 'No recent successful collector check. Use Check now.',
              fresh ? _Health.ready : _Health.unknown,
            ),
          if (c.tracker.isWindows)
            _row(
              'Windows app blocking',
              !c.trackingEnabled
                  ? 'Off'
                  : c.windowsForegroundEventsActive
                  ? 'Monitor enabled'
                  : 'Monitor unavailable',
              c.lastVerifiedWindowsBlockAt == null
                  ? 'No confirmed restriction presentation in this launch. A configured monitor is not proof that every app can be restricted.'
                  : 'Last confirmed presentation: ${c.lastVerifiedWindowsBlockSource == null ? 'an app' : sourceName(c.lastVerifiedWindowsBlockSource!)} at ${TimeOfDay.fromDateTime(tz.TZDateTime.from(c.lastVerifiedWindowsBlockAt!, c.location)).format(context)}. Other clients, elevated windows and workspace boundaries may differ.',
              !c.trackingEnabled
                  ? _Health.off
                  : c.windowsForegroundEventsActive
                  ? _Health.ready
                  : _Health.attention,
            ),
          if (c.tracker.isAndroid)
            _row(
              'Android app blocking',
              c.androidBlockingEnabled
                  ? 'Accessibility connected'
                  : 'Accessibility not connected',
              'Usage Access alone cannot block apps. Connection does not certify delivery or OEM background reliability.',
              c.androidBlockingEnabled ? _Health.ready : _Health.attention,
            ),
          if (c.tracker.isWindows)
            _row(
              'Browser extension',
              bridge?.isListening != true
                  ? 'Bridge unavailable'
                  : bridge?.lastPolicyRequestAt == null
                  ? 'Not yet verified'
                  : _recent(
                      bridge?.lastPolicyRequestAt,
                      const Duration(seconds: 75),
                    )
                  ? 'Recent policy request'
                  : 'No recent contact',
              bridge?.isListening != true
                  ? 'The local bridge is not listening. Review the startup warning or restart Grindset.'
                  : 'An authenticated request verifies connection, not that browser rules were applied. Open your paired browser to check; closed or sleeping browsers may show no recent contact.',
              bridge?.isListening != true
                  ? _Health.attention
                  : _recent(
                      bridge?.lastPolicyRequestAt,
                      const Duration(seconds: 75),
                    )
                  ? _Health.ready
                  : _Health.unknown,
            ),
          _row(
            'Restrictions',
            '$configured configured for this platform',
            'Activities need matching sources and tracking enabled. Budgets and schedules remain independent of focus profiles.',
            configured == 0
                ? _Health.unknown
                : !c.trackingEnabled
                ? _Health.off
                : _Health.ready,
          ),
          if (c.trackingInterruption != null)
            Text(
              'Recorded tracking gap: ${c.trackingInterruption}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.onTracking != null)
                OutlinedButton(
                  onPressed: widget.onTracking,
                  child: Text(
                    c.trackingEnabled ? 'Review collector' : 'Set up tracking',
                  ),
                ),
              if (widget.onBrowser != null)
                TextButton(
                  onPressed: widget.onBrowser,
                  child: const Text('Browser setup'),
                ),
              if (widget.onAccessibility != null)
                TextButton(
                  onPressed: widget.onAccessibility,
                  child: const Text('App blocking setup'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'These are observed prerequisites and recent checks, not a guarantee of tamper-proof blocking or notification delivery.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      );
    },
  );
}
