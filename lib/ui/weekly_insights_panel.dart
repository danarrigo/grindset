import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_controller.dart';
import '../core/activity.dart';
import '../core/service_catalog.dart';
import '../core/weekly_insights.dart';
import 'appearance.dart';

class WeeklyInsightsPanel extends StatefulWidget {
  const WeeklyInsightsPanel({super.key, required this.controller});
  final AppController controller;
  @override
  State<WeeklyInsightsPanel> createState() => _WeeklyInsightsPanelState();
}

class _WeeklyInsightsPanelState extends State<WeeklyInsightsPanel> {
  Timer? _timer;
  int _generation = 0;
  bool _loading = true;
  String? _error;
  String _requestedScope = '';
  List<UsageInterval>? _rows;
  DateTime? _snapshotAt;
  List<ActivityRule>? _projectedRules;
  WeeklyInsights? _report;
  String _scope(AppController c) =>
      '${c.deviceId}/${c.timezone}/${accountDay(c.now, c.location).$1}';
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_loading) _load();
    });
  }

  @override
  void didUpdateWidget(covariant WeeklyInsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        _requestedScope != _scope(widget.controller)) {
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    ++_generation;
    super.dispose();
  }

  Future<void> _load() async {
    final c = widget.controller;
    final generation = ++_generation;
    _requestedScope = _scope(c);
    final at = c.now;
    final local = tz.TZDateTime.from(at, c.location);
    final start = tz.TZDateTime(
      c.location,
      local.year,
      local.month,
      local.day - 6,
    ).toUtc();
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final rows = await c.store.usage(from: start);
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = rows;
        _snapshotAt = at;
        _projectedRules = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load recorded insights: $error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _usageLabel(Duration value) =>
      value > Duration.zero && value < const Duration(minutes: 1)
      ? '<1 min'
      : durationLabel(value);

  Widget _stat(String label, String value) => SizedBox(
    width: 210,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!_loading &&
        _error == null &&
        _rows != null &&
        !identical(_projectedRules, c.rules)) {
      _report = WeeklyInsights(
        intervals: _rows!,
        rules: c.rules,
        deviceId: c.deviceId,
        now: _snapshotAt!,
        location: c.location,
      );
      _projectedRules = c.rules;
    }
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Weekly insights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Refresh weekly insights',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Text(
          'This device · Last 7 local calendar days, including today · ${c.timezone}',
        ),
        const SizedBox(height: 12),
        const Text(
          'Confirmed usage only. Missing records are unknown, not zero usage. Rule-matched time is not a productivity score.',
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!_loading && report != null) ...[
          if (report.recordedDays == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No recorded usage in this period. Enable tracking to collect observations; old gaps cannot be reconstructed.',
              ),
            ),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _stat(
                'Recorded usage',
                report.recordedDays == 0
                    ? 'Not recorded'
                    : _usageLabel(report.total),
              ),
              _stat(
                'Time on apps in your rules',
                report.recordedDays == 0
                    ? 'Not recorded'
                    : _usageLabel(report.matched),
              ),
              _stat('Days with observations', '${report.recordedDays} of 7'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Recorded daily trend',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final day in report.days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          MaterialLocalizations.of(context)
                              .formatShortDate(day.date),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          day.hasRecords
                              ? _usageLabel(day.usage)
                              : 'Not recorded',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  if (day.hasRecords)
                    LinearProgressIndicator(
                      value:
                          day.usage.inMilliseconds /
                          math.max(
                            1,
                            report.days
                                .map((d) => d.usage.inMilliseconds)
                                .reduce(math.max),
                          ),
                    ),
                  for (final overrun in day.budgetOverruns)
                    Text(
                      '${overrun.name}: ${_usageLabel(overrun.excess)} above the current limit on this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (day.budgetsReached.isNotEmpty)
                    Text(
                      'This-device limits reached: ${day.budgetsReached.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'This-device budget comparison',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            c.rules.any((r) => r.dailyMinutes != null)
                ? 'This device alone: ${report.budgetDays} of ${report.recordedDays} recorded days reached a current daily budget. Other devices may also have used the shared budget. This applies today’s budgets and source selections to past observations; it is not a history of past rule settings.'
                : 'No daily budgets are currently configured.',
          ),
          const SizedBox(height: 20),
          Text(
            'Top recorded apps and sites',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'App and website breakdowns can overlap. Overall totals merge overlapping observations instead of adding them twice.',
            style: TextStyle(fontSize: 12),
          ),
          for (final item in report.topSources.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(sourceName(item.source))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _usageLabel(item.duration),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    item.source,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Snapshot updated ${TimeOfDay.fromDateTime(tz.TZDateTime.from(_snapshotAt!, c.location)).format(context)}. Refreshes every minute while open. Today may be incomplete.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
