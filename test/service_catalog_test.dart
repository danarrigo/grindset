import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/activity.dart';
import 'package:lockin/core/rule_presets.dart';
import 'package:lockin/core/service_catalog.dart';

void main() {
  test('every service has a unique name and valid identifiers', () {
    final names = <String>{};
    final owners = <String, String>{};
    for (final service in catalogServices) {
      expect(names.add(service.name), isTrue, reason: service.name);
      expect(service.sources, isNotEmpty, reason: service.name);
      for (final source in service.sources) {
        if (source.startsWith('web:')) {
          expect(websiteHost(source.substring(4)), source.substring(4));
        } else if (source.startsWith('windows:')) {
          expect(
            source,
            matches(RegExp(r'^windows:[a-z0-9 ._!+-]+\.exe$')),
            reason: 'lowercase executable',
          );
        } else {
          expect(source, matches(RegExp(r'^android:[A-Za-z0-9_.]+$')));
        }
        // One identifier belongs to one service, so names never flicker.
        expect(
          owners.putIfAbsent(source, () => service.name),
          service.name,
          reason: source,
        );
      }
    }
    expect(catalogServices.length, greaterThanOrEqualTo(140));
  });

  test('starter presets keep their exact identifiers', () {
    for (final preset in individualRulePresets) {
      expect(serviceNamed(preset.name)!.sources, preset.sources);
    }
  });

  test('families only name catalog services and never whole browsers', () {
    for (final family in catalogFamilies) {
      for (final service in family.services) {
        expect(service.category, isNot('Whole browser'), reason: service.name);
      }
    }
  });

  test('search finds services by name, nickname and website', () {
    expect(searchCatalog('google').first, isA<CatalogFamily>());
    expect((searchCatalog('google').first as CatalogFamily).name, 'Google');
    expect((searchCatalog('ig').first as CatalogService).name, 'Instagram');
    expect((searchCatalog('twitter').first as CatalogService).name, 'X');
    expect((searchCatalog('gmail').first as CatalogService).name, 'Gmail');
    expect((searchCatalog('YouTube').first as CatalogService).name, 'YouTube');
    expect(
      searchCatalog('netfl').whereType<CatalogService>().map((s) => s.name),
      contains('Netflix'),
    );
    expect(searchCatalog(''), isEmpty);
    expect(searchCatalog('zzzz-nothing'), isEmpty);
  });

  test('sources are named after their service', () {
    expect(sourceName('web:m.youtube.com'), 'YouTube');
    expect(sourceName('web:music.youtube.com'), 'YouTube Music');
    expect(sourceName('windows:Spotify.EXE'), 'Spotify');
    expect(sourceName('android:com.netflix.mediaclient'), 'Netflix');
    expect(sourceName('web:example.com'), 'example.com');
  });
}
