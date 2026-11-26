import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/while_visible.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('changes wait while hidden, then arrive once', () {
    final source = ChangeNotifier();
    final visible = ValueNotifier(true);
    final gated = WhileVisible(source, visible);
    var heard = 0;
    gated.addListener(() => heard++);

    source.notifyListeners();
    expect(heard, 1);
    visible.value = false;
    source
      ..notifyListeners()
      ..notifyListeners();
    expect(heard, 1);
    visible.value = true;
    expect(heard, 2);
    // Shown again with nothing missed: no extra rebuild.
    visible.value = false;
    visible.value = true;
    expect(heard, 2);
    gated.dispose();
  });

  testWidgets('a hidden window does not rebuild, and catches up when shown', (
    tester,
  ) async {
    final store = LocalStore.memory();
    final controller = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => DateTime.utc(2026, 11, 10, 10),
    );
    await controller.initialize(poll: false);
    controller.onboarded = true;
    final visible = ValueNotifier(true);
    final changes = WhileVisible(controller, visible);
    addTearDown(() async {
      changes.dispose();
      controller.dispose();
      await store.close();
    });
    await tester.pumpWidget(
      LockinApp(controller: controller, changes: changes),
    );
    await tester.pumpAndSettle();

    visible.value = false;
    await controller.saveRule(
      ActivityRule(id: 'g', name: 'Games', sources: ['web:game.test']),
    );
    // Nothing is rebuilt, so no frame is even asked for.
    expect(tester.binding.hasScheduledFrame, isFalse);

    visible.value = true;
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsWidgets);
  });
}
