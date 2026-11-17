import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'rule_editor.dart';

/// Installed app name when known, otherwise the catalog or identifier name.
String displayName(AppController c, String source) =>
    c.appDetails[source]?.label ?? sourceName(source);

class SourceIcon extends StatelessWidget {
  const SourceIcon({
    super.key,
    required this.controller,
    required this.source,
    this.size = 32,
  });
  final AppController controller;
  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = controller.appDetails[source]?.icon;
    if (icon != null) {
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
}
