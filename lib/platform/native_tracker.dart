import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../core/activity.dart';

class ForegroundApp {
  const ForegroundApp(this.source, this.label);
  final String source;
  final String label;
}

/// Platform access is deliberately separate from timers and rule accounting.
class NativeTracker {
  static const channel = MethodChannel('app.lockin/usage');
  static final _closeDesktop = DynamicLibrary.open(
    'user32.dll',
  ).lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseDesktop');
  bool get isWindows => Platform.isWindows;
  bool get isAndroid => Platform.isAndroid;
  bool get supported => isWindows || isAndroid;

  Future<bool> hasAccess() async {
    if (isWindows) return true;
    if (isAndroid) {
      return await channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    }
    return false;
  }

  Future<void> requestAccess() async {
    if (isAndroid) await channel.invokeMethod<void>('requestUsageAccess');
  }

  ForegroundApp? foreground() {
    if (!isWindows) return null;
    // A secure/locked desktop isn't the user's interactive desktop.
    final desktop = OpenInputDesktop(0, 0, DESKTOP_READOBJECTS);
    if (desktop == 0) return null;
    _closeDesktop(desktop);
    final window = GetForegroundWindow();
    if (window == 0) return null;
    final pid = calloc<Uint32>();
    final size = calloc<Uint32>()..value = 32768;
    final buffer = wsalloc(32768);
    var process = 0;
    try {
      GetWindowThreadProcessId(window, pid);
      process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid.value);
      if (process == 0 ||
          QueryFullProcessImageName(process, 0, buffer, size) == 0) {
        return null;
      }
      final name = p.windows.basename(buffer.toDartString()).toLowerCase();
      if (['lockapp.exe', 'logonui.exe'].contains(name)) return null;
      // Never read or store window titles or executable paths.
      return ForegroundApp(
        'windows:$name',
        name.replaceFirst(RegExp(r'\.exe$'), ''),
      );
    } finally {
      if (process != 0) CloseHandle(process);
      calloc.free(pid);
      calloc.free(size);
      calloc.free(buffer);
    }
  }

  Future<List<UsageInterval>> androidHistory(
    String deviceId,
    DateTime from,
    DateTime until,
  ) async {
    if (!isAndroid) return [];
    final values =
        await channel.invokeListMethod<dynamic>('readUsage', {
          'from': from.millisecondsSinceEpoch,
          'until': until.millisecondsSinceEpoch,
        }) ??
        [];
    return values.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return UsageInterval(
        id: '$deviceId:${row['source']}:${row['start']}',
        deviceId: deviceId,
        source: row['source'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(
          row['start'] as int,
          isUtc: true,
        ),
        end: DateTime.fromMillisecondsSinceEpoch(
          row['end'] as int,
          isUtc: true,
        ),
      );
    }).toList();
  }
}
