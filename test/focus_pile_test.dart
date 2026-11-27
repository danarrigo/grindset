import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/app_controller.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/ui/source_label.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('a session shows each blocked app or site once', () async {
    final store = LocalStore.memory();
    final c = AppController(
      store: store,
      tracker: NativeTracker(),
      clock: () => DateTime.utc(2026, 11, 10, 10),
    );
    addTearDown(() async {
      c.dispose();
      await store.close();
    });
    await c.initialize(poll: false);
    await c.saveRule(
      ActivityRule(
        id: 'social',
        name: 'Social',
        // X under both names, and an app this device hasn't got.
        sources: [
          'web:x.com',
          'web:twitter.com',
          'android:com.twitter.android',
        ],
      ),
    );
    await c.saveRule(
      ActivityRule(id: 'video', name: 'Video', sources: ['web:youtube.com']),
    );
    await c.saveRule(
      ActivityRule(
        id: 'later',
        name: 'Not during focus',
        sources: ['web:reddit.com'],
        focusBlock: false,
      ),
    );
    final shut = shutWhileFocusing(c);
    expect(shut.map((item) => item.name), unorderedEquals(['X', 'YouTube']));
    expect(
      shut.firstWhere((item) => item.name == 'X').sources,
      unorderedEquals(['web:x.com', 'web:twitter.com']),
    );
  });
}
