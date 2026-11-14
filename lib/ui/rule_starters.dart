import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/rule_presets.dart';

class RuleStarters extends StatelessWidget {
  const RuleStarters({
    super.key,
    required this.rules,
    required this.onSelected,
  });
  final List<ActivityRule> rules;
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Starter activities',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (showGroup) ...[
            Text(
              'One shared budget across 17 supported social, messaging and video apps.',
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
            'Or choose individual apps',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Windows apps where supported, websites and Android apps. Suggested: 30 min/day and focus blocking. Edit before saving.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: Text(preset.name),
                  onPressed: () => onSelected(preset),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Websites need the paired browser extension. Windows app blocking shows an interruption; it is not a process lock.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
