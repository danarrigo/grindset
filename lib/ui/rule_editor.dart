import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';

String sourceName(String source) {
  for (final preset in rulePresets) {
    if (preset.sources.contains(source)) return preset.name;
  }
  final raw = source.split(':').last;
  if (source.startsWith('windows:')) {
    return raw.replaceFirst(RegExp(r'\.exe$'), '');
  }
  if (source.startsWith('android:')) return raw.split('.').last;
  return raw;
}

class RuleEditor extends StatefulWidget {
  const RuleEditor({super.key, required this.sources, this.rule, this.preset})
    : assert(rule == null || preset == null);
  final Set<String> sources;
  final ActivityRule? rule;
  final RulePreset? preset;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minutes;
  final _manual = TextEditingController();
  late final Set<String> _selected;
  late bool _focus;
  late bool _budget;
  late bool _scheduled;
  late TimeOfDay _from;
  late TimeOfDay _until;
  late Set<int> _days;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final preset = widget.preset;
    _name = TextEditingController(text: rule?.name ?? preset?.name);
    _minutes = TextEditingController(
      text: '${rule?.dailyMinutes ?? preset?.dailyMinutes ?? 30}',
    );
    _selected = {...?rule?.sources, ...?preset?.sources};
    _focus = rule?.focusBlock ?? true;
    _budget = rule?.dailyMinutes != null || preset != null;
    final schedule = rule?.schedules.firstOrNull;
    _scheduled = schedule != null;
    _from = TimeOfDay(
      hour: (schedule?.startMinute ?? 540) ~/ 60,
      minute: (schedule?.startMinute ?? 540) % 60,
    );
    _until = TimeOfDay(
      hour: (schedule?.endMinute ?? 1020) ~/ 60,
      minute: (schedule?.endMinute ?? 1020) % 60,
    );
    _days = {...?schedule?.weekdays};
    if (_days.isEmpty) _days = {1, 2, 3, 4, 5};
  }

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      final extra = _manual.text
          .split(RegExp(r'[\n,]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      final sources = {..._selected, ...extra}.map((raw) {
        // Keyboard capitalization must not change the platform prefix. Keep
        // the identifier itself intact, particularly case-sensitive packages.
        final source = raw.replaceFirstMapped(
          RegExp(r'^(windows|android|web):', caseSensitive: false),
          (match) => match[0]!.toLowerCase(),
        );
        if (!source.startsWith('web:')) return source;
        final host = websiteHost(source.substring(4));
        if (host == null) {
          throw ArgumentError(
            'Use a website host such as web:youtube.com, without a URL path or wildcard.',
          );
        }
        return 'web:$host';
      }).toSet();
      if (sources.any(
        (s) => !RegExp(r'^(windows|android|web):[^\s/:]+$').hasMatch(s),
      )) {
        throw ArgumentError(
          'Use source identifiers such as windows:chrome.exe or android:com.google.android.youtube.',
        );
      }
      final rule = ActivityRule(
        id: widget.rule?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        sources: sources,
        focusBlock: _focus,
        dailyMinutes: _budget ? int.parse(_minutes.text) : null,
        schedules: _scheduled
            ? [
                ScheduleWindow(
                  weekdays: _days,
                  startMinute: _from.hour * 60 + _from.minute,
                  endMinute: _until.hour * 60 + _until.minute,
                ),
              ]
            : [],
      );
      Navigator.pop(context, rule);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _pickTime(bool start) async {
    final value = await showTimePicker(
      context: context,
      initialTime: start ? _from : _until,
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          _from = value;
        } else {
          _until = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.rule?.sources ?? widget.preset?.sources ?? const <String>{};
    final sources =
        {
          ...widget.sources,
          ...?widget.rule?.sources,
          ...rulePresets.expand((preset) => preset.sources),
        }.toList()..sort((a, b) {
          if (initial.contains(a) != initial.contains(b)) {
            return initial.contains(a) ? -1 : 1;
          }
          final name = sourceName(a).compareTo(sourceName(b));
          return name == 0 ? a.compareTo(b) : name;
        });
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.rule == null ? 'Create an activity' : 'Edit activity',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Link apps across devices to give them one shared budget.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Activity name',
                    hintText: 'e.g. YouTube',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Name this activity'
                      : null,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Apps in this activity',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final source in sources)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(sourceName(source)),
                          subtitle: Text(
                            source,
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: _selected.contains(source),
                          onChanged: (value) => setState(() {
                            if (value ?? false) {
                              _selected.add(source);
                            } else {
                              _selected.remove(source);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Enter a source identifier',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    TextField(
                      controller: _manual,
                      maxLines: 2,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        hintText: 'android:com.example.app\nweb:example.com',
                        helperText: 'One per line. Web hosts include subdomains and require the paired Windows extension.',
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Block during focus'),
                  value: _focus,
                  onChanged: (v) => setState(() => _focus = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily shared budget'),
                  subtitle: const Text(
                    'Overlapping use of this activity counts once.',
                  ),
                  value: _budget,
                  onChanged: (v) => setState(() => _budget = v),
                ),
                if (_budget)
                  TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Minutes per day',
                    ),
                    validator: (v) =>
                        (int.tryParse(v ?? '') ?? 0) < 1 ||
                            (int.tryParse(v ?? '') ?? 0) > 1440
                        ? 'Choose 1 to 1440 minutes'
                        : null,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recurring restriction'),
                  value: _scheduled,
                  onChanged: (v) => setState(() => _scheduled = v),
                ),
                if (_scheduled) ...[
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(
                            [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ][day - 1],
                          ),
                          showCheckmark: false,
                          selected: _days.contains(day),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _days.add(day);
                            } else {
                              _days.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(true),
                          child: Text('From ${_from.format(context)}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(false),
                          child: Text('Until ${_until.format(context)}'),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Uses your account timezone. Overnight windows are supported.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Save activity'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
