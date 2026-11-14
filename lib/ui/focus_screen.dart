import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The working surface only. Session state and navigation belong to the app.
class FocusScreen extends StatelessWidget {
  const FocusScreen({
    super.key,
    required this.remaining,
    required this.running,
    required this.actionLabel,
    required this.onAction,
    required this.onMenu,
    required this.onStatus,
    required this.buildLabel,
    this.status,
    this.warning,
    this.showBrand = true,
    this.menuButtonKey,
  });

  final Duration remaining;
  final bool running;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onMenu;
  final VoidCallback onStatus;
  final String buildLabel;
  final String? status;
  final String? warning;
  final bool showBrand;
  final Key? menuButtonKey;

  String get _clock {
    final seconds = (remaining.inMicroseconds / Duration.microsecondsPerSecond)
        .ceil();
    final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:$minutes:$remainder'
        : '${seconds ~/ 60}:$remainder';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: showBrand
                  ? const Text(
                      'Grindset',
                      style: TextStyle(
                        color: Color(0xFFE5E5EA),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Tooltip(
              message: 'More options',
              excludeFromSemantics: true,
              child: CupertinoButton(
                key: menuButtonKey,
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(24),
                onPressed: onMenu,
                child: const Icon(
                  CupertinoIcons.ellipsis,
                  semanticLabel: 'More options',
                  color: Color(0xFFE5E5EA),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 48),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (warning != null) ...[
                          Text(
                            warning!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFE5C07B),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Semantics(
                          label: running
                              ? 'Time remaining'
                              : 'Session duration',
                          value: _clock,
                          child: ExcludeSemantics(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _clock,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 88,
                                  fontWeight: FontWeight.w200,
                                  letterSpacing: -3,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            status!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFBFBFC6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 42),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(84, 84),
                          onPressed: onAction,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: running
                                      ? const Color(0xFF2C2C2E)
                                      : const Color(0xFF073B1D),
                                ),
                                child: Icon(
                                  running
                                      ? CupertinoIcons.stop_fill
                                      : CupertinoIcons.play_fill,
                                  semanticLabel: actionLabel,
                                  color: running
                                      ? Colors.white
                                      : const Color(0xFF30D158),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 13),
                              ExcludeSemantics(
                                child: Text(
                                  actionLabel,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: running
                                        ? const Color(0xFFBFBFC6)
                                        : const Color(0xFF30D158),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(48, 48),
          onPressed: onStatus,
          child: Text(
            buildLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
