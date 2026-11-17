import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/focus_session.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/focus_screen.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _WindowsTracker extends NativeTracker {
  @override
  bool get isWindows => true;
  @override
  Future<bool> setWindowsForegroundWatch(bool enabled) async => true;
  @override
  bool get isAndroid => false;
  @override
  Future<bool> hasAccess() async => true;
  @override
  ForegroundApp? foreground() => null;
}

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'Windows restriction replaces the entire desktop workspace, not just the timer pane',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final store = LocalStore.memory();
      final controller = AppController(
        store: store,
        tracker: _WindowsTracker(),
      );
      await controller.initialize(poll: false);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      controller.blockedSource = 'windows:discord.exe';
      controller.blockMessage = 'Focus session in progress';
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Discord is restricted'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-3')), findsNothing);
      expect(tester.getSize(find.byType(Scaffold)), const Size(1280, 900));
      await tester.tap(find.text('Use other apps'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-3')), findsOneWidget);
    },
  );

  Future<(AppController, LocalStore)> open({DateTime Function()? clock}) async {
    final store = LocalStore.memory();
    final controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: clock ?? () => DateTime.utc(2026, 11, 10, 10),
    );
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize(poll: false);
    return (controller, store);
  }

  Future<void> navigate(WidgetTester tester, int page) async {
    final destination = find.byKey(ValueKey('nav-$page'));
    if (destination.evaluate().isEmpty) {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(destination);
    await tester.tap(destination);
    await tester.pumpAndSettle();
  }

  Future<void> customDuration(WidgetTester tester, String minutes) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Duration ·'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), minutes);
    await tester.tap(find.text('Set duration'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'data controls export without resetting and require explicit reset confirmation',
    (tester) async {
      final (controller, _) = await open();
      viewport(tester, const Size(390, 844));
      var exports = 0;
      var resets = 0;
      await tester.pumpWidget(
        LockinApp(
          controller: controller,
          exportData: () async {
            exports++;
            return true;
          },
          resetDevice: () async {
            resets++;
          },
        ),
      );
      await navigate(tester, 4);
      await tester.ensureVisible(find.text('Export data'));
      await tester.tap(find.text('Export data'));
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(resets, 0);
      await tester.ensureVisible(find.text('Reset this device'));
      await tester.tap(find.text('Reset this device'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cloud records and other devices are not deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(resets, 0);
      await tester.tap(find.text('Reset this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset and close'));
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('isolated Windows tracking does not promise sign-in startup', (
    tester,
  ) async {
    final store = LocalStore.memory();
    final controller = AppController(store: store, tracker: _WindowsTracker());
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize(poll: false);
    viewport(tester, const Size(800, 900));
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 4);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'This preview does not change Windows sign-in startup.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('start when you sign in to Windows'),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(controller.trackingEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lock in starts immediately without a setup form', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1200, 900));
    await tester.pumpWidget(LockinApp(controller: controller));
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('Lock in'), findsOneWidget);
    expect(find.byTooltip('More options'), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Focused'), findsNothing);
    expect(find.text('Daily limits'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FocusScreen),
        matching: find.text('Activity'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(FocusScreen),
        matching: find.text('Rules'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('nav-2')), findsOneWidget);
    await tester.tap(find.text('Lock in'));
    await tester.pumpAndSettle();
    expect(controller.session?.focusing(controller.now), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('End session'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
  });

  testWidgets(
    'countdown does not lose a second or show zero before its deadline',
    (tester) async {
      var now = DateTime.utc(2026, 11, 10, 10);
      final (controller, _) = await open(clock: () => now);
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.tap(find.text('Lock in'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(milliseconds: 1));
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      now = controller.session!.end.subtract(const Duration(milliseconds: 1));
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('0:01'), findsOneWidget);
      expect(find.text('Session complete'), findsNothing);
      now = controller.session!.end;
      await controller.refresh();
      await tester.pumpAndSettle();
      // A finished session resets to the next duration instead of 0:00.
      expect(find.text('0:00'), findsNothing);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Session complete'), findsOneWidget);
    },
  );

  testWidgets('a custom session survives closing and reopening SQLite', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('lockin-focus-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lockin.sqlite');
    var now = DateTime.utc(2026, 11, 10, 10);
    viewport(tester, const Size(400, 560));
    // Drift starts its isolate in the factory, so construction needs real time too.
    await tester.runAsync(() async {
      final firstStore = LocalStore.file(file);
      final first = AppController(
        store: firstStore,
        tracker: NativeTracker(),
        clock: () => now,
      );
      try {
        await first.initialize(poll: false);
        await first.setPreferredMinutes(SessionPhase.rest, 8);
        await first.startSession(
          const Duration(minutes: 37),
          SessionPhase.focus,
        );
      } finally {
        first.dispose();
        await firstStore.close();
      }
    });
    now = now.add(const Duration(minutes: 20));
    final restored = (await tester.runAsync(() async {
      final store = LocalStore.file(file);
      final controller = AppController(
        store: store,
        tracker: NativeTracker(),
        clock: () => now,
      );
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize(poll: false);
      return controller;
    }))!;
    await tester.pumpWidget(LockinApp(controller: restored));
    await tester.pumpAndSettle();
    expect(find.text('17:00'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
    expect(restored.preferredMinutes(SessionPhase.focus), 37);
    expect(restored.preferredMinutes(SessionPhase.rest), 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom duration validates input and starts the requested timer',
    (tester) async {
      final (controller, _) = await open();
      viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(LockinApp(controller: controller));
      await customDuration(tester, '0');
      expect(find.text('Choose 1 to 1440 minutes'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '37');
      await tester.tap(find.text('Set duration'));
      await tester.pumpAndSettle();
      expect(find.text('37:00'), findsOneWidget);
      await tester.tap(find.text('Lock in'));
      await tester.pumpAndSettle();
      expect(
        controller.session!.end.difference(controller.session!.start),
        const Duration(minutes: 37),
      );
      expect(find.text('37:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ending early does not replace the remembered duration with elapsed time',
    (tester) async {
      var now = DateTime.utc(2026, 11, 10, 10);
      final (controller, store) = await open(clock: () => now);
      viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(LockinApp(controller: controller));
      await customDuration(tester, '37');
      await tester.tap(find.text('Lock in'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 1));
      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End session').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = AppController(
        store: store,
        tracker: NativeTracker(),
        clock: () => now,
      );
      addTearDown(restored.dispose);
      await restored.initialize(poll: false);
      await tester.pumpWidget(LockinApp(controller: restored));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Duration · 37 min'), findsOneWidget);
    },
  );

  testWidgets('activity shows real focus time without stopping the timer', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 10, 10);
    final (controller, _) = await open(clock: () => now);
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.tap(find.text('Lock in'));
    await tester.pumpAndSettle();
    final sessionId = controller.session!.id;
    now = now.add(const Duration(minutes: 7));
    await controller.refresh();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Duration ·'), findsNothing);
    expect(find.text('Switch to break · 5 min'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await navigate(tester, 1);
    expect(find.text('Focused'), findsOneWidget);
    expect(find.text('7 min'), findsOneWidget);
    await navigate(tester, 0);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('Focused'), findsNothing);
    expect(controller.session!.id, sessionId);
  });

  testWidgets('duration choices are remembered without starting a session', (
    tester,
  ) async {
    final (controller, store) = await open();
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    await customDuration(tester, '37');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to break · 5 min'));
    await tester.pumpAndSettle();
    await customDuration(tester, '8');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to focus'));
    await tester.pumpAndSettle();
    expect(find.text('37:00'), findsOneWidget);
    expect(controller.session, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    final restored = AppController(store: store, tracker: NativeTracker());
    addTearDown(restored.dispose);
    await restored.initialize(poll: false);
    await tester.pumpWidget(LockinApp(controller: restored));
    await tester.pumpAndSettle();
    expect(find.text('37:00'), findsOneWidget);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Switch to break · 8 min'), findsOneWidget);
    expect(restored.session, isNull);
  });

  testWidgets('focus and break keep independent durations through the menu', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 10, 10);
    final (controller, _) = await open(clock: () => now);
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    await customDuration(tester, '37');
    await tester.tap(find.text('Lock in'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End session').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to break · 5 min'));
    await tester.pumpAndSettle();
    expect(find.text('5:00'), findsOneWidget);
    await customDuration(tester, '8');
    await tester.tap(find.text('Start break'));
    await tester.pumpAndSettle();
    expect(find.text('8:00'), findsOneWidget);
    expect(find.text('End break'), findsOneWidget);
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.text('End break'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to focus'));
    await tester.pumpAndSettle();
    expect(find.text('37:00'), findsOneWidget);
    expect(controller.preferredMinutes(SessionPhase.focus), 37);
    expect(controller.preferredMinutes(SessionPhase.rest), 8);
    expect(controller.session!.running(now), isFalse);
  });

  testWidgets(
    'Focus stays usable with a warning and doubled text on a short phone',
    (tester) async {
      final (controller, _) = await open();
      viewport(tester, const Size(320, 480));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        LockinApp(
          controller: controller,
          startupWarning: 'Cloud setup failed. Local mode remains available.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Cloud setup failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Lock in'));
      await tester.tap(find.text('Lock in'));
      await tester.pumpAndSettle();
      expect(controller.session!.focusing(controller.now), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duration can be changed on a phone with the keyboard open', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(320, 640));
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration · 25 min'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '45');
    await tester.ensureVisible(find.text('Set duration'));
    await tester.tap(find.text('Set duration'));
    await tester.pumpAndSettle();
    expect(find.text('45:00'), findsOneWidget);
    expect(controller.session, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'blocking and the single-app override remain reachable on Focus',
    (tester) async {
      final (controller, _) = await open();
      await controller.saveRule(
        ActivityRule(
          id: 'browser',
          name: 'Browser',
          sources: ['windows:chrome.exe'],
          dailyMinutes: 1,
        ),
      );
      controller.blockedSource = 'windows:chrome.exe';
      controller.blockMessage = 'Daily budget reached.';
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(LockinApp(controller: controller));
      expect(find.text('Daily budget reached.'), findsOneWidget);
      await tester.tap(find.text('Allow this app for 5 minutes'));
      await tester.pumpAndSettle();
      expect(controller.blockedSource, isNull);
      expect(controller.rules.single.dailyMinutes, 1);
      expect(find.text('Lock in'), findsOneWidget);
      expect(controller.session, isNull);
    },
  );

  testWidgets('all mobile pages fit at 320 pixels with enlarged text', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(320, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final index in [1, 2, 3, 4, 0]) {
      await navigate(tester, index);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Page $index must not overflow',
      );
    }
  });

  testWidgets(
    'a completed session waits for the next phase to be manually started',
    (tester) async {
      var now = DateTime.utc(2026, 11, 10, 10);
      final (controller, _) = await open(clock: () => now);
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('screen'),
          child: LockinApp(controller: controller),
        ),
      );
      await tester.tap(find.text('Lock in'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 26));
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Session complete'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('goldens/mobile-complete.png'),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch to break · 5 min'));
      await tester.pumpAndSettle();
      expect(find.text('5:00'), findsOneWidget);
      expect(controller.session!.running(now), isFalse);
      await tester.tap(find.text('Start break'));
      await tester.pumpAndSettle();
      expect(find.text('5:00'), findsOneWidget);
      expect(controller.session!.phase, SessionPhase.rest);
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('goldens/mobile-break.png'),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    },
  );

  testWidgets('a rule can be added on a phone while the keyboard is open', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 2);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'YouTube');
    // Typed websites and app IDs keep working, whatever the keyboard
    // capitalizes, and still count when Save is pressed without Add.
    await tester.ensureVisible(find.byKey(const ValueKey('add-website')));
    await tester.enterText(
      find.byKey(const ValueKey('add-website')),
      'Android:com.google.android.youtube,Web:YouTube.COM',
    );
    expect(tester.testTextInput.setClientArgs!['autocorrect'], isFalse);
    expect(tester.testTextInput.setClientArgs!['enableSuggestions'], isFalse);
    // Let the field finish scrolling its caret into view first.
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(controller.rules.single.name, 'YouTube');
    expect(
      controller.rules.single.sources,
      containsAll(['android:com.google.android.youtube', 'web:youtube.com']),
    );
    expect(find.text('YouTube'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starter rules are reviewed before saving and stay editable', (
    tester,
  ) async {
    final (controller, store) = await open();
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('starter-screen'),
        child: LockinApp(controller: controller),
      ),
    );
    await navigate(tester, 2);
    expect(find.text('Suggested apps'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('starter-screen')),
      matchesGoldenFile('goldens/mobile-rule-starters.png'),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(controller.rules, isEmpty);
    expect(controller.trackingEnabled, isFalse);

    await tester.ensureVisible(find.text('Instagram'));
    await tester.tap(find.text('Instagram'));
    await tester.pumpAndSettle();
    expect(find.text('Limit Instagram'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Instagram'), findsOneWidget);
    expect(controller.rules, isEmpty);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await store.rules(), isEmpty);

    await tester.ensureVisible(find.text('YouTube'));
    await tester.tap(find.text('YouTube'));
    await tester.pumpAndSettle();
    // The preset's app and websites show as one named row, no raw IDs.
    expect(find.text('Android app · youtube.com · youtu.be'), findsOneWidget);
    expect(find.textContaining('android:'), findsNothing);
    expect(
      find.text('YouTube is blocked while you focus and after 30 min a day.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Minutes a day'),
      '45',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('YouTube is blocked while you focus and after 45 min a day.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    final rule = controller.rules.single;
    expect(rule.name, 'YouTube');
    expect(rule.dailyMinutes, 45);
    expect(rule.focusBlock, isTrue);
    expect(rule.schedules, isEmpty);
    expect(
      rule.sources,
      containsAll([
        'web:youtube.com',
        'web:youtu.be',
        'android:com.google.android.youtube',
      ]),
    );
    expect((await store.rules()).single.encode(), rule.encode());
    expect(find.widgetWithText(ActionChip, 'YouTube'), findsNothing);
    expect(controller.trackingEnabled, isFalse);
    expect(controller.usage, isEmpty);

    await tester.tap(find.text('YouTube'));
    await tester.pumpAndSettle();
    expect(find.text('Edit rule'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '45'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.rules.single.encode(), rule.encode());
  });

  testWidgets('starter suggestions respect existing custom and alias rules', (
    tester,
  ) async {
    final (controller, store) = await open();
    final original = ActivityRule(
      id: 'my-news-rule',
      name: 'My news habit',
      sources: ['web:mobile.twitter.com'],
      focusBlock: false,
      dailyMinutes: 12,
    );
    await controller.saveRule(original);
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 2);
    // With rules saved, suggestions are folded until opened.
    expect(find.text('Instagram'), findsNothing);
    await tester.ensureVisible(find.text('Suggested apps'));
    await tester.tap(find.text('Suggested apps'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'X'), findsNothing);
    await tester.ensureVisible(find.text('Instagram'));
    await tester.tap(find.text('Instagram'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(controller.rules, hasLength(2));
    expect(
      (await store.rules()).singleWhere((r) => r.id == original.id).encode(),
      original.encode(),
    );
    expect(find.widgetWithText(ActionChip, 'Instagram'), findsNothing);
  });

  testWidgets('starter rules fit a short phone with enlarged text', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 2);
    await tester.ensureVisible(find.text('Discord'));
    await tester.tap(find.text('Discord'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(controller.rules.single.name, 'Discord');
    expect(controller.rules.single.dailyMinutes, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop workspace exposes navigation and Discord app coverage', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1120, 720));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('desktop-workspace'),
        child: LockinApp(controller: controller),
      ),
    );
    expect(find.byKey(const ValueKey('nav-2')), findsOneWidget);
    await navigate(tester, 2);
    expect(find.text('All social media'), findsOneWidget);
    await tester.ensureVisible(find.text('Discord'));
    await tester.tap(find.text('Discord'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(
      controller.rules.single.sources,
      containsAll([
        'windows:discord.exe',
        'windows:discordptb.exe',
        'windows:discordcanary.exe',
      ]),
    );
    await expectLater(
      find.byKey(const ValueKey('desktop-workspace')),
      matchesGoldenFile('goldens/desktop-rules.png'),
    );
    await navigate(tester, 4);
    expect(find.text('App updates'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('desktop-workspace')),
      matchesGoldenFile('goldens/desktop-settings.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keyboard navigation preserves the running timer', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1120, 720));
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    final sessionId = controller.session!.id;
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Your rules'), findsOneWidget);
    expect(controller.session!.id, sessionId);
    expect(controller.session!.running(controller.now), isTrue);
  });

  testWidgets('desktop navigation stays usable with doubled text', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1120, 600));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 2);
    await navigate(tester, 4);
    expect(find.text('App updates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing Discord rules can explicitly gain desktop coverage', (
    tester,
  ) async {
    final (controller, store) = await open();
    await controller.saveRule(
      ActivityRule(
        id: 'old-discord',
        name: 'Work chat',
        sources: ['web:discord.com', 'android:com.discord'],
        dailyMinutes: 45,
        focusBlock: false,
      ),
    );
    viewport(tester, const Size(1120, 720));
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 2);
    await tester.tap(
      find.byKey(const ValueKey('desktop-coverage-old-discord')),
    );
    await tester.pumpAndSettle();
    expect(
      (await store.rules()).single.sources,
      isNot(contains('windows:discord.exe')),
    );
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    final rule = controller.rules.single;
    expect(rule.id, 'old-discord');
    expect(rule.name, 'Work chat');
    expect(rule.dailyMinutes, 45);
    expect(rule.focusBlock, isFalse);
    expect(rule.sources, contains('windows:discord.exe'));
    expect(
      find.byKey(const ValueKey('desktop-coverage-old-discord')),
      findsNothing,
    );
  });

  testWidgets('all social media is one editable combined rule', (tester) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1120, 720));
    await tester.pumpWidget(LockinApp(controller: controller));
    await navigate(tester, 2);
    await tester.tap(find.text('All social media'));
    await tester.pumpAndSettle();
    expect(controller.rules, isEmpty);
    await tester.ensureVisible(find.text('Save rule'));
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(controller.rules.single.name, 'All social media');
    expect(controller.rules.single.dailyMinutes, 30);
    expect(
      controller.rules.single.sources,
      containsAll([
        'web:instagram.com',
        'web:youtube.com',
        'windows:discord.exe',
        'windows:telegram.exe',
        'windows:signal.exe',
        'android:com.whatsapp',
      ]),
    );
    expect(controller.trackingEnabled, isFalse);
  });

  testWidgets('rules show individual budgets using merged device usage', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 10, 10, 20);
    final (controller, store) = await open(clock: () => now);
    await controller.saveRule(
      ActivityRule(
        id: 'youtube',
        name: 'YouTube',
        dailyMinutes: 30,
        sources: ['web:youtube.com', 'android:youtube'],
      ),
    );
    await controller.saveRule(
      ActivityRule(
        id: 'social',
        name: 'Social',
        dailyMinutes: 10,
        sources: ['android:social'],
      ),
    );
    for (final interval in [
      UsageInterval(
        id: 'pc',
        deviceId: 'pc',
        source: 'web:youtube.com',
        start: DateTime.utc(2026, 11, 10, 10),
        end: DateTime.utc(2026, 11, 10, 10, 10),
      ),
      UsageInterval(
        id: 'phone',
        deviceId: 'phone',
        source: 'android:youtube',
        start: DateTime.utc(2026, 11, 10, 10, 5),
        end: DateTime.utc(2026, 11, 10, 10, 15),
      ),
      UsageInterval(
        id: 'social',
        deviceId: 'phone',
        source: 'android:social',
        start: DateTime.utc(2026, 11, 10, 9),
        end: DateTime.utc(2026, 11, 10, 9, 8),
      ),
    ]) {
      await store.putUsage(interval);
    }
    await controller.reloadUsage();
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Social'), findsNothing);
    await navigate(tester, 2);
    expect(find.textContaining('8 min of 10 min'), findsOneWidget);
    expect(find.text('Social'), findsOneWidget);
    await controller.deleteRule('social');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('15 min of 30 min'),
      findsOneWidget,
      reason: 'The overlapping YouTube minutes must count once',
    );
  });

  testWidgets('timer-only previews show no build label or setup prompt', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    expect(find.textContaining('Preview build'), findsNothing);
    expect(find.textContaining('Finish setup'), findsNothing);
  });

  testWidgets(
    'approved Focus layout stays minimal and dark in either system appearance',
    (tester) async {
      final (controller, _) = await open();
      for (final (name, size, mode) in [
        ('desktop', const Size(400, 560), ThemeMode.light),
        ('mobile', const Size(390, 844), ThemeMode.light),
        ('desktop-dark', const Size(400, 560), ThemeMode.dark),
        ('mobile-dark', const Size(390, 844), ThemeMode.dark),
        ('desktop-wide', const Size(1200, 900), ThemeMode.light),
      ]) {
        viewport(tester, size);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('screen'),
            child: LockinApp(controller: controller, themeMode: mode),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Grindset'), findsOneWidget);
        expect(find.text('Lock in'), findsOneWidget);
        expect(find.text('25:00'), findsOneWidget);
        expect(find.text('Focused'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(FocusScreen),
            matching: find.text('Activity'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('screen')),
          matchesGoldenFile('goldens/$name.png'),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        if (name == 'mobile') {
          await tester.tap(find.byTooltip('More options'));
          await tester.pumpAndSettle();
          await expectLater(
            find.byKey(const ValueKey('screen')),
            matchesGoldenFile('goldens/mobile-menu.png'),
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets('active focus previews show an unadorned countdown', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 10, 10);
    final (controller, _) = await open(clock: () => now);
    await controller.startSession(
      const Duration(minutes: 25),
      SessionPhase.focus,
    );
    now = now.add(const Duration(minutes: 7));
    for (final (name, size) in [
      ('desktop-focus', const Size(400, 560)),
      ('mobile-focus', const Size(390, 844)),
    ]) {
      viewport(tester, size);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('screen'),
          child: LockinApp(controller: controller, themeMode: ThemeMode.light),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('7 min'), findsNothing);
      expect(find.byTooltip('More options'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('goldens/$name.png'),
      );
    }
  });
}
