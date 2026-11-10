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
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

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

  Future<void> customDuration(WidgetTester tester, String minutes) async {
    await tester.tap(find.byKey(const ValueKey('duration-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom duration...'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), minutes);
    await tester.tap(find.text('Set duration'));
    await tester.pumpAndSettle();
  }

  testWidgets('Lock in starts immediately without a setup form', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1200, 900));
    await tester.pumpWidget(LockinApp(controller: controller));
    expect(find.widgetWithText(FilledButton, 'Lock in'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('25:00'),
      findsNothing,
      reason: 'The idle screen is action-first, not a giant stopwatch',
    );
    expect(find.text('Focused today'), findsOneWidget);
    expect(find.text('Daily limits'), findsOneWidget);
    await tester.tap(find.text('Lock in'));
    await tester.pumpAndSettle();
    expect(controller.session?.focusing(controller.now), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('End session'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
  });

  testWidgets('a restored session keeps its deadline after the UI closes', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 10, 10);
    final (controller, store) = await open(clock: () => now);
    viewport(tester, const Size(1200, 900));
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.tap(find.text('Lock in'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    now = now.add(const Duration(minutes: 20));
    final restored = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => now,
    );
    addTearDown(restored.dispose);
    await restored.initialize(poll: false);
    await tester.pumpWidget(LockinApp(controller: restored));
    await tester.pumpAndSettle();
    expect(find.text('5:00'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
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
      expect(find.text('37 min'), findsOneWidget);
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
      expect(find.text('37 min'), findsOneWidget);
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
      await tester.tap(find.byKey(ValueKey('nav-$index')));
      await tester.pumpAndSettle();
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
      viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.tap(find.text('Lock in'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 26));
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('Session complete'), findsOneWidget);
      await tester.tap(find.text('Break'));
      await tester.pumpAndSettle();
      expect(find.text('5 min'), findsOneWidget);
      expect(controller.session!.running(now), isFalse);
      await tester.tap(find.text('Start break'));
      await tester.pumpAndSettle();
      expect(find.text('5:00'), findsOneWidget);
      expect(controller.session!.phase, SessionPhase.rest);
    },
  );

  testWidgets(
    'an activity can be added on a phone while the keyboard is open',
    (tester) async {
      final (controller, _) = await open();
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.tap(find.byKey(const ValueKey('nav-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add activity'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'YouTube');
      await tester.ensureVisible(find.text('Enter a source identifier'));
      await tester.tap(find.text('Enter a source identifier'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'android:com.google.android.youtube',
      );
      await tester.ensureVisible(find.text('Save activity'));
      await tester.tap(find.text('Save activity'));
      await tester.pumpAndSettle();
      expect(controller.rules.single.name, 'YouTube');
      expect(
        controller.rules.single.sources,
        contains('android:com.google.android.youtube'),
      );
      expect(find.text('YouTube'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home shows the nearest real daily limit using merged device usage',
    (tester) async {
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
      expect(find.text('Closest limit'), findsOneWidget);
      expect(find.text('2 min left'), findsOneWidget);
      expect(find.text('Social'), findsOneWidget);
      await controller.deleteRule('social');
      await tester.pumpAndSettle();
      expect(
        find.text('15 min left'),
        findsOneWidget,
        reason: 'The overlapping YouTube minutes must count once',
      );
    },
  );

  testWidgets('preview status keeps unfinished blocking and sync explicit', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(LockinApp(controller: controller));
    expect(
      find.text('Timer only. App blocking is not connected yet.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Preview build'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('persistent background journal'),
      findsOneWidget,
    );
  });

  testWidgets(
    'light and dark previews share the same desktop and mobile structure',
    (tester) async {
      final (controller, _) = await open();
      for (final (name, size, mode) in [
        ('desktop', const Size(1200, 900), ThemeMode.light),
        ('mobile', const Size(390, 844), ThemeMode.light),
        ('desktop-dark', const Size(1200, 900), ThemeMode.dark),
        ('mobile-dark', const Size(390, 844), ThemeMode.dark),
      ]) {
        viewport(tester, size);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('screen'),
            child: LockinApp(controller: controller, themeMode: mode),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lock in'), findsOneWidget);
        expect(find.text('0 min'), findsOneWidget);
        expect(find.text('None set'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (name.startsWith('mobile')) {
          expect(
            tester
                .getBottomRight(find.widgetWithText(FilledButton, 'Lock in'))
                .dy,
            lessThan(tester.getTopLeft(find.byType(CupertinoTabBar)).dy),
          );
        }
        await expectLater(
          find.byKey(const ValueKey('screen')),
          matchesGoldenFile('goldens/$name.png'),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        if (name.startsWith('mobile')) {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
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
      ('desktop-focus', const Size(1200, 900)),
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
      expect(find.text('7 min'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('goldens/$name.png'),
      );
    }
  });
}
