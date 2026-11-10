// THROWAWAY: Focus-screen directions on /?variant=A|B|C|D.
// The minimal D direction can hide prototype chrome with &clean=1.
// Preview only. In-memory timer state; no database, auth, tracking or blocking.
// Keep this entrypoint on the design branch, not the production main branch.
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  usePathUrlStrategy();
  runApp(const _FocusPrototype());
}

class _FocusPrototype extends StatefulWidget {
  const _FocusPrototype();
  @override
  State<_FocusPrototype> createState() => _PrototypeState();
}

class _PrototypeState extends State<_FocusPrototype> {
  static const _names = ['Clock', 'Focus settings', 'Control panel', 'Minimal'];
  static const _tabs = ['Focus', 'Activity', 'Rules', 'Devices', 'Settings'];
  static const _icons = [
    CupertinoIcons.scope,
    CupertinoIcons.chart_bar,
    CupertinoIcons.shield,
    CupertinoIcons.desktopcomputer,
    CupertinoIcons.gear_alt,
  ];
  late String _variant;
  late bool _clean;
  late BuildContext _viewContext;
  int _minutes = 25;
  bool _break = false;
  DateTime? _end;
  late final Timer _ticker;
  bool get _running => _end != null && _end!.isAfter(DateTime.now());
  bool get _light => _variant == 'B';
  int get _index => _variant.codeUnitAt(0) - 65;
  Color get _ink => _light ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _secondary =>
      _light ? const Color(0xFF737379) : const Color(0xFFA7A7AD);
  Color get _accent => ['A', 'D'].contains(_variant)
      ? const Color(0xFFFF9F0A)
      : const Color(0xFF007AFF);
  String get _mode => _break ? 'Break' : 'Focus';
  String get _action => _running
      ? 'End session'
      : _break
      ? 'Start break'
      : 'Lock in';
  Map<String, Object?> get _state => {
    'variant': _variant,
    'direction': _names[_index],
    'clean_preview': _clean,
    'minutes': _minutes,
    'phase': _break ? 'break' : 'focus',
    'running': _running,
    'remaining_seconds': _remaining.inSeconds,
    'focused_today_minutes': 0,
    'tracking_connected': false,
    'persistence': false,
  };
  Duration get _remaining =>
      _running ? _end!.difference(DateTime.now()) : Duration(minutes: _minutes);
  String get _clock {
    final seconds = _remaining.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final requested = Uri.base.queryParameters['variant'] ?? 'D';
    _variant = ['A', 'B', 'C', 'D'].contains(requested) ? requested : 'D';
    _clean = Uri.base.queryParameters['clean'] == '1';
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_end != null) {
        setState(() {
          if (!_running) _end = null;
        });
      }
    });
    HardwareKeyboard.instance.addHandler(_keys);
    _trace();
  }

  @override
  void dispose() {
    _ticker.cancel();
    HardwareKeyboard.instance.removeHandler(_keys);
    super.dispose();
  }

  bool _keys(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.findAncestorWidgetOfExactType<EditableText>() != null ||
        focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<CupertinoTimerPicker>() != null) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _cycle(-1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _cycle(1);
      return true;
    }
    return false;
  }

  void _trace() => debugPrint('FOCUS PROTOTYPE ${jsonEncode(_state)}');
  void _cycle(int change) {
    setState(
      () => _variant = String.fromCharCode(
        65 + (_index + change) % _names.length,
      ),
    );
    SystemNavigator.routeInformationUpdated(
      uri: Uri(
        path: '/',
        queryParameters: {...Uri.base.queryParameters, 'variant': _variant},
      ),
      replace: true,
    );
    _trace();
  }

  void _toggle() {
    setState(
      () => _end = _running
          ? null
          : DateTime.now().add(Duration(minutes: _minutes)),
    );
    _trace();
  }

  void _preset(int value) {
    setState(() {
      _minutes = value;
      _end = null;
    });
    _trace();
  }

  void _phase(bool rest) {
    setState(() {
      _break = rest;
      _minutes = rest ? 5 : 25;
      _end = null;
    });
    _trace();
  }

  void _details([String? title]) {
    showCupertinoModalPopup<void>(
      context: _viewContext,
      builder: (context) => CupertinoActionSheet(
        title: Text(title ?? 'Prototype state'),
        message: Text(
          title == null ? const JsonEncoder.withIndent('  ').convert(_state) : 'Visual prototype only. No account, app blocking or system tracking is connected.',
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ),
    );
  }

  void _duration() {
    showCupertinoModalPopup<void>(
      context: _viewContext,
      builder: (context) => Container(
        height: 310,
        color: _light ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
              CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hm,
                initialTimerDuration: Duration(minutes: _minutes),
                onTimerDurationChanged: (duration) =>
                    _preset(duration.inMinutes.clamp(1, 1440)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) {
      return const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: Text('Design prototype unavailable in release builds.'),
          ),
        ),
      );
    }
    final brightness = _light ? Brightness.light : Brightness.dark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      title: 'Lockin design prototype',
      theme: ThemeData(
        brightness: brightness,
        fontFamily: 'Inter',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: brightness,
        ),
        cupertinoOverrideTheme: CupertinoThemeData(
          brightness: brightness,
          primaryColor: _accent,
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(
              fontFamily: 'Inter',
              color: _ink,
              fontSize: 16,
            ),
          ),
        ),
      ),
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) {
          _viewContext = context;
          return Scaffold(
            backgroundColor: _light ? const Color(0xFFF2F2F7) : Colors.black,
            body: Column(
              children: [
                Expanded(
                  child: switch (_variant) {
                    'A' => _clockDirection(),
                    'B' => _focusDirection(),
                    'D' => _minimalDirection(),
                    _ => _controlDirection(),
                  },
                ),
                if (!_clean) _switcher(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _switcher() => Container(
    color: const Color(0xFF171719),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Row(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.all(8),
              onPressed: () => _cycle(-1),
              child: const Icon(
                CupertinoIcons.chevron_left,
                color: Colors.white,
                size: 19,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PROTOTYPE $_variant · ${_names[_index]}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_minutes min · ${_running ? 'running' : 'idle'} · memory only',
                    style: const TextStyle(
                      color: Color(0xFFB9B9C0),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(8),
              onPressed: () => _cycle(1),
              child: const Icon(
                CupertinoIcons.chevron_right,
                color: Colors.white,
                size: 19,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              onPressed: _details,
              child: const Icon(
                CupertinoIcons.info_circle,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _round(
    IconData icon,
    VoidCallback pressed, {
    Color? fill,
    Color? ink,
    double size = 44,
  }) => SizedBox(
    width: size,
    height: size,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      color: fill ?? (_light ? Colors.white : const Color(0xFF242426)),
      borderRadius: BorderRadius.circular(size / 2),
      onPressed: pressed,
      child: Icon(icon, color: ink ?? _ink, size: size > 60 ? 28 : 21),
    ),
  );

  Widget _dock({bool glass = false}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: _Glass(
        radius: 32,
        blur: glass ? 28 : 18,
        color: _light
            ? Colors.white.withValues(alpha: .94)
            : const Color(0xFF28282B).withValues(alpha: .87),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    borderRadius: BorderRadius.circular(28),
                    color: i == 0
                        ? (_light
                              ? const Color(0xFFEAEAF0)
                              : Colors.black.withValues(alpha: .65))
                        : Colors.transparent,
                    onPressed: () {
                      if (i != 0) _details(_tabs[i]);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _icons[i],
                          size: 22,
                          color: i == 0 ? _accent : _ink,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tabs[i],
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: i == 0 ? _accent : _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  // D: one compact utility. Time, one action, and a menu. No dashboard chrome.
  Widget _minimalDirection() => LayoutBuilder(
    builder: (context, box) {
      final compactWindow = box.maxWidth >= 620;
      final panel = ColoredBox(
        color: const Color(0xFF09090A),
        child: SafeArea(
          minimum: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Lockin',
                      style: TextStyle(
                        color: Color(0xFFE5E5EA),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  _round(
                    CupertinoIcons.ellipsis,
                    _minimalMenu,
                    size: 44,
                    fill: const Color(0xFF1C1C1E),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: _running ? 'Time remaining' : 'Session duration',
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
                      const SizedBox(height: 42),
                      _round(
                        _running
                            ? CupertinoIcons.stop_fill
                            : CupertinoIcons.play_fill,
                        _toggle,
                        size: 84,
                        fill: _running
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFF073B1D),
                        ink: _running ? Colors.white : const Color(0xFF30D158),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        _action,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _running
                              ? const Color(0xFFBFBFC6)
                              : const Color(0xFF30D158),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Text(
                'Timer preview',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
              ),
            ],
          ),
        ),
      );
      if (!compactWindow) return panel;
      return ColoredBox(
        color: const Color(0xFFDEDEE3),
        child: Center(
          child: Container(
            width: 400,
            height: 560,
            margin: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .17),
                  blurRadius: 44,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: panel,
            ),
          ),
        ),
      );
    },
  );

  void _minimalMenu() {
    showCupertinoModalPopup<void>(
      context: _viewContext,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Lockin'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _duration();
            },
            child: Text('Duration · $_minutes min'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _phase(!_break);
            },
            child: Text(_break ? 'Switch to focus' : 'Take a 5-minute break'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _details('Activity and settings');
            },
            child: const Text('Activity & settings'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _details();
            },
            child: const Text('About this preview'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // A: Clock's high-contrast working surface, large numerals, circular actions,
  // real controls and flat rows. No website masthead or giant CTA rectangle.
  Widget _clockDirection() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 760;
      return Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                wide ? 40 : 24,
                wide ? 30 : 20,
                wide ? 40 : 24,
                120,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 670),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lockin',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.9,
                              ),
                            ),
                          ),
                          _round(CupertinoIcons.slider_horizontal_3, _duration),
                          const SizedBox(width: 10),
                          _round(
                            CupertinoIcons.gear_alt,
                            () => _details('Settings'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _running ? '$_mode in progress' : '$_mode timer',
                        style: TextStyle(color: _secondary, fontSize: 15),
                      ),
                      SizedBox(height: wide ? 52 : 44),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          _clock,
                          style: TextStyle(
                            color: _ink,
                            fontSize: wide ? 112 : 88,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: CupertinoButton(
                          onPressed: _duration,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_minutes minutes',
                                style: TextStyle(
                                  color: _secondary,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                CupertinoIcons.chevron_down,
                                size: 12,
                                color: _secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              _round(
                                CupertinoIcons.moon,
                                () => _phase(!_break),
                                size: 76,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _break ? 'Focus' : 'Break',
                                style: TextStyle(
                                  color: _secondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              _round(
                                _running
                                    ? CupertinoIcons.stop_fill
                                    : CupertinoIcons.play_fill,
                                _toggle,
                                size: 76,
                                fill: const Color(0xFF073B1D),
                                ink: const Color(0xFF30D158),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _action,
                                style: const TextStyle(
                                  color: Color(0xFF30D158),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 38),
                      Text(
                        'Presets',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final minutes in [25, 45, 60]) _clockRow(minutes),
                      const SizedBox(height: 22),
                      _flatRow('Focused today', '0 min', dark: true),
                      _flatRow('Daily limits', 'Not set', dark: true),
                      const SizedBox(height: 16),
                      Text(
                        'Visual preview. No system tracking or blocking connected.',
                        style: TextStyle(color: _secondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 20, right: 20, bottom: 16, child: _dock()),
        ],
      );
    },
  );
  Widget _clockRow(int minutes) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF28282A), width: .6)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$minutes:00',
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 36,
              fontWeight: FontWeight.w300,
              letterSpacing: -1,
            ),
          ),
        ),
        _round(
          CupertinoIcons.play_fill,
          () {
            _preset(minutes);
            _toggle();
          },
          fill: const Color(0xFF073B1D),
          ink: const Color(0xFF30D158),
          size: 42,
        ),
      ],
    ),
  );

  // B: Focus's grouped native settings, a clear mode identity, blue action,
  // compact information density, and a contextual desktop sidebar.
  Widget _focusDirection() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 800;
      return Row(
        children: [
          if (wide)
            Container(
              width: 200,
              color: const Color(0xFFE8E8ED),
              padding: const EdgeInsets.fromLTRB(15, 28, 15, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 12, bottom: 30),
                    child: Text(
                      'Lockin',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  for (var i = 0; i < _tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: CupertinoButton(
                        onPressed: () {
                          if (i != 0) _details(_tabs[i]);
                        },
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        color: i == 0
                            ? const Color(0xFFD6D6DD)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        child: Row(
                          children: [
                            Icon(
                              _icons[i],
                              size: 18,
                              color: const Color(0xFF47474F),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _tabs[i],
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: const Color(0xFF25252A),
                                fontWeight: i == 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Design preview\nTracking not connected',
                      style: TextStyle(
                        color: Color(0xFF737379),
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 44 : 22,
                      wide ? 34 : 20,
                      wide ? 44 : 22,
                      wide ? 30 : 112,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 530),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Focus',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      color: _ink,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                ),
                                _round(
                                  CupertinoIcons.ellipsis,
                                  () => _details('Focus options'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                22,
                                26,
                                22,
                                22,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEEEFF),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.scope,
                                      size: 34,
                                      color: Color(0xFF5856D6),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  Text(
                                    _running
                                        ? '$_mode in progress'
                                        : '$_mode session',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _running
                                        ? _clock
                                        : '$_minutes-minute session',
                                    style: TextStyle(
                                      fontSize: _running ? 48 : 14,
                                      color: _running ? _ink : _secondary,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: _running ? -2 : 0,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    child: CupertinoButton.filled(
                                      onPressed: _toggle,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Text(
                                        _action,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                            _group([
                              _setting(
                                CupertinoIcons.timer,
                                const Color(0xFFFF9500),
                                'Duration',
                                '$_minutes min',
                                _duration,
                              ),
                              _setting(
                                CupertinoIcons.shield,
                                const Color(0xFF5856D6),
                                'Blocklist',
                                'Not configured',
                                () => _details('Blocklist'),
                              ),
                              _setting(
                                CupertinoIcons.moon,
                                const Color(0xFF007AFF),
                                'Break',
                                '5 min',
                                () => _phase(!_break),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'Limits and schedules stay active outside focus sessions. Blocking is not connected in this prototype.',
                                style: TextStyle(
                                  color: _secondary,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                bottom: 8,
                              ),
                              child: Text(
                                'TODAY',
                                style: TextStyle(
                                  color: _secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            _group([
                              _setting(
                                CupertinoIcons.hourglass,
                                const Color(0xFF007AFF),
                                'Focused time',
                                '0 min',
                                () => _details('Focused time'),
                              ),
                              _setting(
                                CupertinoIcons.chart_bar,
                                const Color(0xFF34C759),
                                'Daily limits',
                                'Not set',
                                () => _details('Daily limits'),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!wide)
                  Positioned(left: 18, right: 18, bottom: 12, child: _dock()),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget _group(List<Widget> rows) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: .5,
              indent: 57,
              color: Color(0xFFE3E3E8),
            ),
          rows[i],
        ],
      ],
    ),
  );
  Widget _setting(
    IconData icon,
    Color color,
    String label,
    String value,
    VoidCallback tap,
  ) => CupertinoButton(
    onPressed: tap,
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: _ink),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: _secondary,
          ),
        ),
        const SizedBox(width: 7),
        const Icon(
          CupertinoIcons.chevron_right,
          size: 12,
          color: Color(0xFFB7B7BE),
        ),
      ],
    ),
  );

  // C: a compact system control surface. Material is limited to controls and
  // navigation; there is no decorative glass dashboard or invented analytics.
  Widget _controlDirection() => Stack(
    children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF333F58), Color(0xFF30313C), Color(0xFF1B2734)],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 115),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Lockin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.8,
                          ),
                        ),
                      ),
                      _round(
                        CupertinoIcons.gear_alt,
                        () => _details('Settings'),
                        fill: Colors.white.withValues(alpha: .10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  _Glass(
                    radius: 30,
                    blur: 30,
                    color: Colors.white.withValues(alpha: .13),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: const Icon(
                                  CupertinoIcons.scope,
                                  size: 29,
                                  color: Color(0xFF6762D9),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _mode,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _running
                                          ? 'Session in progress'
                                          : 'Not active',
                                      style: const TextStyle(
                                        color: Color(0xFFCED0D9),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Text(
                            _running ? _clock : '$_minutes',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 76,
                              fontWeight: FontWeight.w200,
                              letterSpacing: -3,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (!_running)
                            const Text(
                              'minutes',
                              style: TextStyle(
                                color: Color(0xFFCED0D9),
                                fontSize: 15,
                              ),
                            ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  onPressed: _duration,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  color: Colors.white.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(22),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.timer,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                      SizedBox(width: 7),
                                      Text(
                                        'Duration',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CupertinoButton(
                                  onPressed: _toggle,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  child: Text(
                                    _action,
                                    style: const TextStyle(
                                      color: Color(0xFF252638),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _Glass(
                    radius: 22,
                    blur: 24,
                    color: Colors.white.withValues(alpha: .08),
                    child: Column(
                      children: [
                        _controlRow(
                          CupertinoIcons.hourglass,
                          'Focused today',
                          '0 min',
                        ),
                        Divider(
                          height: 1,
                          indent: 22,
                          endIndent: 22,
                          color: Colors.white.withValues(alpha: .1),
                        ),
                        _controlRow(
                          CupertinoIcons.shield,
                          'Daily limits',
                          'Not set',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Visual prototype. No system tracking or blocking connected.',
                      style: TextStyle(
                        color: Color(0xFFCED0D9),
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(left: 20, right: 20, bottom: 16, child: _dock(glass: true)),
    ],
  );
  Widget _controlRow(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFDFE1EA), size: 19),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: Color(0xFFCED0D9), fontSize: 13),
        ),
      ],
    ),
  );
  Widget _flatRow(String title, String value, {bool dark = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: TextStyle(color: _secondary, fontSize: 14)),
        ),
        Text(value, style: TextStyle(color: _ink, fontSize: 14)),
      ],
    ),
  );
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    required this.color,
    required this.radius,
    required this.blur,
  });
  final Widget child;
  final Color color;
  final double radius;
  final double blur;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: Colors.white.withValues(alpha: .13),
            width: .6,
          ),
        ),
        child: child,
      ),
    ),
  );
}
