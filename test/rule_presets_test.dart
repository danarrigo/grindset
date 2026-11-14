import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/rule_presets.dart';
import 'package:lockin/ui/rule_editor.dart';

void main() {
  test(
    'starter catalog has distinct names and valid cross-platform identifiers',
    () {
      expect(rulePresets, hasLength(9));
      expect(rulePresets.map((preset) => preset.name).toSet(), hasLength(9));
      final allSources = <String>{};
      for (final preset in rulePresets) {
        expect(preset.dailyMinutes, 30);
        expect(preset.sources.any((s) => s.startsWith('web:')), isTrue);
        expect(preset.sources.any((s) => s.startsWith('android:')), isTrue);
        for (final source in preset.sources) {
          expect(allSources.add(source), isTrue);
          if (source.startsWith('web:')) {
            final host = source.substring(4);
            expect(websiteHost(host), host);
            expect(host, contains('.'));
          } else {
            expect(
              source,
              matches(r'^android:[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
            );
          }
          expect(sourceName(source), preset.name);
        }
      }
    },
  );

  test(
    'starter websites include mobile subdomains but not lookalike hosts',
    () {
      for (final source in rulePresets.expand((p) => p.sources)) {
        if (!source.startsWith('web:')) continue;
        final host = source.substring(4);
        expect(matchesSource(source, 'web:m.$host'), isTrue);
        expect(matchesSource(source, 'web:$host.evil.example'), isFalse);
      }
      expect(sourceName('windows:my-editor.exe'), 'my-editor');
      expect(sourceName('android:com.example.custom'), 'custom');
    },
  );
}
