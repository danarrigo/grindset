import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app_controller.dart';
import '../core/activity.dart';
import '../core/focus_profile.dart';

class FocusProfilesPanel extends StatefulWidget {
  const FocusProfilesPanel({super.key, required this.controller});
  final AppController controller;
  @override
  State<FocusProfilesPanel> createState() => _FocusProfilesPanelState();
}

class _FocusProfilesPanelState extends State<FocusProfilesPanel> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({FocusProfile? profile, String name = ''}) async {
    final result = await showDialog<FocusProfile>(
      context: context,
      builder: (_) => _ProfileEditor(
        profile: profile,
        initialName: name,
        rules: widget.controller.rules,
      ),
    );
    if (result != null && mounted) {
      await _run(() => widget.controller.saveFocusProfile(result));
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Focus profiles',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'On this device. Profiles select which saved activities block during a manual focus timer. They do not change budgets, schedules or timer duration.',
          ),
          const SizedBox(height: 12),
          Text(
            'Current selection: ${c.selectedFocusProfile?.name ?? 'Custom'}',
          ),
          if (c.rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Create an activity in Rules before configuring a profile.',
              ),
            ),
          for (final profile in c.focusProfiles)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      profile.ruleIds
                          .map(
                            (id) =>
                                c.rules
                                    .where((r) => r.id == id)
                                    .firstOrNull
                                    ?.name ??
                                'Removed activity',
                          )
                          .join(', '),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await _confirm(
                                        'Use ${profile.name}?',
                                        'This replaces the Block during focus selection on this device, including any current focus session. Budgets, schedules and existing five-minute overrides stay in place. No timer is started or stopped.',
                                        'Use profile',
                                      ) &&
                                      mounted) {
                                    await _run(
                                      () => c.applyFocusProfile(profile.id),
                                    );
                                  }
                                },
                          child: Text('Use ${profile.name}'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(profile: profile),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await _confirm(
                                        'Delete ${profile.name}?',
                                        'This removes the saved profile. Your current blocking selection remains unchanged.',
                                        'Delete profile',
                                      ) &&
                                      mounted) {
                                    await _run(
                                      () => c.deleteFocusProfile(profile.id),
                                    );
                                  }
                                },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in ['Work', 'Study', 'Sleep'])
                if (!c.focusProfiles.any(
                  (p) => p.name.toLowerCase() == name.toLowerCase(),
                ))
                  OutlinedButton(
                    onPressed: _busy || c.rules.isEmpty
                        ? null
                        : () => _edit(name: name),
                    child: Text('Create $name'),
                  ),
              TextButton.icon(
                onPressed: _busy || c.rules.isEmpty ? null : () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New profile'),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          const Text(
            'Saving or editing a profile never applies it automatically. New or changed activities may make the current selection Custom.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      );
    },
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    this.profile,
    required this.initialName,
    required this.rules,
  });
  final FocusProfile? profile;
  final String initialName;
  final List<ActivityRule> rules;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(
    text: widget.profile?.name ?? widget.initialName,
  );
  late final _selected = {...?widget.profile?.ruleIds};
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.profile == null
                  ? 'Create focus profile'
                  : 'Edit focus profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Profile name'),
              maxLength: 60,
            ),
            const Text(
              'Select saved activities to block during manual focus. Other activities keep their budgets and schedules.',
            ),
            for (final rule in widget.rules)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(rule.name),
                subtitle: Text(rule.sources.take(2).join(', ')),
                value: _selected.contains(rule.id),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(rule.id);
                  } else {
                    _selected.remove(rule.id);
                  }
                }),
              ),
            for (final id
                in _selected
                    .where((id) => !widget.rules.any((r) => r.id == id))
                    .toList())
              CheckboxListTile(
                title: const Text('Removed activity (uncheck to save)'),
                value: true,
                onChanged: (_) => setState(() => _selected.remove(id)),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      if (_selected.any(
                        (id) => !widget.rules.any((r) => r.id == id),
                      )) {
                        throw StateError('Remove missing activities first.');
                      }
                      Navigator.pop(
                        context,
                        FocusProfile(
                          id: widget.profile?.id ?? const Uuid().v4(),
                          name: _name.text,
                          ruleIds: _selected,
                        ),
                      );
                    } catch (error) {
                      setState(() => _error = error.toString());
                    }
                  },
                  child: const Text('Save profile'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
