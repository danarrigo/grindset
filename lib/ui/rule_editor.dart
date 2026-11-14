import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';
import '../platform/windows_apps.dart';

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
  }) : assert(rule == null || preset == null),
       assert(!scheduledFocus || rule == null);
  final Set<String> sources;
  final ActivityRule? rule;
  final RulePreset? preset;
  final bool scheduledFocus;
  final String timezone;
  final Future<List<WindowsApp>> Function()? loadWindowsApps;
  final Future<WindowsApp?> Function()? browseWindowsApp;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minutes;
  final _manual = TextEditingController();
  final _search = TextEditingController();
  late final Set<String> _selected;
  late bool _focus;
  late bool _budget;
  late bool _scheduled;
  late final List<_ScheduleDraft> _schedules;
  final _windowsApps = <String, WindowsApp>{};
  bool _loadingApps = false;
  String? _appsError;
  String? _platform;
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
    _minutes = TextEditingController(
      text: '${rule?.dailyMinutes ?? preset?.dailyMinutes ?? 30}',
    );
    _selected = {...?rule?.sources, ...?preset?.sources};
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
        if (source.startsWith('windows:')) return source.toLowerCase();
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
        (s) => s.startsWith('windows:')
            ? !RegExp(r'^windows:[^/\\:\x00-\x1f]+\.exe$').hasMatch(s)
            : !RegExp(r'^(android|web):[^\s/:]+$').hasMatch(s),
      )) {
        throw ArgumentError(
          'Use source identifiers such as windows:chrome.exe or android:com.google.android.youtube.',
        );
      }
      if (sources.isEmpty) {
        throw ArgumentError('Choose at least one app or website.');
      }
      if (sources.length > 256) {
        throw ArgumentError('Choose up to 256 sources per activity.');
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
      setState(() => _error = error.toString());
    }
  }

  String _appName(String source) =>
      _windowsApps[source.toLowerCase()]?.name ?? sourceName(source);

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
          _platform = 'windows';
          _sourceQuery = '';
          _search.clear();
          if (browse) {
            _selected.add(apps.single.source);
            if (_name.text.trim().isEmpty) _name.text = apps.single.name;
          }
        } else if (!browse) {
          _appsError = 'No selectable running or registered apps found. Browse for an application executable instead.';
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

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.rule?.sources ?? widget.preset?.sources ?? const <String>{};
    final sources =
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
            .toSet()
            .toList()
          ..sort((a, b) {
            final aSelected = initial.any((source) => matchesSource(source, a));
            final bSelected = initial.any((source) => matchesSource(source, b));
            if (aSelected != bSelected) {
              return aSelected ? -1 : 1;
            }
            final name = _appName(a).compareTo(_appName(b));
            return name == 0 ? a.compareTo(b) : name;
          });
    final visibleSources = sources.where(
      (source) =>
          (_platform == null || source.startsWith('$_platform:')) &&
          (_appName(source).toLowerCase().contains(_sourceQuery) ||
              source.toLowerCase().contains(_sourceQuery)),
    );
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: desktop ? 720 : 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.scheduledFocus
                      ? 'Schedule focus hours'
                      : widget.rule == null
                      ? 'Create an activity'
                      : 'Edit activity',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.scheduledFocus
                      ? 'Choose distractions to block automatically at your scheduled hours. No timer needs to be started.'
                      : widget.preset == socialMediaPreset
                      ? 'One shared budget across the supported social, messaging and video apps below. Existing individual rules still apply. Review the list before saving.'
                      : 'Link Windows apps, websites and Android apps with one shared budget.',
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
                      : v.trim().length > 120
                      ? 'Use up to 120 characters'
                      : null,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Apps in this activity',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                if (widget.loadWindowsApps != null ||
                    widget.browseWindowsApp != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.loadWindowsApps != null)
                        OutlinedButton.icon(
                          onPressed: _loadingApps
                              ? null
                              : () => _findWindowsApps(),
                          icon: const Icon(
                            Icons.desktop_windows_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _loadingApps
                                ? 'Finding apps…'
                                : 'Find apps on this PC',
                          ),
                        ),
                      if (widget.browseWindowsApp != null)
                        TextButton.icon(
                          onPressed: _loadingApps
                              ? null
                              : () => _findWindowsApps(browse: true),
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Browse for .exe'),
                        ),
                    ],
                  ),
                  const Text(
                    'Running windows and apps registered with Windows. Names only, never window titles or contents. Shared-host/PWA apps may need website rules.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (_appsError != null)
                    Text(
                      _appsError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final filter in <String?, String>{
                      null: 'All',
                      'windows': 'Windows',
                      'web': 'Websites',
                      'android': 'Android',
                    }.entries)
                      ChoiceChip(
                        label: Text(filter.value),
                        selected: _platform == filter.key,
                        onSelected: (_) =>
                            setState(() => _platform = filter.key),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Find apps and websites',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (query) =>
                      setState(() => _sourceQuery = query.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_selected.length} selected across all platforms',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: desktop ? 260 : 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final source in visibleSources)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_appName(source)),
                          subtitle: Text(
                            '${_windowsApps[source]?.running == true ? 'Running · ' : ''}$source',
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: _selected.any(
                            (selected) => matchesSource(selected, source),
                          ),
                          onChanged: (value) => setState(() {
                            if (value ?? false) {
                              _selected.add(source);
                              if (_name.text.trim().isEmpty) {
                                _name.text = _appName(source);
                              }
                            } else {
                              _selected.removeWhere(
                                (selected) => matchesSource(selected, source),
                              );
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
                  subtitle: const Text(
                    'On this device. Daily budgets and schedules sync.',
                  ),
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
                  title: const Text('Scheduled focus hours'),
                  subtitle: const Text(
                    'Automatically block these apps without starting a timer.',
                  ),
                  value: _scheduled,
                  onChanged: (v) => setState(() => _scheduled = v),
                ),
                if (_scheduled) ...[
                  Text(
                    'Timezone: ${widget.timezone}. Tracking must be enabled. Overnight windows end the next day.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  for (var i = 0; i < _schedules.length; i++) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Time window ${i + 1}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (_schedules.length > 1)
                          IconButton(
                            tooltip: 'Remove time window ${i + 1}',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () =>
                                setState(() => _schedules.removeAt(i)),
                          ),
                      ],
                    ),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _pickTime(i, true),
                          child: Text(
                            'From ${_schedules[i].from.format(context)}',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _pickTime(i, false),
                          child: Text(
                            'Until ${_schedules[i].until.format(context)}',
                          ),
                        ),
                      ],
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _schedules.length >= 64
                        ? null
                        : () =>
                              setState(() => _schedules.add(_ScheduleDraft())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add time window'),
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
