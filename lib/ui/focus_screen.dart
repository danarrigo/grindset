import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The Focus page's own colours: near-black in dark mode, as before, and a
/// matching light set.
class FocusPalette {
  const FocusPalette._({
    required this.background,
    required this.ink,
    required this.clock,
    required this.muted,
    required this.faint,
    required this.chip,
    required this.stop,
    required this.start,
    required this.startInk,
    required this.warning,
    required this.setup,
  });
  final Color background, ink, clock, muted, faint, chip, stop, start;
  final Color startInk, warning, setup;

  static const dark = FocusPalette._(
    background: Color(0xFF09090A),
    ink: Color(0xFFE5E5EA),
    clock: Colors.white,
    muted: Color(0xFFBFBFC6),
    faint: Color(0xFF8E8E93),
    chip: Color(0xFF1C1C1E),
    stop: Color(0xFF2C2C2E),
    start: Color(0xFF073B1D),
    startInk: Color(0xFF30D158),
    warning: Color(0xFFE5C07B),
    setup: Color(0xFFFF9F0A),
  );
  static const light = FocusPalette._(
    background: Color(0xFFF7F7F9),
    ink: Color(0xFF1D1D1F),
    clock: Color(0xFF1D1D1F),
    muted: Color(0xFF55555B),
    faint: Color(0xFF86868C),
    chip: Color(0xFFE9E9ED),
    stop: Color(0xFFE3E3E8),
    start: Color(0xFFD9F2E1),
    startInk: Color(0xFF176F30),
    warning: Color(0xFF85570D),
    setup: Color(0xFFB25000),
  );

  static FocusPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// The working surface only. Session state and navigation belong to the app.
class FocusScreen extends StatelessWidget {
  const FocusScreen({
    super.key,
    required this.remaining,
    required this.running,
    required this.actionLabel,
    required this.onAction,
    required this.onMenu,
    this.setupLabel,
    this.onSetup,
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

  /// Shown until tracking, blocking and a first rule are set up.
  final String? setupLabel;
  final VoidCallback? onSetup;
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
  Widget build(BuildContext context) {
    final p = FocusPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: showBrand
                    ? Text(
                        'Grindset',
                        style: TextStyle(
                          color: p.ink,
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
                  color: p.chip,
                  borderRadius: BorderRadius.circular(24),
                  onPressed: onMenu,
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    semanticLabel: 'More options',
                    color: p.ink,
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
                              style: TextStyle(color: p.warning, fontSize: 13),
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
                                  style: TextStyle(
                                    color: p.clock,
                                    fontSize: 88,
                                    fontWeight: FontWeight.w200,
                                    letterSpacing: -3,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
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
                              style: TextStyle(color: p.muted, fontSize: 13),
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
                                    color: running ? p.stop : p.start,
                                  ),
                                  child: Icon(
                                    running
                                        ? CupertinoIcons.stop_fill
                                        : CupertinoIcons.play_fill,
                                    semanticLabel: actionLabel,
                                    color: running ? p.clock : p.startInk,
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
                                      color: running ? p.muted : p.startInk,
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
          if (setupLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(48, 44),
                color: p.chip,
                borderRadius: BorderRadius.circular(22),
                onPressed: onSetup,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle,
                      color: p.setup,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        setupLabel!,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: p.faint,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
