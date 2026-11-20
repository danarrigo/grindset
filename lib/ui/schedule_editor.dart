import 'package:flutter/material.dart';

import '../core/activity.dart';

/// A time window being edited. Starts as weekdays 9:00 to 17:00.
class ScheduleDraft {
  ScheduleDraft([ScheduleWindow? window])
    : days = {...?window?.weekdays},
      from = TimeOfDay(
        hour: (window?.startMinute ?? 540) ~/ 60,
        minute: (window?.startMinute ?? 540) % 60,
      ),
      until = TimeOfDay(
        hour: (window?.endMinute ?? 1020) ~/ 60,
        minute: (window?.endMinute ?? 1020) % 60,
      ) {
    if (window == null) days.addAll({1, 2, 3, 4, 5});
  }
  final Set<int> days;
  TimeOfDay from;
  TimeOfDay until;

  /// Throws [ArgumentError] while no day is picked or both times are equal.
  ScheduleWindow save() => ScheduleWindow(
    weekdays: days,
    startMinute: from.hour * 60 + from.minute,
    endMinute: until.hour * 60 + until.minute,
  );
}

/// Outlined when off, brand green when on, so every option reads as tappable.
Widget choiceChip(
  BuildContext context, {
  required String label,
  String? semanticsLabel,
  required bool selected,
  required ValueChanged<bool> onSelected,
}) {
  final colors = Theme.of(context).colorScheme;
  return ChoiceChip(
    label: Text(label, semanticsLabel: semanticsLabel),
    selected: selected,
    onSelected: onSelected,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    backgroundColor: colors.surface,
    selectedColor: colors.primary,
    side: BorderSide(color: selected ? colors.primary : colors.outline),
    labelStyle: TextStyle(
      fontWeight: FontWeight.w600,
      color: selected ? colors.onPrimary : colors.onSurface,
    ),
  );
}

/// Day chips and from/to times for each window, plus "Add more times".
/// The parent owns [drafts]; [onChanged] asks it to rebuild.
class ScheduleWindowsEditor extends StatelessWidget {
  const ScheduleWindowsEditor({
    super.key,
    required this.drafts,
    required this.onChanged,
  });
  final List<ScheduleDraft> drafts;
  final VoidCallback onChanged;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  Future<void> _pickTime(
    BuildContext context,
    ScheduleDraft draft,
    bool start,
  ) async {
    final value = await showTimePicker(
      context: context,
      initialTime: start ? draft.from : draft.until,
      initialEntryMode: MediaQuery.sizeOf(context).width >= 840
          ? TimePickerEntryMode.input
          : TimePickerEntryMode.dial,
    );
    if (value == null) return;
    if (start) {
      draft.from = value;
    } else {
      draft.until = value;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final draft in drafts)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var day = 1; day <= 7; day++)
                    choiceChip(
                      context,
                      label: _letters[day - 1],
                      semanticsLabel: _days[day - 1],
                      selected: draft.days.contains(day),
                      onSelected: (value) {
                        if (value) {
                          draft.days.add(day);
                        } else {
                          draft.days.remove(day);
                        }
                        onChanged();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: () => _pickTime(context, draft, true),
                    child: Text(draft.from.format(context)),
                  ),
                  const Text('to'),
                  OutlinedButton(
                    onPressed: () => _pickTime(context, draft, false),
                    child: Text(draft.until.format(context)),
                  ),
                  if (drafts.length > 1)
                    IconButton(
                      tooltip: 'Remove these times',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        drafts.remove(draft);
                        onChanged();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      TextButton.icon(
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: drafts.length >= 64
            ? null
            : () {
                drafts.add(ScheduleDraft());
                onChanged();
              },
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add more times'),
      ),
    ],
  );
}
