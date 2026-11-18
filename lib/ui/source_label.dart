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
