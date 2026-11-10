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
}
