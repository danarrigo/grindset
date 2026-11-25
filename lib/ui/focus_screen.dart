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

/// Focus hours on the Focus page: on now (with when they end and what they
/// block) or starting later today.
class FocusHoursBanner {
  const FocusHoursBanner({
    required this.title,
    required this.active,
    this.detail,
  });
  final String title;
  final String? detail;
  final bool active;
}

/// Something to fix, shown as a card; tapping it goes where it is fixed.
class FocusNotice {
  const FocusNotice(this.message, {this.onTap, this.warning = true});
  final String message;
  final VoidCallback? onTap;

  /// A warning gets the warning sign; anything else a calm pause sign.
  final bool warning;
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
    this.eyebrow,
    this.showAction = true,
    this.focusHours,
    this.notices = const [],
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

  /// A label above the clock, e.g. "Focus hours" when it counts down to them ending.
  final String? eyebrow;

  /// False while Focus hours already block distractions: nothing to start.
  final bool showAction;
  final FocusHoursBanner? focusHours;
  final List<FocusNotice> notices;
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
          if (focusHours != null) ...[
            const SizedBox(height: 12),
            _FocusHoursCard(banner: focusHours!, palette: p),
          ],
          for (final notice in notices) ...[
            const SizedBox(height: 8),
            _NoticeCard(notice: notice, palette: p),
          ],
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
                          if (eyebrow != null) ...[
                            Text(
                              eyebrow!,
                              key: const ValueKey('focus-eyebrow'),
                              style: TextStyle(
                                color: p.startInk,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Semantics(
                            label: eyebrow != null
                                ? '$eyebrow remaining'
                                : running
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
                          if (showAction) ...[
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

class _FocusHoursCard extends StatelessWidget {
  const _FocusHoursCard({required this.banner, required this.palette});
  final FocusHoursBanner banner;
  final FocusPalette palette;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 430),
    child: Container(
      key: const ValueKey('focus-hours-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: banner.active ? palette.start : palette.chip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: banner.active ? palette.startInk : palette.faint,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.title,
                  style: TextStyle(
                    color: banner.active ? palette.startInk : palette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (banner.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    banner.detail!,
                    style: TextStyle(
                      color: banner.active ? palette.ink : palette.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice, required this.palette});
  final FocusNotice notice;
  final FocusPalette palette;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 430),
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 44),
      onPressed: notice.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        decoration: BoxDecoration(
          color: palette.chip,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              notice.warning
                  ? CupertinoIcons.exclamationmark_triangle_fill
                  : CupertinoIcons.pause_circle_fill,
              color: notice.warning ? palette.warning : palette.faint,
              size: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notice.message,
                style: TextStyle(color: palette.ink, fontSize: 13, height: 1.3),
              ),
            ),
            if (notice.onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_right,
                color: palette.faint,
                size: 14,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
