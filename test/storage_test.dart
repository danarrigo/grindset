import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/data/local_store.dart';

void main() {
  test(
    'confirmed history survives closing and reopening the database file',
    () async {
      final directory = await Directory.systemTemp.createTemp('lockin-test-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/lockin.sqlite');
      final first = LocalStore.file(file);
      try {
        await first.saveSetting('timezone', 'America/New_York');
        await first.putUsage(
          UsageInterval(
            id: 'saved',
            deviceId: 'phone',
            source: 'android:youtube',
            start: DateTime.utc(2026, 11, 10, 10),
            end: DateTime.utc(2026, 11, 10, 10, 10),
          ),
        );
      } finally {
        await first.close();
      }
      final restored = LocalStore.file(file);
      addTearDown(restored.close);
      expect(await restored.setting('timezone'), 'America/New_York');
      expect(
        combinedUsage(await restored.usage()),
        const Duration(minutes: 10),
      );
    },
  );

  test(
    'reimporting unchanged Android history does not queue it for upload again',
    () async {
      final store = LocalStore.memory();
      addTearDown(store.close);
      final interval = UsageInterval(
        id: 'unchanged',
        deviceId: 'phone',
        source: 'android:youtube',
        start: DateTime.utc(2026, 11, 10, 10),
        end: DateTime.utc(2026, 11, 10, 10, 10),
      );
      await store.putUsage(interval);
      await store.markUploaded(interval);
      await store.putUsage(interval);
      expect(await store.usage(pendingOnly: true), isEmpty);
    },
  );

  test(
    'a successful upload cannot mark a newer local observation as synced',
    () async {
      final store = LocalStore.memory();
      addTearDown(store.close);
      final start = DateTime.utc(2026, 11, 10);
      UsageInterval observation(int minutes) => UsageInterval(
        id: 'stable-id',
        deviceId: 'pc',
        source: 'windows:code.exe',
        start: start,
        end: start.add(Duration(minutes: minutes)),
      );
      await store.putUsage(observation(1));
      await store.putUsage(observation(2));
      await store.markUploaded(observation(1));
      expect(
        (await store.usage(pendingOnly: true)).single.end,
        start.add(const Duration(minutes: 2)),
      );
      await store.markUploaded(observation(2));
      expect(await store.usage(pendingOnly: true), isEmpty);
      // An older download cannot shorten confirmed history.
      await store.putUsage(observation(1), pending: false);
      expect(combinedUsage(await store.usage()), const Duration(minutes: 2));
    },
  );
  test(
    'activity configuration round-trips without needing a cloud account',
    () async {
      final store = LocalStore.memory();
      addTearDown(store.close);
      await store.saveRules([
        ActivityRule(
          id: 'yt',
          name: 'YouTube',
          sources: ['web:youtube.com', 'android:com.google.android.youtube'],
          dailyMinutes: 30,
        ),
      ]);
      final restored = (await store.rules()).single;
      expect(restored.dailyMinutes, 30);
      expect(
        restored.sources,
        containsAll(['web:youtube.com', 'android:com.google.android.youtube']),
      );
    },
  );
}
