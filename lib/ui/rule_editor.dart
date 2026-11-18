import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';
import '../core/service_catalog.dart';
import '../platform/windows_apps.dart';
import 'schedule_summary.dart';
import 'source_label.dart';

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
    this.labelFor,
  }) : assert(rule == null || preset == null),
       assert(!scheduledFocus || rule == null);
  final Set<String> sources;
  final ActivityRule? rule;
  final RulePreset? preset;
  final bool scheduledFocus;
  final String timezone;
  final Future<List<WindowsApp>> Function()? loadWindowsApps;
  final Future<WindowsApp?> Function()? browseWindowsApp;

  /// Installed app icon among [sources], when the platform can provide one.
  final Widget Function(List<String> sources, String name, double size)?
  iconFor;

  /// The installed app's own name for a source, when known.
  final String? Function(String source)? labelFor;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

const _limitChoices = [15, 30, 60];

class _RuleEditorState extends State<RuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minutes;
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
  final _openFamilies = <String>{};
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

  /// A website or app ID typed into search, when it reads as one. Plain words
  /// ("goo") are searches, not websites.
  Set<String>? _typed(String query) {
    if (query.contains(' ') || !(query.contains('.') || query.contains(':'))) {
      return null;
    }
    try {
      return _parseTyped(query);
    } on ArgumentError {
      return null;
    }
  }

  void _toggle(_Choice choice, bool add) => setState(() {
    if (add) {
      _selected.addAll(choice.sources);
      if (_name.text.trim().isEmpty) _name.text = choice.name;
    } else {
      // Only what this choice covers: unticking Gmail keeps google.com.
      _selected.removeWhere(
        (selected) => choice.sources.any((s) => matchesSource(s, selected)),
      );
    }
  });

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      final sources = {..._selected};
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
      serviceFor(source)?.name ??
      _windowsApps[source.toLowerCase()]?.name ??
      widget.labelFor?.call(source) ??
      sourceName(source);

  /// Where a choice works: "Web, Android, Windows".
  String _platforms(Iterable<String> sources) => [
    if (sources.any((s) => s.startsWith('web:'))) 'Web',
    if (sources.any((s) => s.startsWith('android:'))) 'Android',
    if (sources.any((s) => s.startsWith('windows:'))) 'Windows',
  ].join(', ');

  _Choice _serviceChoice(
    CatalogService service, [
    Iterable<String> extra = const [],
  ]) {
    final sources = {...service.sources, ...extra};
    return _Choice(
      service.name,
      sources,
      '${service.category} · ${_platforms(sources)}',
    );
  }

  _Choice _familyChoice(CatalogFamily family) {
    // "Search, Gmail, YouTube and 9 more" fits one line on a phone.
    final names = family.members
        .take(3)
        .map((m) => m.replaceFirst('${family.name} ', ''))
        .join(', ');
    return _Choice(
      family.name,
      family.sources,
      '$names and ${family.members.length - 3} more',
      family: family,
    );
  }

  /// Apps this device has used or found. A known service brings all of its
  /// apps and websites, so picking Instagram here covers Instagram everywhere.
  List<_Choice> _deviceApps() {
    final observed = {
      ...widget.sources,
      ..._windowsApps.keys,
      ...?widget.rule?.sources,
    }.map((s) => s.startsWith('windows:') ? s.toLowerCase() : s);
    return [
      for (final MapEntry(:key, :value) in _group(observed).entries)
        if (serviceNamed(key) case final service?)
          _serviceChoice(service, value)
        else
          _Choice(
            key,
            value.toSet(),
            [
              if (value.any((s) => _windowsApps[s]?.running == true)) 'Running',
              _platforms(value),
            ].join(' · '),
          ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Picker rows: suggestions by section with an empty search, otherwise
  /// the best matches from everything.
  List<(String?, _Choice)> _results() {
    final device = _deviceApps();
    final query = _sourceQuery;
    if (query.isEmpty) {
      final shown = {for (final c in device) c.name};
      return [
        for (final c in device) ('On this device', c),
        for (final preset in individualRulePresets)
          if (!shown.contains(preset.name))
            ('Popular', _serviceChoice(serviceNamed(preset.name)!)),
        for (final family in catalogFamilies)
          ('Whole companies', _familyChoice(family)),
      ];
    }
    // Parse what was typed, not the lowercased query: Android IDs are
    // case-sensitive.
    final typed = _typed(_search.text.trim());
    final matches = [
      for (final match in searchCatalog(query))
        if (match is CatalogFamily)
          _familyChoice(match)
        else if (match is CatalogService)
          device.firstWhere(
            (c) => c.name == match.name,
            orElse: () => _serviceChoice(match),
          ),
    ];
    final names = {for (final c in matches) c.name};
    return [
      if (typed != null)
        (
          null,
          _Choice(
            typed.map((s) => s.substring(s.indexOf(':') + 1)).join(', '),
            typed,
            typed
                .map(
                  (s) => s.startsWith('web:')
                      ? 'Website'
                      : s.startsWith('android:')
                      ? 'Android app'
                      : 'Windows app',
                )
                .toSet()
                .join(', '),
            typed: true,
          ),
        ),
      for (final c in matches) (null, c),
      for (final c in device)
        if (!names.contains(c.name) &&
            (c.name.toLowerCase().contains(query) ||
                c.sources.any((s) => s.toLowerCase().contains(query))))
          (null, c),
    ];
  }

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

  Widget _icon(Iterable<String> sources, String name, double size) =>
      widget.iconFor?.call(sources.toList(), name, size) ??
      LetterTile(name, size: size);

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A whole company reads as one row; partly chosen ones list each app.
    final fullFamilies = [
      for (final family in catalogFamilies)
        if (family.sources.every(_selected.contains)) family,
    ];
    final inFamilies = {for (final f in fullFamilies) ...f.sources};
    final selectedGroups = _group(
      _selected.where((s) => !inFamilies.contains(s)),
    );
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
                if (_selected.isEmpty)
                  Text(
                    'Nothing added yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (final family in fullFamilies)
                  _selectedRow(
                    family.name,
                    family.sources,
                    'All ${family.members.length} ${family.name} services',
                    icon: LetterTile(family.name),
                  ),
                for (final group in selectedGroups.entries)
                  _selectedRow(
                    group.key,
                    group.value.toSet(),
                    _kinds(group),
                    icon: _icon(group.value, group.key, 32),
                  ),
                if (!_picking)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => setState(() => _picking = true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add another app or website'),
                  )
                else
                  _picker(colors, desktop),
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

  Widget _selectedRow(
    String name,
    Set<String> sources,
    String subtitle, {
    required Widget icon,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove $name',
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () => setState(() => _selected.removeAll(sources)),
        ),
      ],
    ),
  );

  Widget _choiceRow(_Choice choice, {bool nested = false}) {
    final all = choice.sources.every(_isSelected);
    final any = choice.sources.any(_isSelected);
    final family = choice.family;
    final open = family != null && _openFamilies.contains(family.name);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: nested ? 24 : 0),
          leading: choice.typed
              ? const LetterTile('', size: 28, icon: Icons.add_rounded)
              : family != null
              ? LetterTile(family.name, size: 28)
              : _icon(choice.sources, choice.name, 28),
          title: Text(
            choice.typed
                ? 'Add ${choice.name}'
                : family != null
                ? 'All of ${family.name}'
                : choice.name,
          ),
          subtitle: Text(choice.subtitle, style: const TextStyle(fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (family != null)
                IconButton(
                  tooltip: open
                      ? 'Hide ${family.name} services'
                      : 'Pick ${family.name} services one by one',
                  icon: Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  onPressed: () => setState(
                    () => open
                        ? _openFamilies.remove(family.name)
                        : _openFamilies.add(family.name),
                  ),
                ),
              Checkbox(
                tristate: true,
                value: all ? true : (any ? null : false),
                onChanged: (_) => _choose(choice, !all),
              ),
            ],
          ),
          onTap: () => _choose(choice, !all),
        ),
        if (open)
          for (final service in family.services)
            _choiceRow(_serviceChoice(service), nested: true),
      ],
    );
  }

  /// Typed entries are added once and the search clears for the next one.
  void _choose(_Choice choice, bool add) {
    _toggle(choice, add);
    if (choice.typed) {
      _search.clear();
      setState(() => _sourceQuery = '');
    }
  }

  Widget _picker(ColorScheme colors, bool desktop) {
    final results = _results();
    return Container(
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
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Search apps and websites',
              hintText: 'Google, YouTube, a game, example.com',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (query) =>
                setState(() => _sourceQuery = query.trim().toLowerCase()),
            onSubmitted: (_) {
              if (_sourceQuery.isNotEmpty && results.isNotEmpty) {
                _choose(results.first.$2, true);
              }
            },
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
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: desktop ? 320 : 280),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < results.length; i++) ...[
                  if (results[i].$1 != null &&
                      (i == 0 || results[i - 1].$1 != results[i].$1))
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 2),
                      child: Text(
                        results[i].$1!,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  _choiceRow(results[i].$2),
                ],
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nothing found. For a website, type its address, like example.com.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

/// One tappable result: a service, a whole company, an app on this device,
/// or exactly what was typed.
class _Choice {
  const _Choice(
    this.name,
    this.sources,
    this.subtitle, {
    this.family,
    this.typed = false,
  });
  final String name;
  final Set<String> sources;
  final String subtitle;
  final CatalogFamily? family;
  final bool typed;
}
