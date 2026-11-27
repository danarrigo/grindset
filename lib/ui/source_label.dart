import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/service_catalog.dart';

/// Installed app name when known, otherwise the catalog or identifier name.
String displayName(AppController c, String source) =>
    c.appDetails[_key(source)]?.label ?? sourceName(source);

String _key(String source) =>
    source.startsWith('windows:') ? source.toLowerCase() : source;

/// The first installed app icon among [sources], if any.
Uint8List? installedIcon(AppController c, Iterable<String> sources) {
  for (final source in sources) {
    final icon = c.appDetails[_key(source)]?.icon;
    if (icon != null) return icon;
  }
  return null;
}

/// The real app icon when one of [sources] is installed, then the website's
/// logo, otherwise a tile with the first letter of [name].
class SourceIcon extends StatelessWidget {
  const SourceIcon({
    super.key,
    required this.controller,
    required this.sources,
    required this.name,
    this.size = 32,
  });
  final AppController controller;
  final List<String> sources;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = installedIcon(controller, sources);
    if (icon == null) {
      final logo = controller.siteLogo(sources);
      if (logo == null) return LetterTile(name, size: size);
      // Site logos are often small or transparent, so they sit on a white
      // tile that reads the same in light and dark mode.
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * .22),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: .5,
          ),
        ),
        child: Image.memory(
          logo,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.memory(
        icon,
        width: size,
        height: size,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// A neutral rounded tile with a name's first letter or digit, or [icon].
class LetterTile extends StatelessWidget {
  const LetterTile(this.name, {super.key, this.size = 32, this.icon});
  final String name;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final match = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * .22),
      ),
      child: ExcludeSemantics(
        child: icon != null
            ? Icon(icon, size: size * .56, color: colors.onSurfaceVariant)
            : Text(
                match?[0]!.toUpperCase() ?? '?',
                style: TextStyle(
                  fontSize: size * .46,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

/// What a focus session keeps shut, one entry per app or site: the sources
/// of every rule that blocks while focusing, joined by service. Apps that
/// aren't on this device are left out; their websites are not.
List<({String name, List<String> sources})> shutWhileFocusing(AppController c) {
  final prefix = c.tracker.isAndroid
      ? 'android:'
      : c.tracker.isWindows
      ? 'windows:'
      : null;
  final sources = {
    for (final rule in c.rules)
      if (rule.focusBlock) ...rule.sources,
  };
  c.requestAppDetails(sources);
  final byName = <String, List<String>>{};
  for (final source in sources) {
    final web = source.startsWith('web:');
    final installed = installedIcon(c, [source]) != null;
    // An app counts once this device has said it is installed.
    if (!web && !(prefix != null && source.startsWith(prefix) && installed)) {
      continue;
    }
    final name = serviceFor(source)?.name ?? displayName(c, source);
    (byName[name] ??= []).add(source);
  }
  return [
    for (final MapEntry(:key, :value) in byName.entries)
      (name: key, sources: value),
  ];
}

/// Every app and site a session keeps shut, packed together. At most two
/// rows; the last tile counts the rest.
class ShutPile extends StatelessWidget {
  const ShutPile({
    super.key,
    required this.controller,
    required this.items,
    this.locked = false,
  });
  final AppController controller;
  final List<({String name, List<String> sources})> items;

  /// Faded, with the count in green: they are shut now.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const gap = 8.0;
    final count = items.length;
    return Semantics(
      label:
          '$count ${count == 1 ? 'app or site' : 'apps and sites'} '
          '${locked ? 'shut' : 'stay shut while you focus'}: '
          '${items.map((i) => i.name).join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final perRow = ((box.maxWidth + gap) / (36 + gap))
                    .floor()
                    .clamp(1, 12);
                final size = ((box.maxWidth - gap * (perRow - 1)) / perRow)
                    .clamp(28.0, 44.0);
                final room = perRow * 2;
                final shown = count > room ? room - 1 : count;
                return Opacity(
                  opacity: locked ? .55 : 1,
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final item in items.take(shown))
                        SourceIcon(
                          controller: controller,
                          sources: item.sources,
                          name: item.name,
                          size: size,
                        ),
                      if (count > shown)
                        Container(
                          width: size,
                          height: size,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(size * .22),
                          ),
                          child: Text(
                            '+${count - shown}',
                            style: TextStyle(
                              fontSize: size * .34,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (locked) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_rounded, size: 15, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '$count ${count == 1 ? 'app or site' : 'apps and sites'} shut',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
