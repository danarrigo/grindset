import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local_store.dart';

class ExportFiles {
  static const channel = MethodChannel('app.lockin/usage');

  static Future<bool> save(
    LocalStore store, {
    required DateTime exportedAt,
  }) async {
    final cache = await getTemporaryDirectory();
    final directory = await cache.createTemp('grindset-export-');
    try {
      final name =
          'grindset-export-${exportedAt.toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.json';
      final archive = File(p.join(directory.path, name));
      await store.exportTo(archive, exportedAt: exportedAt);
      if (Platform.isAndroid) {
        return await channel.invokeMethod<bool>('saveExport', {
              'path': archive.path,
              'name': name,
            }) ??
            false;
      }
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON archive', extensions: ['json']),
        ],
      );
      if (location == null) return false;
      if (p.extension(location.path).toLowerCase() != '.json') {
        throw ArgumentError('Save the archive with a .json extension.');
      }
      await archive.copy(location.path);
      return true;
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
