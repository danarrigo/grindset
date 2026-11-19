import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';
import '../core/service_catalog.dart';

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
    final categories = categoryPresets
        .where(
          (preset) =>
              !rules.any((rule) => preset.sources.every(rule.sources.contains)),
        )
        .toList();
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
      if (categories.isNotEmpty) ...[
        Text(
          'Limit a whole category. Its apps and sites share one daily limit.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in categories)
              ActionChip(
                backgroundColor: colors.surfaceContainerHighest,
                side: BorderSide.none,
                avatar: Icon(_categoryIcons[preset.name], size: 18),
                label: Text(preset.name),
                onPressed: () => onSelected(preset),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(),
        ),
      ],
      Text(
        'Or pick one app. It starts blocked while you focus and limited to 30 min a day. You can change this before saving.',
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
      'Suggestions',
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

const _categoryIcons = {
  'Social media': Icons.people_outline_rounded,
  'Messaging': Icons.chat_bubble_outline_rounded,
  'Video and streaming': Icons.smart_display_outlined,
  'Games': Icons.sports_esports_outlined,
  'Shopping': Icons.shopping_bag_outlined,
  'News and reading': Icons.article_outlined,
  'AI chat': Icons.auto_awesome_outlined,
  'Dating': Icons.favorite_border_rounded,
  'Music and audio': Icons.headphones_outlined,
};
