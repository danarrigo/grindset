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
  testWidgets('set times start as weekdays 9 to 5 and can have more windows', (
    tester,
  ) async {
    ActivityRule? saved;
    await open(
      tester,
      RuleEditor(sources: {'windows:discord.exe'}, timezone: 'Asia/Jakarta'),
      (value) => saved = value,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Search apps and websites'),
      'discord',
    );
    await tester.pumpAndSettle();
    // Picking an app by name picks all of it: its apps and its website.
    await tester.tap(find.widgetWithText(ListTile, 'Discord'));
    await tester.pumpAndSettle();
    await tap(tester, 'At set times');
    expect(find.textContaining('Asia/Jakarta'), findsOneWidget);
    await tap(tester, 'Add more times');
    await tap(tester, 'Save rule');
    expect(saved!.name, 'Discord');
    expect(
      saved!.sources,
      containsAll(['windows:discord.exe', 'web:discord.com']),
    );
    expect(saved!.schedules, hasLength(2));
    expect(saved!.schedules.first.weekdays, {1, 2, 3, 4, 5});
    expect(saved!.schedules.first.startMinute, 540);
    expect(saved!.schedules.first.endMinute, 1020);
  });
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
        find.widgetWithText(TextField, 'Search apps and websites'),
        'Test App',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Test App'));
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

  testWidgets('a whole company is one search away, and parts can be unticked', (
    tester,
  ) async {
    ActivityRule? saved;
    await open(tester, RuleEditor(sources: {}), (value) => saved = value);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search apps and websites'),
      'google',
    );
    await tester.pumpAndSettle();
    await tap(tester, 'All of Google');
    expect(find.text('All 12 Google services'), findsOneWidget);
    await tester.tap(find.byTooltip('Pick Google services one by one'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Gmail'));
    await tester.tap(find.widgetWithText(ListTile, 'Gmail'));
    await tester.pumpAndSettle();
    // A partly chosen company lists each app it still covers.
    expect(find.text('All 12 Google services'), findsNothing);
    await tap(tester, 'Save rule');
    expect(saved!.name, 'Google');
    expect(
      saved!.sources,
      containsAll([
        'web:google.com',
        'web:youtube.com',
        'android:com.google.android.youtube',
      ]),
    );
    expect(saved!.sources, isNot(contains('android:com.google.android.gm')));
    expect(saved!.sources, isNot(contains('web:gmail.com')));
  });

  testWidgets(
    'most-used apps come first and phone apps are picked by name, never by ID',
    (tester) async {
      ActivityRule? saved;
      await open(
        tester,
        RuleEditor(
          sources: {},
          recentUse: const [
            (source: 'web:youtube.com', duration: Duration(hours: 2)),
            (source: 'windows:chrome.exe', duration: Duration(hours: 5)),
            (
              source: 'android:com.example.game',
              duration: Duration(minutes: 40),
            ),
            (
              source: 'android:com.google.android.youtube',
              duration: Duration(minutes: 30),
            ),
          ],
          loadInstalledApps: () async => {
            'android:com.example.game': 'Pocket Knights',
            'android:com.example.notes': 'Field Notes',
          },
        ),
        (value) => saved = value,
      );
      expect(find.text('You use these most'), findsOneWidget);
      // YouTube's app and site add up; the whole browser is never suggested.
      expect(find.text('2 hr 30 min this week'), findsOneWidget);
      expect(find.text('Chrome'), findsNothing);
      expect(find.text('40 min this week'), findsOneWidget);
      // An installed app with no catalog entry shows by its own name.
      await tester.enterText(
        find.widgetWithText(TextField, 'Search apps and websites'),
        'field',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Field Notes'));
      await tester.pumpAndSettle();
      await tap(tester, 'Save rule');
      // Named after the app picked; nothing had to be typed.
      expect(saved!.name, 'Field Notes');
      expect(saved!.sources, ['android:com.example.notes']);
    },
  );

  testWidgets('the rule is named after what was picked until a name is typed', (
    tester,
  ) async {
    ActivityRule? saved;
    await open(tester, RuleEditor(sources: {}), (value) => saved = value);
    expect(find.widgetWithText(TextFormField, 'Rule name'), findsNothing);
    final search = find.widgetWithText(TextField, 'Search apps and websites');
    for (final app in ['YouTube', 'TikTok', 'Reddit']) {
      await tester.enterText(search, app.toLowerCase());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, app).first);
      await tester.pumpAndSettle();
    }
    final name = find.widgetWithText(TextFormField, 'Rule name');
    String current() => tester.widget<TextFormField>(name).controller!.text;
    expect(current(), 'YouTube, TikTok and 1 more');
    await tester.tap(find.byTooltip('Remove YouTube'));
    await tester.pumpAndSettle();
    expect(current(), 'TikTok and Reddit');
    await tester.enterText(name, 'Scrolling');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Reddit'));
    await tester.pumpAndSettle();
    expect(current(), 'Scrolling');
    await tap(tester, 'Save rule');
    expect(saved!.name, 'Scrolling');
  });
}
