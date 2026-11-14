import 'package:flutter/material.dart';

import '../core/activity.dart';

String scheduleSummary(BuildContext context, ScheduleWindow window) {
  final days = window.weekdays.length == 7
      ? 'Every day'
      : window.weekdays.length == 5 &&
            window.weekdays.containsAll({1, 2, 3, 4, 5})
      ? 'Mon-Fri'
      : ([...window.weekdays]..sort())
            .map(
              (day) => const [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ][day - 1],
            )
            .join(', ');
  String time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
  return '$days ${time(window.startMinute)} to ${time(window.endMinute)}${window.endMinute < window.startMinute ? ' (next day)' : ''}';
}
