import 'dart:async';

import 'package:flutter/material.dart';

/// The unlock pause: a reason and a short wait before loosening anything
/// while blocking is in force. Pops the reason, or null when cancelled.
///
/// The wait starts again if you leave the app, so it can't run out in the
/// background.
class UnlockPauseDialog extends StatefulWidget {
  const UnlockPauseDialog({
    super.key,
    required this.what,
    required this.seconds,
    required this.because,
    this.action = 'Continue',
    this.judge,
  });

  /// What is being unlocked, as in "end this focus session early".
  final String what;
  final int seconds;

  /// Why it is blocked, as in "during Focus hours".
  final String because;

  /// The label of the button that goes ahead.
  final String action;

  /// Asks an AI whether the reason is good enough. Null when not used. May
  /// throw an exception whose message is for people.
  final Future<({bool allow, String message})> Function(String reason)? judge;

  @override
  State<UnlockPauseDialog> createState() => _UnlockPauseDialogState();
}

class _UnlockPauseDialogState extends State<UnlockPauseDialog>
    with WidgetsBindingObserver {
  final _reason = TextEditingController();
  late int _left = widget.seconds;
  Timer? _timer;
  bool _checking = false;

  /// The AI's answer or why there is none, shown under the reason.
  String? _verdict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _left = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _left--);
      if (_left <= 0) timer.cancel();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _left > 0) {
      setState(_start);
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final reason = _reason.text.trim();
    final judge = widget.judge;
    if (judge == null) return Navigator.pop(context, reason);
    setState(() {
      _checking = true;
      _verdict = null;
    });
    try {
      final verdict = await judge(reason);
      if (!mounted) return;
      if (verdict.allow) return Navigator.pop(context, reason);
      // A no means waiting again before the next try.
      setState(() {
        _verdict = verdict.message.isEmpty ? 'Not this time.' : verdict.message;
        _start();
      });
    } catch (error) {
      if (mounted) setState(() => _verdict = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String get _wait =>
      '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _left <= 0 && _reason.text.trim().isNotEmpty && !_checking;
    return AlertDialog(
      scrollable: true,
      title: const Text('Why do you need this?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Blocking is on ${widget.because}. Before you ${widget.what}, '
            'say why and take a moment. Leaving Grindset starts the wait again.'
            '${widget.judge == null ? '' : ' An AI reads your reason and decides.'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('unlock-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'For example: a tutorial for work',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_verdict != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _verdict!,
                key: const ValueKey('unlock-verdict'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Never mind'),
        ),
        FilledButton(
          key: const ValueKey('unlock-continue'),
          onPressed: ready ? _continue : null,
          child: Text(
            _checking
                ? 'Asking AI…'
                : _left > 0
                ? 'Wait $_wait'
                : widget.judge == null
                ? widget.action
                : 'Ask AI',
          ),
        ),
      ],
    );
  }
}
