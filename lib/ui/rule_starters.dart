import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';

class RuleStarters extends StatelessWidget {
  const RuleStarters({
    super.key,
    required this.rules,
    required this.onSelected,
    this.collapsed = false,
  });
  final List<ActivityRule> rules;

  /// Folded behind a heading once the user has their own rules.
  final bool collapsed;
  final ValueChanged<RulePreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showGroup = !rules.any(
      (rule) => socialMediaPreset.sources.every(rule.sources.contains),
    );
    final presets = individualRulePresets
        .where(
          (preset) => !rules.any(
            (rule) => rule.sources.any(
              (source) => preset.sources.any(
                (candidate) =>
                    matchesSource(candidate, source) ||
                    matchesSource(source, candidate),
              ),
            ),
          ),
        )
        .toList();
    if (MediaQuery.sizeOf(context).width >= 840) {
      presets.sort((a, b) {
        final aNative = a.sources.any((s) => s.startsWith('windows:'));
        final bNative = b.sources.any((s) => s.startsWith('windows:'));
        return aNative == bNative
            ? individualRulePresets
                  .indexOf(a)
                  .compareTo(individualRulePresets.indexOf(b))
            : aNative
            ? -1
            : 1;
      });
    }
    final body = <Widget>[
      if (showGroup) ...[
        Text(
          'One daily limit shared by 17 social, messaging and video apps.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => onSelected(socialMediaPreset),
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: const Text('All social media'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(),
        ),
      ],
      Text(
        'Or pick one app. Starts at 30 min a day and blocked during focus; you can change it before saving.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in presets)
            ActionChip(
              backgroundColor: colors.surfaceContainerHighest,
              side: BorderSide.none,
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(preset.name),
              onPressed: () => onSelected(preset),
            ),
        ],
      ),
    ];
    final title = Text(
      'Suggested apps',
      style: Theme.of(context).textTheme.titleMedium,
    );
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: collapsed
          ? ExpansionTile(
              title: title,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 20),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 10), ...body],
              ),
            ),
    );
  }
}
