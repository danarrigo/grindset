import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
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

  testWidgets(
    'a user starts focus, closes the UI, and restores the same deadline',
    (tester) async {
      var now = DateTime.utc(2026, 11, 10, 10);
      final (controller, store) = await open(clock: () => now);
      viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      expect(find.text('End session'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      now = now.add(const Duration(minutes: 20));
      final restored = AppController(
        store: store,
        tracker: NativeTracker(),
        clock: () => now,
      );
      await restored.initialize(poll: false);
      addTearDown(restored.dispose);
      await tester.pumpWidget(LockinApp(controller: restored));
      await tester.pumpAndSettle();
      expect(find.text('5:00'), findsOneWidget);
      expect(find.text('End session'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom timer validates input and starts the requested duration',
    (tester) async {
      final (controller, _) = await open();
      viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Set duration'));
      await tester.pumpAndSettle();
      expect(find.text('Choose 1 to 1440 minutes'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '37');
      await tester.tap(find.text('Set duration'));
      await tester.pumpAndSettle();
      expect(find.text('37:00'), findsOneWidget);
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      expect(
        controller.session!.end.difference(controller.session!.start),
        const Duration(minutes: 37),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all mobile pages remain usable at 320 pixels with enlarged text',
    (tester) async {
      final (controller, _) = await open();
      viewport(tester, const Size(320, 740));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final title in [
        'Activity',
        'Rules',
        'Devices',
        'Settings',
        'Focus',
      ]) {
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'The $title page must not overflow',
        );
      }
    },
  );

  testWidgets(
    'a completed timer shows zero until the next phase is manually chosen',
    (tester) async {
      var now = DateTime.utc(2026, 11, 10, 10);
      final (controller, _) = await open(clock: () => now);
      viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(LockinApp(controller: controller));
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 26));
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('SESSION COMPLETE'), findsOneWidget);
      await tester.tap(find.text('Break'));
      await tester.pumpAndSettle();
      expect(find.text('5:00'), findsOneWidget);
      expect(find.text('Start break'), findsOneWidget);
      expect(controller.session!.running(now), isFalse);
    },
  );

  testWidgets('a user creates an activity rule through the editor', (
    tester,
  ) async {
    final (controller, _) = await open();
    viewport(tester, const Size(1200, 900));
    await tester.pumpWidget(LockinApp(controller: controller));
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add activity'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'YouTube');
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
  });

  testWidgets('desktop and mobile have honest empty states', (tester) async {
    final (controller, _) = await open();
    for (final (name, size) in [
      ('desktop', const Size(1200, 900)),
      ('mobile', const Size(390, 844)),
    ]) {
      viewport(tester, size);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('screen'),
          child: LockinApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tracking setup required'), findsOneWidget);
      expect(find.text('0m'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (name == 'desktop') {
        expect(find.byType(NavigationBar), findsNothing);
      } else {
        expect(
          tester
              .getBottomRight(find.widgetWithText(FilledButton, 'Start focus'))
              .dy,
          lessThan(size.height - 80),
          reason: 'The main action should fit above navigation',
        );
      }
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('goldens/$name.png'),
      );
    }
  });
}
