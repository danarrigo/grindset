import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/app.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/focus_profiles_panel.dart';
import 'package:lockin/ui/tracking_health_panel.dart';
import 'package:lockin/ui/weekly_insights_panel.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _Windows extends NativeTracker {
  @override
  bool get isWindows => true;
  @override
  bool get isAndroid => false;
  @override
  Future<bool> setWindowsForegroundWatch(bool enabled) async => true;
  @override
  void bindWindowsForeground(void Function()? onChanged) {}
  @override
  ForegroundApp? foreground() => null;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  late LocalStore store;
  late AppController c;
  late DateTime now;
  setUp(() async {
    now = DateTime.utc(2026, 11, 16, 12);
    store = LocalStore.memory();
    c = AppController(store: store, tracker: _Windows(), clock: () => now);
    await c.initialize(poll: false);
  });
  tearDown(() async {
    c.dispose();
    await store.close();
  });
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Focus shows a near limit whether or not budget notifications are on',
    (tester) async {
      await c.saveRule(
        ActivityRule(
          id: 'budget',
          name: 'Social',
          sources: ['windows:discord.exe'],
          dailyMinutes: 50,
        ),
      );
      await store.putUsage(
        UsageInterval(
          id: 'near-budget',
          deviceId: c.deviceId,
          source: 'windows:discord.exe',
          start: now.subtract(const Duration(minutes: 40)),
          end: now,
        ),
      );
      await c.reloadUsage();
      c.trackingEnabled = true;
      await tester.pumpWidget(LockinApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Social: 10 min left today'), findsOneWidget);
      expect(c.budgetWarnings, isEmpty);
      await c.setBudgetWarningsEnabled(true);
      await tester.pumpAndSettle();
      expect(find.text('Social: 10 min left today'), findsOneWidget);
      expect(c.budgetWarnings.single.name, 'Social');
      expect(c.rules.single.dailyMinutes, 50);
      expect(c.completionAlertsEnabled, isFalse);
    },
  );

  testWidgets(
    'setup checklist shows off, ready and broken steps in plain words',
    (tester) async {
      await show(
        tester,
        TrackingHealthPanel(controller: c, onTracking: () {}, onRules: () {}),
      );
      expect(
        find.text('Off. Rules only work while this is on.'),
        findsOneWidget,
      );
      expect(find.text('Turn on'), findsOneWidget);
      expect(find.text('Unavailable. Restart Grindset.'), findsOneWidget);
      expect(find.text('Starts when tracking is on.'), findsOneWidget);
      expect(find.text('Setup · 0 of 4 done'), findsOneWidget);
      c.trackingEnabled = true;
      c.accessGranted = true;
      c.windowsForegroundEventsActive = true;
      await show(
        tester,
        TrackingHealthPanel(controller: c, onTracking: () {}, onRules: () {}),
      );
      expect(find.text('Turn on'), findsNothing);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Setup · 2 of 4 done'), findsOneWidget);
      c.windowsForegroundEventsActive = false;
      await show(
        tester,
        TrackingHealthPanel(controller: c, onTracking: () {}, onRules: () {}),
      );
      expect(find.text('Not working. Restart Grindset.'), findsOneWidget);
    },
  );
  testWidgets(
    'Work creation is inert until the user explicitly confirms Use profile',
    (tester) async {
      await c.saveRule(
        ActivityRule(
          id: 'social',
          name: 'Social',
          sources: ['windows:discord.exe'],
          focusBlock: false,
          dailyMinutes: 47,
        ),
      );
      await show(tester, FocusProfilesPanel(controller: c));
      await tester.tap(find.text('Create Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Social'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(c.focusProfiles.single.name, 'Work');
      expect(c.rules.single.focusBlock, isFalse);
      await tester.tap(find.text('Use Work'));
      await tester.pumpAndSettle();
      expect(c.rules.single.focusBlock, isFalse);
      await tester.tap(find.text('Use profile'));
      await tester.pumpAndSettle();
      expect(c.rules.single.focusBlock, isTrue);
      expect(c.rules.single.dailyMinutes, 47);
      expect(c.session, isNull);
    },
  );
  testWidgets(
    'new panels remain usable on a narrow screen with enlarged text',
    (tester) async {
      await store.putUsage(
        UsageInterval(
          id: 'narrow',
          deviceId: c.deviceId,
          source: 'windows:long-application-name.exe',
          start: now.subtract(const Duration(minutes: 119)),
          end: now,
        ),
      );
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final panel in <Widget>[
        TrackingHealthPanel(controller: c),
        FocusProfilesPanel(controller: c),
        WeeklyInsightsPanel(controller: c),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(16), child: panel),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'weekly no-data view marks days unknown instead of claiming zero distraction',
    (tester) async {
      await show(tester, WeeklyInsightsPanel(controller: c));
      expect(
        find.textContaining('No recorded usage in this period'),
        findsOneWidget,
      );
      expect(find.text('Not recorded'), findsWidgets);
      expect(find.text('0 of 7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'weekly view uses confirmed records and labels current-budget projection',
    (tester) async {
      await c.saveRule(
        ActivityRule(
          id: 'social',
          name: 'Social',
          sources: ['windows:discord.exe'],
          dailyMinutes: 20,
        ),
      );
      await store.putUsage(
        UsageInterval(
          id: 'record',
          deviceId: c.deviceId,
          source: 'windows:discord.exe',
          start: now.subtract(const Duration(minutes: 30)),
          end: now,
        ),
      );
      await show(tester, WeeklyInsightsPanel(controller: c));
      expect(find.text('30 min'), findsWidgets);
      expect(
        find.textContaining(
          '1 of 1 recorded days reached a current daily budget',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('not a history of past rule settings'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
