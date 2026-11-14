import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/platform/app_updates.dart';
import 'package:lockin/ui/updates_panel.dart';

Widget screen(UpdatesPanel panel) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(20), child: panel),
    ),
  ),
);

void main() {
  for (final android in [false, true]) {
    testWidgets(
      'explicit check and browser download for ${android ? 'Android' : 'Windows'}',
      (tester) async {
        var checks = 0;
        final opened = <Uri>[];
        await tester.pumpWidget(
          screen(
            UpdatesPanel(
              android: android,
              loadVersion: () async => '1.1.0',
              loadRelease: () async {
                checks++;
                return AppRelease(
                  version: '1.2.0',
                  notes: 'New update checks.',
                );
              },
              openDownload: (url) async {
                opened.add(url);
                return true;
              },
            ),
          ),
        );
        expect(checks, 0);
        expect(opened, isEmpty);
        await tester.tap(find.text('Check for updates'));
        await tester.pumpAndSettle();
        expect(find.text('Grindset 1.2.0 is available'), findsOneWidget);
        expect(find.text('New update checks.'), findsOneWidget);
        expect(checks, 1);
        expect(opened, isEmpty);
        await tester.ensureVisible(find.text('Download update'));
        await tester.tap(find.text('Download update'));
        await tester.pumpAndSettle();
        expect(
          opened.single.path,
          endsWith(android ? 'android-arm64.apk' : 'windows-x64-setup.exe'),
        );
        expect(
          find.textContaining('Download opened in your browser'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('equal and older releases do not offer installation', (
    tester,
  ) async {
    for (final version in ['1.1.0', '1.0.0']) {
      await tester.pumpWidget(
        screen(
          UpdatesPanel(
            key: ValueKey(version),
            android: false,
            loadVersion: () async => '1.1.0',
            loadRelease: () async => AppRelease(version: version, notes: ''),
          ),
        ),
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No newer release found'), findsOneWidget);
      expect(find.text('Download update'), findsNothing);
    }
  });

  testWidgets('failed checks remain retryable without false success', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        UpdatesPanel(
          android: false,
          loadVersion: () async => '1.1.0',
          loadRelease: () async => throw Exception('Offline'),
        ),
      ),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not check for updates'), findsOneWidget);
    expect(find.textContaining('No newer release found'), findsNothing);
    expect(find.text('Download update'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('navigating away during a check does not update disposed UI', (
    tester,
  ) async {
    final pending = Completer<AppRelease>();
    await tester.pumpWidget(
      screen(
        UpdatesPanel(
          android: false,
          loadVersion: () async => '1.1.0',
          loadRelease: () => pending.future,
        ),
      ),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(AppRelease(version: '1.2.0', notes: 'Changes'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
