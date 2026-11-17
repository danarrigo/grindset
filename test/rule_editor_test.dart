import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/platform/windows_apps.dart';
import 'package:lockin/ui/rule_editor.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    RuleEditor editor,
    void Function(ActivityRule?) result,
  ) async {
    tester.view.physicalSize = const Size(1120, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<ActivityRule>(
                  context: context,
                  builder: (_) => editor,
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  ActivityRule existing() => ActivityRule(
    id: 'existing',
    name: 'Distractions',
    sources: ['windows:discord.exe'],
    focusBlock: false,
    dailyMinutes: 47,
    schedules: [
      ScheduleWindow(
        weekdays: [1, 2, 3, 4, 5],
        startMinute: 540,
        endMinute: 720,
      ),
      ScheduleWindow(weekdays: [5], startMinute: 1320, endMinute: 120),
    ],
  );

  testWidgets(
    'editing preserves every existing schedule, budget and identity',
    (tester) async {
      final rule = existing();
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(sources: {}, rule: rule, timezone: 'Europe/London'),
        (value) => saved = value,
      );
      await tap(tester, 'Save rule');
      expect(saved!.toJson(), rule.toJson());
    },
  );
  testWidgets(
    'scheduled focus starts with explicit weekday hours, no timer or daily budget',
    (tester) async {
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(
          sources: {'windows:discord.exe'},
          scheduledFocus: true,
          timezone: 'Asia/Jakarta',
        ),
        (value) => saved = value,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Search apps'),
        'discord',
      );
      await tester.pumpAndSettle();
      // Picking an app by name picks all of it: its apps and its website.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Discord'));
      await tester.pumpAndSettle();
      await tap(tester, 'Add more times');
      await tap(tester, 'Save rule');
      expect(saved!.name, 'Focus hours');
      expect(saved!.focusBlock, isFalse);
      expect(saved!.dailyMinutes, isNull);
      expect(
        saved!.sources,
        containsAll(['windows:discord.exe', 'web:discord.com']),
      );
      expect(saved!.schedules, hasLength(2));
      expect(saved!.schedules.first.weekdays, {1, 2, 3, 4, 5});
      expect(saved!.schedules.first.startMinute, 540);
      expect(saved!.schedules.first.endMinute, 1020);
    },
  );
  testWidgets(
    'a schedule can be removed without dropping another overnight window',
    (tester) async {
      final rule = existing();
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(sources: {}, rule: rule),
        (value) => saved = value,
      );
      await tester.ensureVisible(find.byTooltip('Remove these times').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove these times').first);
      await tester.pumpAndSettle();
      await tap(tester, 'Save rule');
      expect(saved!.schedules.single.toJson(), rule.schedules.last.toJson());
      expect(saved!.dailyMinutes, 47);
      expect(saved!.focusBlock, isFalse);
    },
  );
  testWidgets(
    'empty weekdays are rejected without changing the original rule',
    (tester) async {
      final rule = ActivityRule(
        id: 'one',
        name: 'One',
        sources: ['windows:discord.exe'],
        schedules: [
          ScheduleWindow(weekdays: [1], startMinute: 540, endMinute: 1020),
        ],
      );
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(sources: {}, rule: rule),
        (value) => saved = value,
      );
      await tap(tester, 'M');
      await tap(tester, 'Save rule');
      expect(saved, isNull);
      expect(find.textContaining('Choose weekdays'), findsOneWidget);
      expect(rule.schedules.single.weekdays, {1});
    },
  );

  testWidgets(
    'PC discovery is explicit, searchable, and accepts executable names with spaces',
    (tester) async {
      var loads = 0;
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(
          sources: {},
          loadWindowsApps: () async {
            loads++;
            return [
              const WindowsApp(
                source: 'windows:test app.exe',
                name: 'Test App',
                running: true,
              ),
            ];
          },
        ),
        (value) => saved = value,
      );
      expect(loads, 0);
      await tap(tester, 'Show apps on this PC');
      expect(loads, 1);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search apps'),
        'Test App',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Test App'));
      await tester.pumpAndSettle();
      await tap(tester, 'Save rule');
      expect(saved!.name, 'Test App');
      expect(saved!.sources, {'windows:test app.exe'});
    },
  );
  testWidgets(
    'browse cancellation and scan errors do not erase existing selections',
    (tester) async {
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(
          sources: {},
          rule: existing(),
          loadWindowsApps: () async => throw StateError('Scan unavailable'),
          browseWindowsApp: () async => null,
        ),
        (value) => saved = value,
      );
      await tap(tester, 'Add another app or website');
      await tap(tester, 'Show apps on this PC');
      expect(find.textContaining('Scan unavailable'), findsOneWidget);
      await tap(tester, 'Browse');
      await tap(tester, 'Save rule');
      expect(saved!.toJson(), existing().toJson());
    },
  );
  testWidgets('browsing selects the app without retaining executable paths', (
    tester,
  ) async {
    ActivityRule? saved;
    await open(
      tester,
      RuleEditor(
        sources: {},
        browseWindowsApp: () async => const WindowsApp(
          source: 'windows:code.exe',
          name: 'Visual Studio Code',
        ),
      ),
      (value) => saved = value,
    );
    await tap(tester, 'Browse');
    await tap(tester, 'Save rule');
    expect(saved!.sources, {'windows:code.exe'});
    expect(saved!.name, 'Visual Studio Code');
  });
}
