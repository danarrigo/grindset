import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lockin/platform/app_links.dart';
import 'package:lockin/platform/app_updates.dart';

void main() {
  test('versions compare numerically and never offer a downgrade', () {
    final release = AppRelease(version: '1.10.0', notes: 'Changes');
    expect(release.isNewerThan('1.9.9'), isTrue);
    expect(release.isNewerThan('1.10.0+35'), isFalse);
    expect(release.isNewerThan('2.0.0'), isFalse);
    expect(
      () => AppRelease(version: '1.2.0-beta', notes: ''),
      throwsFormatException,
    );
    expect(
      () => AppRelease(version: '../attacker', notes: ''),
      throwsFormatException,
    );
    expect(
      () => AppRelease(version: '01.2.0', notes: ''),
      throwsFormatException,
    );
  });

  test(
    'feed uses anonymous public HTTPS and derives trusted platform downloads',
    () async {
      final client = MockClient((request) async {
        expect(request.url, AppLinks.updateFeed);
        expect(request.method, 'GET');
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        return http.Response(
          jsonEncode({
            'schema': 1,
            'version': '1.2.0',
            'notes': 'In-app checks and confirmation page.',
            'download_url': 'https://attacker.example/not-an-update.exe',
          }),
          200,
        );
      });
      addTearDown(client.close);
      final release = await const AppUpdates().latest(client: client);
      expect(release.isNewerThan('1.1.0'), isTrue);
      expect(
        release.downloadUrl(android: false).toString(),
        'https://github.com/danarrigo/grindset-releases/releases/download/v1.2.0/grindset-1.2.0-windows-x64-setup.exe',
      );
      expect(
        release.downloadUrl(android: true).toString(),
        'https://github.com/danarrigo/grindset-releases/releases/download/v1.2.0/grindset-1.2.0-android-arm64.apk',
      );
    },
  );

  test(
    'unavailable or malformed feeds are errors, not up-to-date results',
    () async {
      for (final response in [
        http.Response('Unavailable', 503),
        http.Response('<html>Not JSON</html>', 200),
        http.Response('{"schema":2,"version":"1.2.0","notes":""}', 200),
        http.Response('{"schema":1,"version":"1.2.0"}', 200),
        http.Response('{"schema":1,"version":"1.2.0/evil","notes":""}', 200),
        http.Response('x' * 65537, 200),
      ]) {
        final client = MockClient((_) async => response);
        addTearDown(client.close);
        await expectLater(
          const AppUpdates().latest(client: client),
          throwsA(isA<Exception>()),
        );
      }
    },
  );
}
