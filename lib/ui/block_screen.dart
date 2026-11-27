import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_controller.dart';
import 'appearance.dart';
import 'source_label.dart';

/// Shown over a blocked app: whose turn it is not, how far through the
/// block you are, and the way back to work.
class BlockScreen extends StatelessWidget {
  const BlockScreen({
    super.key,
    required this.controller,
    required this.source,
    required this.onBack,
    this.onAskAi,
  });

  final AppController controller;
  final String source;
  final VoidCallback onBack;

  /// Asks an AI for a few minutes; null when that isn't possible.
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final name = displayName(c, source);
    final span = c.blockSpan(source);
    String clock(DateTime at) =>
        TimeOfDay.fromDateTime(tz.TZDateTime.from(at, c.location))
            .format(context);
    final from = span?.from;
    final progress = span == null
        ? null
        : from == null
        ? 1.0
        : (c.now.difference(from).inSeconds /
                  span.until.difference(from).inSeconds)
              .clamp(0.0, 1.0);
    final left = span?.until.difference(c.now);
    final detail = span == null
        ? null
        : from == null
        ? 'Opens again tomorrow'
        : '${left! < const Duration(minutes: 1) ? 'Under a minute' : durationLabel(left)} left · ends ${clock(span.until)}';
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SourceIcon(
                      controller: c,
                      sources: [source],
                      name: name,
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Not now,\n$name.',
                    maxLines: 4,
                    style: TextStyle(
                      fontSize: name.length > 14 ? 38 : 48,
                      fontWeight: FontWeight.w700,
                      letterSpacing: name.length > 14 ? -1.3 : -1.8,
                      height: 1.04,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (span != null) ...[
                    _Bar(progress: progress!),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          span.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          detail!,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      c.blockMessage ?? 'An active rule is blocking this app.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(flex: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onBack,
                    child: const Text('Back to work'),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 48,
                    child: onAskAi == null
                        ? null
                        : TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: colors.onSurfaceVariant,
                              textStyle: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                              ),
                            ),
                            onPressed: onAskAi,
                            child: const Text(
                              'Need it? Ask AI for a few minutes',
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How far through the block, drawn like the green bar in the logo.
class _Bar extends StatelessWidget {
  const _Bar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final done = (progress * 1000).round();
    return Semantics(
      label: '${(progress * 100).round()} percent through',
      child: SizedBox(
        height: 10,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (done > 0)
              Expanded(
                flex: done,
                child: ColoredBox(color: colors.primary),
              ),
            if (done > 0 && done < 1000) const SizedBox(width: 3),
            if (done < 1000)
              Expanded(
                flex: 1000 - done,
                child: ColoredBox(color: colors.surfaceContainerHighest),
              ),
          ],
        ),
      ),
    );
  }
}
