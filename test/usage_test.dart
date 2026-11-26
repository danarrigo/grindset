import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';

void main() {
  test('overlapping YouTube use consumes 15 minutes, not 20', () {
    final day = DateTime.utc(2026, 11, 10, 10);
    final usage = [
      UsageInterval(
        id: 'pc',
        deviceId: 'windows',
        source: 'web:youtube.com',
        start: day,
        end: day.add(const Duration(minutes: 10)),
      ),
      UsageInterval(
        id: 'phone',
        deviceId: 'android',
        source: 'android:youtube',
        start: day.add(const Duration(minutes: 5)),
        end: day.add(const Duration(minutes: 15)),
      ),
    ];
    expect(combinedUsage(usage), const Duration(minutes: 15));
  });

  test('only sources the server accepts are synced', () {
    // Checked against the server's valid_source function.
    for (final source in [
      'windows:zen.exe',
      'windows:cloudflare warp.exe',
      'web:informatika.stei.itb.ac.id',
      'web:127.0.0.1',
      'web:localhost',
      'web:Example.COM.',
      'android:com.EmasDigi',
      'android:com.x',
    ]) {
      expect(syncableSource(source), isTrue, reason: source);
    }
    for (final source in [
      'windows:grindset-1.6.15-windows-x64-setup.tmp',
      'windows:x.EXE',
      'windows:a/b.exe',
      'web:a..b',
      'web:-bad.com',
      'web:${'a' * 254}',
      'android:com',
      'file:notes.txt',
    ]) {
      expect(syncableSource(source), isFalse, reason: source);
    }
  });
}
