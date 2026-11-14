import 'package:file_selector/file_selector.dart';

import 'native_tracker.dart';

class WindowsApp {
  const WindowsApp({
    required this.source,
    required this.name,
    this.running = false,
  });
  final String source;
  final String name;
  final bool running;

  factory WindowsApp.fromMap(Map<String, dynamic> value) {
    final source = value['source'];
    final name = value['name'];
    if (source is! String ||
        !RegExp(r'^windows:[^/\\:\x00-\x1f]+\.exe$').hasMatch(source) ||
        name is! String ||
        name.trim().isEmpty) {
      throw const FormatException('Invalid Windows application.');
    }
    return WindowsApp(
      source: source,
      name: name,
      running: value['running'] == true,
    );
  }
}

class WindowsApps {
  static Future<List<WindowsApp>> list() async {
    final rows = await NativeTracker.windowsChannel
        .invokeListMethod<dynamic>('listWindowsApps')
        .timeout(const Duration(seconds: 15));
    return [
      for (final row in rows ?? [])
        WindowsApp.fromMap(Map<String, dynamic>.from(row as Map)),
    ];
  }

  static Future<WindowsApp?> browse() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Windows application', extensions: ['exe']),
      ],
    );
    if (file == null) return null;
    final row = await NativeTracker.windowsChannel
        .invokeMapMethod<String, dynamic>('describeWindowsApp', {
          'path': file.path,
        })
        .timeout(const Duration(seconds: 15));
    if (row == null) {
      throw const FormatException(
        'Choose a local application executable, not a Windows recovery app or shared system host.',
      );
    }
    return WindowsApp.fromMap(row);
  }
}
