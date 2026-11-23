import 'package:flutter/material.dart';

import '../core/activity.dart';
import 'schedule_editor.dart';

/// Edits Focus hours: set times when every rule that blocks while you focus
/// is on, as if a focus session were running. Pops the new windows, an
/// empty list when turned off, or null when cancelled.
class FocusHoursDialog extends StatefulWidget {
  const FocusHoursDialog({
    super.key,
    required this.windows,
    this.saved = const [],
    required this.timezone,
    required this.focusRules,
  });
  final List<ScheduleWindow> windows;

  /// The times to offer when turning Focus hours back on.
  final List<ScheduleWindow> saved;
  final String timezone;

  /// Names of this device's rules that block while focusing.
  final List<String> focusRules;

  @override
  State<FocusHoursDialog> createState() => _FocusHoursDialogState();
}

class _FocusHoursDialogState extends State<FocusHoursDialog> {
  late bool _on = widget.windows.isNotEmpty;
  late final _drafts = [
    for (final window
        in widget.windows.isNotEmpty ? widget.windows : widget.saved)
      ScheduleDraft(window),
    if (widget.windows.isEmpty && widget.saved.isEmpty) ScheduleDraft(),
  ];
  String? _error;

  void _save() {
    try {
      Navigator.pop(context, [
        if (_on)
          for (final draft in _drafts) draft.save(),
      ]);
    } on ArgumentError catch (error) {
      setState(() => _error = error.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = widget.focusRules;
    final blocks = rules.isEmpty
        ? 'No rule blocks while you focus yet. Turn on "While I\'m focusing" in a rule to use Focus hours.'
        : rules.length <= 3
        ? 'Blocks ${_list(rules)}.'
        : 'Blocks ${rules.take(2).join(', ')} and ${rules.length - 2} more rules.';
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Focus hours', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'At these times your rules block as if a focus session were running. No timer needed. Applies on all your devices.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Focus hours'),
                value: _on,
                onChanged: (value) => setState(() {
                  _on = value;
                  _error = null;
                }),
              ),
              if (_on) ...[
                ScheduleWindowsEditor(
                  drafts: _drafts,
                  onChanged: () => setState(() => _error = null),
                ),
                const SizedBox(height: 8),
                Text(
                  'Times use ${widget.timezone}.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  blocks,
                  key: const ValueKey('focus-hours-rules'),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: rules.isEmpty
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _list(List<String> names) => names.length == 1
    ? names.single
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
