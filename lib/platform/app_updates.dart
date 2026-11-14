import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_links.dart';

List<int> _version(String value) {
  final match = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+\d+)?$')
      .firstMatch(value);
  if (match == null || value.length > 40) {
    throw const FormatException('Unsupported app version.');
  }
  return [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
}

class AppRelease {
  AppRelease({required this.version, required this.notes}) {
    _version(version);
    if (version.contains('+')) {
      throw const FormatException(
        'Release versions must not contain build metadata.',
      );
    }
  }

  final String version;
  final String notes;

  bool isNewerThan(String installed) {
    final latest = _version(version);
    final current = _version(installed);
    for (var i = 0; i < latest.length; i++) {
      if (latest[i] != current[i]) return latest[i] > current[i];
    }
    return false;
  }

  // Derive URLs rather than accepting arbitrary launch targets from a feed.
  Uri downloadUrl({required bool android}) => Uri.parse(
    '${AppLinks.releases}/download/v$version/grindset-$version-'
    '${android ? 'android-arm64.apk' : 'windows-x64-setup.exe'}',
  );
}

class AppUpdates {
  const AppUpdates();

  Future<AppRelease> latest({http.Client? client}) async {
    final connection = client ?? http.Client();
    try {
      final response = await connection
          .get(
            AppLinks.updateFeed,
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'The update feed is unavailable. Try again later.',
          AppLinks.updateFeed,
        );
      }
      if (response.bodyBytes.length > 65536) {
        throw const FormatException('The update feed is too large.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> ||
          data['schema'] != 1 ||
          data['version'] is! String ||
          data['notes'] is! String) {
        throw const FormatException('The update feed is not supported.');
      }
      return AppRelease(
        version: data['version'] as String,
        notes: data['notes'] as String,
      );
    } finally {
      if (client == null) connection.close();
    }
  }
}
