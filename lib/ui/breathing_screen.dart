import 'package:flutter/cupertino.dart';

import 'focus_screen.dart';

/// A calm minute before a focus session: breathe in for 4 seconds, out for
/// 6, then the session starts. Nothing is blocked until it does.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({
    super.key,
    required this.onDone,
    required this.onCancel,
    this.duration = const Duration(seconds: 60),
    this.showBrand = true,
  });

  /// Called once when the minute is over or "Start now" is tapped.
  final VoidCallback onDone;
  final VoidCallback onCancel;
  final Duration duration;
  final bool showBrand;

  static const _inhale = Duration(seconds: 4);
  static const _breath = Duration(seconds: 10);

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  var _done = false;

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _clock.forward();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = FocusPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: widget.showBrand
                  ? Text(
                      'Grindset',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    )
                  : null,
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, _) {
                final elapsed = widget.duration * _clock.value;
                final inBreath = Duration(
                  microseconds:
                      elapsed.inMicroseconds %
                      BreathingScreen._breath.inMicroseconds,
                );
                final inhaling = inBreath < BreathingScreen._inhale;
                final progress = inhaling
                    ? inBreath.inMicroseconds /
                          BreathingScreen._inhale.inMicroseconds
                    : (inBreath - BreathingScreen._inhale).inMicroseconds /
                          (BreathingScreen._breath - BreathingScreen._inhale)
                              .inMicroseconds;
                final eased = Curves.easeInOut.transform(progress);
                final size = 0.55 + 0.45 * (inhaling ? eased : 1 - eased);
                final left = ((widget.duration - elapsed).inMilliseconds / 1000)
                    .ceil();
                return Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 220,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: p.startInk.withValues(alpha: .25),
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: size,
                                heightFactor: size,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: p.start,
                                  ),
                                ),
                              ),
                              Text(
                                inhaling ? 'Breathe in' : 'Breathe out',
                                style: TextStyle(
                                  color: p.startInk,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Focus starts in ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 14,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 28),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          minimumSize: const Size(160, 48),
                          color: p.start,
                          borderRadius: BorderRadius.circular(24),
                          onPressed: _finish,
                          child: Text(
                            'Start now',
                            style: TextStyle(
                              color: p.startInk,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CupertinoButton(
                          minimumSize: const Size(160, 44),
                          onPressed: widget.onCancel,
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: p.muted, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
