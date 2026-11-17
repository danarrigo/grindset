import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';
import '../platform/windows_apps.dart';
import 'schedule_summary.dart';

String sourceName(String source) {
  for (final preset in individualRulePresets) {
    if (preset.sources.any((candidate) => matchesSource(candidate, source))) {
      return preset.name;
    }
  }
  final raw = source.split(':').last;
  if (source.startsWith('windows:')) {
    return raw.replaceFirst(RegExp(r'\.exe$'), '');
  }
  if (source.startsWith('android:')) return raw.split('.').last;
  return raw;
}

class RuleEditor extends StatefulWidget {
  const RuleEditor({
    super.key,
    required this.sources,
    this.rule,
    this.preset,
    this.scheduledFocus = false,
    this.timezone = 'account timezone',
    this.loadWindowsApps,
    this.browseWindowsApp,
    this.iconFor,
  }) : assert(rule == null || preset == null),
       assert(!scheduledFocus || rule == null);
  final Set<String> sources;
  final ActivityRule? rule;
  final RulePreset? preset;
  final bool scheduledFocus;
  final String timezone;
  final Future<List<WindowsApp>> Function()? loadWindowsApps;
  final Future<WindowsApp?> Function()? browseWindowsApp;

  /// Installed app icon for a source, when the platform can provide one.
  final Widget Function(String source)? iconFor;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

const _limitChoices = [15, 30, 60];

class _RuleEditorState extends State<RuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minutes;
  final _manual = TextEditingController();
  final _search = TextEditingController();
  late final Set<String> _selected;
  late bool _focus;
  late bool _budget;
  late bool _customLimit;
  late bool _scheduled;
  late bool _picking;
  late final List<_ScheduleDraft> _schedules;
  final _windowsApps = <String, WindowsApp>{};
  bool _loadingApps = false;
  String? _appsError;
  String? _manualError;
  String? _error;
  String _sourceQuery = '';

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final preset = widget.preset;
    _name = TextEditingController(
      text: widget.scheduledFocus ? 'Focus hours' : rule?.name ?? preset?.name,
    );
    final minutes = rule?.dailyMinutes ?? preset?.dailyMinutes ?? 30;
    _minutes = TextEditingController(text: '$minutes');
    _customLimit = !_limitChoices.contains(minutes);
    _selected = {...?rule?.sources, ...?preset?.sources};
    _picking = _selected.isEmpty;
    _focus = widget.scheduledFocus ? false : rule?.focusBlock ?? true;
    _budget =
        !widget.scheduledFocus &&
        (rule?.dailyMinutes != null || preset != null);
    _scheduled = widget.scheduledFocus || (rule?.schedules.isNotEmpty ?? false);
    _schedules = [
      for (final window in rule?.schedules ?? <ScheduleWindow>[])
        _ScheduleDraft(window),
    ];
    if (_schedules.isEmpty) _schedules.add(_ScheduleDraft());
  }

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    _manual.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Normalizes typed websites ("YouTube.com", "https://x.com") and app IDs.
  Set<String> _parseTyped(String text) => text
      .split(RegExp(r'[\n,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((raw) {
        // Keyboard capitalization must not change the platform prefix. Keep
        // the identifier itself intact, particularly case-sensitive packages.
        final source = raw.replaceFirstMapped(
          RegExp(r'^(windows|android|web):', caseSensitive: false),
          (match) => match[0]!.toLowerCase(),
        );
        if (source.startsWith('windows:')) {
          final id = source.toLowerCase();
          if (!RegExp(r'^windows:[^/\\:\x00-\x1f]+\.exe$').hasMatch(id)) {
            throw ArgumentError(
              'Use a Windows app such as windows:chrome.exe.',
            );
          }
          return id;
        }
        if (source.startsWith('android:')) {
          if (!RegExp(r'^android:[^\s/:]+$').hasMatch(source)) {
            throw ArgumentError(
              'Use an Android app ID such as android:com.google.android.youtube.',
            );
          }
          return source;
        }
        final host = websiteHost(
          source.startsWith('web:') ? source.substring(4) : source,
        );
        if (host == null) {
          throw ArgumentError('Type a website such as example.com.');
        }
        return 'web:$host';
      })
      .toSet();

  void _addTyped() {
    try {
      final added = _parseTyped(_manual.text);
      setState(() {
        _selected.addAll(added);
        _manual.clear();
        _manualError = null;
        if (_name.text.trim().isEmpty && added.isNotEmpty) {
          _name.text = _appName(added.first);
        }
      });
    } on ArgumentError catch (error) {
      setState(() => _manualError = error.message.toString());
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      // Text still in the box counts, so nothing typed is silently lost.
      final sources = {..._selected, ..._parseTyped(_manual.text)};
      if (sources.isEmpty) {
        throw ArgumentError('Choose at least one app or website.');
      }
      if (sources.length > 256) {
        throw ArgumentError('Choose up to 256 apps and websites.');
      }
      final rule = ActivityRule(
        id: widget.rule?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        sources: sources,
        focusBlock: _focus,
        dailyMinutes: _budget ? int.parse(_minutes.text) : null,
        schedules: _scheduled
            ? _schedules.map((draft) => draft.save()).toList()
            : [],
      );
      Navigator.pop(context, rule);
    } catch (error) {
      setState(
        () => _error = error is ArgumentError
            ? error.message.toString()
            : error.toString(),
      );
    }
  }

  String _appName(String source) =>
      _windowsApps[source.toLowerCase()]?.name ?? sourceName(source);

  /// What a single source is, in words: "Android app", "Windows app" or the
  /// website itself.
  String _kind(String source) => source.startsWith('android:')
      ? 'Android app'
      : source.startsWith('windows:')
      ? 'Windows app'
      : source.substring(source.indexOf(':') + 1);

  /// Sources grouped by the name people know them by, so "YouTube" is one row
  /// covering its app and websites.
  Map<String, List<String>> _group(Iterable<String> sources) {
    final groups = <String, List<String>>{};
    for (final source in sources) {
      (groups[_appName(source)] ??= []).add(source);
    }
    for (final list in groups.values) {
      list.sort((a, b) => _kindOrder(a).compareTo(_kindOrder(b)));
    }
    return groups;
  }

  int _kindOrder(String s) => s.startsWith('android:')
      ? 0
      : s.startsWith('windows:')
      ? 1
      : 2;

  String _kinds(MapEntry<String, List<String>> group) => group.value
      .map(
        (s) => s.startsWith('web:') && _kind(s) == group.key
            ? 'Website'
            : _kind(s),
      )
      .toSet()
      .join(' · ');

  /// Phones need the width; wider screens indent options under their checkbox.
  bool get _narrow => MediaQuery.sizeOf(context).width < 600;
  double get _indent => _narrow ? 0 : 48;

  bool _isSelected(String source) =>
      _selected.any((selected) => matchesSource(selected, source));

  Future<void> _findWindowsApps({bool browse = false}) async {
    setState(() {
      _loadingApps = true;
      _appsError = null;
    });
    try {
      final List<WindowsApp> apps;
      if (browse) {
        final app = await widget.browseWindowsApp!();
        apps = app == null ? [] : [app];
      } else {
        apps = await widget.loadWindowsApps!();
      }
      if (!mounted) return;
      setState(() {
        for (final app in apps) {
          _windowsApps[app.source.toLowerCase()] = app;
        }
        if (apps.isNotEmpty) {
          _sourceQuery = '';
          _search.clear();
          if (browse) {
            _selected.add(apps.single.source);
            if (_name.text.trim().isEmpty) _name.text = apps.single.name;
          }
        } else if (!browse) {
          _appsError = 'No apps found. Use Browse to pick the app instead.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _appsError = 'Could not find apps: $error');
    } finally {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  Future<void> _pickTime(int index, bool start) async {
    final draft = _schedules[index];
    final value = await showTimePicker(
      context: context,
      initialTime: start ? draft.from : draft.until,
      initialEntryMode: MediaQuery.sizeOf(context).width >= 840
          ? TimePickerEntryMode.input
          : TimePickerEntryMode.dial,
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          draft.from = value;
        } else {
          draft.until = value;
        }
      });
    }
  }

  String _limitLabel(int minutes) => minutes < 60
      ? '$minutes min'
      : minutes % 60 == 0
      ? '${minutes ~/ 60} hr'
      : '${minutes ~/ 60} hr ${minutes % 60} min';

  /// Describes the schedule. A half-edited window (no days, equal times) is
  /// not valid yet, so it is named without details instead of failing.
  String _setTimes() {
    if (_schedules.length != 1) return 'at ${_schedules.length} set times';
    try {
      return 'at set times (${scheduleSummary(context, _schedules.single.save())})';
    } on ArgumentError {
      return 'at set times';
    }
  }

  /// One sentence saying exactly what the rule will do.
  (String, bool) _summary() {
    final name = _name.text.trim().isEmpty ? 'These apps' : _name.text.trim();
    final minutes = int.tryParse(_minutes.text);
    final parts = [
      if (_focus) 'while you focus',
      if (_budget && minutes != null && minutes > 0)
        'after ${_limitLabel(minutes)} a day',
      if (_scheduled) _setTimes(),
    ];
    if (parts.isEmpty) {
      return ('$name will only be tracked. Nothing is blocked.', true);
    }
    final joined = parts.length == 1
        ? parts.single
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return (
      '$name ${_name.text.trim().isEmpty ? 'are' : 'is'} blocked $joined.',
      false,
    );
  }

  Widget _icon(String source, double size) {
    if (widget.iconFor != null) return widget.iconFor!(source);
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * .22),
      ),
      child: Icon(
        source.startsWith('web:')
            ? Icons.language_rounded
            : source.startsWith('windows:')
            ? Icons.desktop_windows_outlined
            : Icons.apps_rounded,
        size: size * .56,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedGroups = _group(_selected);
    final candidates =
        {
              ...widget.sources,
              ..._windowsApps.keys,
              ...?widget.rule?.sources,
              ...rulePresets.expand((preset) => preset.sources),
            }
            .map(
              (source) =>
                  source.startsWith('windows:') ? source.toLowerCase() : source,
            )
            .toSet();
    final candidateGroups =
        _group(
            candidates.where(
              (source) =>
                  _appName(source).toLowerCase().contains(_sourceQuery) ||
                  source.toLowerCase().contains(_sourceQuery),
            ),
          ).entries.toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    final (summary, nothingBlocked) = _summary();
    final title = widget.scheduledFocus
        ? 'Schedule focus hours'
        : widget.rule != null
        ? 'Edit rule'
        : widget.preset == socialMediaPreset
        ? 'Limit all social media'
        : widget.preset != null
        ? 'Limit ${widget.preset!.name}'
        : 'New rule';
    final intro = widget.scheduledFocus
        ? 'Pick what to block at set times. No timer needed.'
        : widget.preset == socialMediaPreset
        ? 'One daily limit shared by all these apps. Your other rules still apply.'
        : widget.rule == null && widget.preset == null
        ? 'Pick apps and websites, then choose when to block them.'
        : null;
    return Dialog(
      insetPadding: _narrow
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: desktop ? 640 : 540),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(_narrow ? 20 : 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (intro != null) ...[
                  const SizedBox(height: 6),
                  Text(intro, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  autofocus: widget.rule == null && widget.preset == null,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. YouTube',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Give this rule a name'
                      : v.trim().length > 120
                      ? 'Use up to 120 characters'
                      : null,
                ),
                _sectionTitle('Apps and websites'),
                if (selectedGroups.isEmpty)
                  Text(
                    'Nothing added yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (final group in selectedGroups.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        _icon(group.value.first, 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _kinds(group),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${group.key}',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () =>
                              setState(() => _selected.removeAll(group.value)),
                        ),
                      ],
                    ),
                  ),
                if (!_picking)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => setState(() => _picking = true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add another app or website'),
                  )
                else
                  _picker(colors, candidateGroups, desktop),
                _sectionTitle('Block it'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("While I'm focusing"),
                  subtitle: const Text(
                    'When the focus timer is running on this device.',
                  ),
                  value: _focus,
                  onChanged: (v) => setState(() => _focus = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('After a daily limit'),
                  subtitle: const Text('Time on all your devices adds up.'),
                  value: _budget,
                  onChanged: (v) => setState(() => _budget = v ?? false),
                ),
                if (_budget) ...[
                  Padding(
                    padding: EdgeInsets.only(left: _indent),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final minutes in _limitChoices)
                          _choice(
                            label: _limitLabel(minutes),
                            selected:
                                !_customLimit && _minutes.text == '$minutes',
                            onSelected: (_) => setState(() {
                              _customLimit = false;
                              _minutes.text = '$minutes';
                            }),
                          ),
                        _choice(
                          label: 'Custom',
                          selected: _customLimit,
                          onSelected: (_) =>
                              setState(() => _customLimit = true),
                        ),
                      ],
                    ),
                  ),
                  if (_customLimit)
                    Padding(
                      padding: EdgeInsets.only(left: _indent, top: 12),
                      child: TextFormField(
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Minutes a day',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) =>
                            (int.tryParse(v ?? '') ?? 0) < 1 ||
                                (int.tryParse(v ?? '') ?? 0) > 1440
                            ? 'Choose 1 to 1440 minutes'
                            : null,
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('At set times'),
                  subtitle: Text(
                    'Even without a timer. Times use ${widget.timezone}.',
                  ),
                  value: _scheduled,
                  onChanged: (v) => setState(() => _scheduled = v ?? false),
                ),
                if (_scheduled)
                  Padding(
                    padding: EdgeInsets.only(left: _indent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _schedules.length; i++)
                          _scheduleRow(i),
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: _schedules.length >= 64
                              ? null
                              : () => setState(
                                  () => _schedules.add(_ScheduleDraft()),
                                ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add more times'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    summary,
                    key: const ValueKey('rule-summary'),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: nothingBlocked
                          ? colors.tertiary
                          : colors.onSurface,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
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
                      child: const Text('Save rule'),
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

  Widget _picker(
    ColorScheme colors,
    List<MapEntry<String, List<String>>> groups,
    bool desktop,
  ) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: colors.outlineVariant),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search apps',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (query) =>
              setState(() => _sourceQuery = query.trim().toLowerCase()),
        ),
        if (widget.loadWindowsApps != null ||
            widget.browseWindowsApp != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (widget.loadWindowsApps != null)
                TextButton.icon(
                  onPressed: _loadingApps ? null : () => _findWindowsApps(),
                  icon: const Icon(Icons.desktop_windows_outlined, size: 18),
                  label: Text(
                    _loadingApps ? 'Finding apps…' : 'Show apps on this PC',
                  ),
                ),
              if (widget.browseWindowsApp != null)
                TextButton.icon(
                  onPressed: _loadingApps
                      ? null
                      : () => _findWindowsApps(browse: true),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Browse'),
                ),
            ],
          ),
          if (_appsError != null)
            Text(_appsError!, style: TextStyle(color: colors.error)),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: desktop ? 240 : 200),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final group in groups)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: _icon(group.value.first, 28),
                  title: Text(group.key),
                  subtitle: Text(
                    [
                      if (group.value.any(
                        (s) => _windowsApps[s]?.running == true,
                      ))
                        'Running',
                      _kinds(group),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: group.value.every(_isSelected),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _selected.addAll(group.value);
                      if (_name.text.trim().isEmpty) _name.text = group.key;
                    } else {
                      _selected.removeWhere(
                        (selected) => group.value.any(
                          (source) => matchesSource(selected, source),
                        ),
                      );
                    }
                  }),
                ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No apps match. Type the website below instead.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('add-website'),
                controller: _manual,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Add a website',
                  hintText: 'example.com',
                  errorText: _manualError,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _addTyped(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(
                onPressed: _addTyped,
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// Outlined when off, brand green when on, so every option reads as tappable.
  Widget _choice({
    required String label,
    String? semanticsLabel,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label, semanticsLabel: semanticsLabel),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      backgroundColor: colors.surface,
      selectedColor: colors.primary,
      side: BorderSide(color: selected ? colors.primary : colors.outline),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? colors.onPrimary : colors.onSurface,
      ),
    );
  }

  Widget _scheduleRow(int i) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var day = 1; day <= 7; day++)
              _choice(
                label: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day - 1],
                semanticsLabel: const [
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                  'Sunday',
                ][day - 1],
                selected: _schedules[i].days.contains(day),
                onSelected: (value) => setState(() {
                  if (value) {
                    _schedules[i].days.add(day);
                  } else {
                    _schedules[i].days.remove(day);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              onPressed: () => _pickTime(i, true),
              child: Text(_schedules[i].from.format(context)),
            ),
            const Text('to'),
            OutlinedButton(
              onPressed: () => _pickTime(i, false),
              child: Text(_schedules[i].until.format(context)),
            ),
            if (_schedules.length > 1)
              IconButton(
                tooltip: 'Remove these times',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => setState(() => _schedules.removeAt(i)),
              ),
          ],
        ),
      ],
    ),
  );
}

class _ScheduleDraft {
  _ScheduleDraft([ScheduleWindow? window])
    : days = {...?window?.weekdays},
      from = TimeOfDay(
        hour: (window?.startMinute ?? 540) ~/ 60,
        minute: (window?.startMinute ?? 540) % 60,
      ),
      until = TimeOfDay(
        hour: (window?.endMinute ?? 1020) ~/ 60,
        minute: (window?.endMinute ?? 1020) % 60,
      ) {
    if (window == null) days.addAll({1, 2, 3, 4, 5});
  }
  final Set<int> days;
  TimeOfDay from;
  TimeOfDay until;
  ScheduleWindow save() => ScheduleWindow(
    weekdays: days,
    startMinute: from.hour * 60 + from.minute,
    endMinute: until.hour * 60 + until.minute,
  );
}
