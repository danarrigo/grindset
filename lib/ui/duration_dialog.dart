import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DurationDialog extends StatefulWidget {
  const DurationDialog({super.key, required this.initialMinutes});
  final int initialMinutes;
  @override
  State<DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<DurationDialog> {
  late final _input = TextEditingController(text: '${widget.initialMinutes}');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_input.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom duration'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _input,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onFieldSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Duration in minutes',
          helperText: 'Between 1 and 1440 minutes',
        ),
        validator: (value) {
          final minutes = int.tryParse(value ?? '') ?? 0;
          return minutes < 1 || minutes > 1440
              ? 'Choose 1 to 1440 minutes'
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Set duration')),
    ],
  );
}
