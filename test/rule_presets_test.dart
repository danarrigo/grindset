import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/rule_presets.dart';
import 'package:lockin/ui/rule_editor.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'individual starters have distinct valid identifiers and readable names',
    () {
      expect(individualRulePresets, hasLength(17));
      expect(rulePresets, hasLength(18));
      final allSources = <String>{};
      for (final preset in individualRulePresets) {
        expect(preset.dailyMinutes, 30);
        expect(preset.sources.any((s) => s.startsWith('android:')), isTrue);
        for (final source in preset.sources) {
          expect(allSources.add(source), isTrue);
          if (source.startsWith('web:')) {
            expect(websiteHost(source.substring(4)), source.substring(4));
          } else if (source.startsWith('windows:')) {
            expect(source, matches(r'^windows:[a-z0-9.]+\.exe$'));
          } else {
            expect(
              source,
              matches(r'^android:[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
            );
          }
          expect(sourceName(source), preset.name);
        }
      }
      expect(socialMediaPreset.sources, allSources);
      expect(allSources, isNot(contains('windows:chrome.exe')));
      expect(allSources, isNot(contains('windows:msedge.exe')));
      expect(allSources, isNot(contains('windows:msedgewebview2.exe')));
    },
  );

  test('old Discord rules can gain only their missing native sources', () {
    final missing = missingDesktopSources([
      'web:discord.com',
      'android:com.discord',
    ]);
    expect(missing, {
      'windows:discord.exe',
      'windows:discordptb.exe',
      'windows:discordcanary.exe',
    });
    expect(missingDesktopSources(socialMediaPreset.sources), isEmpty);
    expect(missingDesktopSources(['web:custom.example']), isEmpty);
  });

  test('combined social budget unions overlapping apps instead of summing', () {
    tzdata.initializeTimeZones();
    final now = DateTime.utc(2026, 11, 14, 10, 40);
    final intervals = [
      UsageInterval(
        id: 'discord',
        deviceId: 'pc',
        source: 'windows:discord.exe',
        start: DateTime.utc(2026, 11, 14, 10),
        end: DateTime.utc(2026, 11, 14, 10, 20),
      ),
      UsageInterval(
        id: 'instagram',
        deviceId: 'phone',
        source: 'android:com.instagram.android',
        start: DateTime.utc(2026, 11, 14, 10, 10),
        end: DateTime.utc(2026, 11, 14, 10, 30),
      ),
    ];
    final rule = ActivityRule(
      id: 'social',
      name: socialMediaPreset.name,
      sources: socialMediaPreset.sources,
      dailyMinutes: 30,
    );
    expect(combinedUsage(intervals), const Duration(minutes: 30));
    expect(
      blockingReason(
        rule: rule,
        now: now,
        location: tz.UTC,
        intervals: intervals,
      ),
      'Daily budget reached',
    );
  });

  test('website subdomains match but unrelated hosts and apps do not', () {
    for (final source in socialMediaPreset.sources.where(
      (s) => s.startsWith('web:'),
    )) {
      final host = source.substring(4);
      expect(matchesSource(source, 'web:m.$host'), isTrue);
      expect(matchesSource(source, 'web:$host.evil.example'), isFalse);
    }
    expect(matchesSource('windows:Discord.EXE', 'windows:discord.exe'), isTrue);
    expect(
      matchesSource('android:com.Example.App', 'android:com.example.app'),
      isFalse,
    );
    expect(sourceName('windows:Discord.EXE'), 'Discord');
    expect(sourceName('windows:my-editor.exe'), 'my-editor');
    expect(sourceName('android:com.example.custom'), 'custom');
  });
}
