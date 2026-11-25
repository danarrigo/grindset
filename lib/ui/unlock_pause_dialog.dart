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
  });

  /// What is being unlocked, as in "end this focus session early".
  final String what;
  final int seconds;

  /// Why it is blocked, as in "during Focus hours".
  final String because;

  /// The label of the button that goes ahead.
  final String action;

  @override
  State<UnlockPauseDialog> createState() => _UnlockPauseDialogState();
}

class _UnlockPauseDialogState extends State<UnlockPauseDialog>
    with WidgetsBindingObserver {
  final _reason = TextEditingController();
  late int _left = widget.seconds;
  Timer? _timer;

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

  String get _wait =>
      '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _left <= 0 && _reason.text.trim().isNotEmpty;
    return AlertDialog(
      scrollable: true,
      title: const Text('Why do you need this?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Blocking is on ${widget.because}. Before you ${widget.what}, '
            'say why and take a moment. Leaving Grindset starts the wait again.',
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Never mind'),
        ),
        FilledButton(
          key: const ValueKey('unlock-continue'),
          onPressed: ready
              ? () => Navigator.pop(context, _reason.text.trim())
              : null,
          child: Text(_left > 0 ? 'Wait $_wait' : widget.action),
        ),
      ],
    );
  }
}
