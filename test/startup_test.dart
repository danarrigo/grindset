import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/main.dart' as application;

void main() {
  testWidgets(
    'an unusable data directory exposes an error without resetting data',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lockin-startup-'),
      ))!;
      final existing = File('${directory.path}/existing-file');
      addTearDown(() => directory.delete(recursive: true));
      await tester.runAsync(() async {
        await existing.writeAsString('Preserve this original file.');
        await application.main(['--data-dir=${existing.path}', '--background']);
      });
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Lockin could not open its local database or platform settings.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your data has not been reset.'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(existing.readAsString),
        'Preserve this original file.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
