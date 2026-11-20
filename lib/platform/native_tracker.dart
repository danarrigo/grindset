import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../core/activity.dart';

class AndroidTrackingStatus {
  const AndroidTrackingStatus({
    required this.enabled,
    required this.running,
    required this.blockingEnabled,
    this.instantAvailable = false,
    this.instantEnabled = false,
    this.error,
  });
  factory AndroidTrackingStatus.fromMap(Map<String, dynamic> value) =>
      AndroidTrackingStatus(
        enabled: value['enabled'] == true,
        running: value['running'] == true,
        blockingEnabled: value['blockingEnabled'] == true,
        instantAvailable: value['instantAvailable'] == true,
        instantEnabled: value['instantEnabled'] == true,
        error: value['error'] as String?,
      );
  final bool enabled;
  final bool running;
  final bool blockingEnabled;

  /// The Google Play edition can cover blocked apps the moment they open.
  final bool instantAvailable;
  final bool instantEnabled;
  final String? error;
}

class WindowsActivityStatus {
  const WindowsActivityStatus({
    required this.current,
    required this.idle,
    required this.idleKnown,
    required this.mediaAvailable,
    required this.mediaPlaying,
  });
  factory WindowsActivityStatus.fromMap(Map<String, dynamic> value) =>
      WindowsActivityStatus(
        current: value['current'] == true,
        idle: Duration(milliseconds: value['idleMs'] as int? ?? 0),
        idleKnown: value['idleKnown'] == true,
        mediaAvailable: value['mediaAvailable'] == true,
        mediaPlaying: value['mediaPlaying'] == true,
      );
  final bool current;
  final Duration idle;
  final bool idleKnown;
  final bool mediaAvailable;
  final bool mediaPlaying;
}

class ForegroundApp {
  const ForegroundApp(this.source, this.label, {this.processId = 0});
  final String source;
  final String label;
  final int processId;
}

/// Platform access is deliberately separate from timers and rule accounting.
class NativeTracker {
  static const channel = MethodChannel('app.lockin/usage');
  static const windowsChannel = MethodChannel('app.lockin/windows');
  static final _closeDesktop = DynamicLibrary.open(
    'user32.dll',
  ).lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseDesktop');
  bool get isWindows => Platform.isWindows;
  bool get isAndroid => Platform.isAndroid;
  bool get supported => isWindows || isAndroid;

  Future<bool> hasAccess() async {
    if (isWindows) return true;
    if (isAndroid) {
      return await channel
              .invokeMethod<bool>('hasUsageAccess')
              .timeout(const Duration(seconds: 20)) ??
          false;
    }
    return false;
  }

  void bindWindowsForeground(void Function()? onChanged) {
    windowsChannel.setMethodCallHandler(
      onChanged == null
          ? null
          : (call) async {
              if (call.method == 'foregroundChanged') onChanged();
            },
    );
  }

  Future<bool> setWindowsForegroundWatch(bool enabled) async =>
      await windowsChannel.invokeMethod<bool>('setForegroundWatch', {
        'enabled': enabled,
      }) ??
      false;

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
        processId: pid.value,
      );
    } finally {
      if (process != 0) CloseHandle(process);
      calloc.free(pid);
      calloc.free(size);
      calloc.free(buffer);
    }
  }

  Future<WindowsActivityStatus> windowsActivity(int processId) async {
    final value = await windowsChannel
        .invokeMapMethod<String, dynamic>('activityState', {'pid': processId})
        .timeout(const Duration(seconds: 20));
    return WindowsActivityStatus.fromMap(value ?? {});
  }

  Future<AndroidTrackingStatus> initializeAndroidTracking(bool enabled) async {
    final value = await channel
        .invokeMapMethod<String, dynamic>('initializeTracking', {
          'enabled': enabled,
        })
        .timeout(const Duration(seconds: 20));
    return AndroidTrackingStatus.fromMap(value ?? {});
  }

  Future<AndroidTrackingStatus> setAndroidTracking(bool enabled) async {
    final value = await channel
        .invokeMapMethod<String, dynamic>('setTrackingEnabled', {
          'enabled': enabled,
        })
        .timeout(const Duration(seconds: 20));
    return AndroidTrackingStatus.fromMap(value ?? {});
  }

  Future<AndroidTrackingStatus> androidStatus() async {
    final value = await channel
        .invokeMapMethod<String, dynamic>('trackingStatus')
        .timeout(const Duration(seconds: 20));
    return AndroidTrackingStatus.fromMap(value ?? {});
  }

  void bindAndroidActions({
    required void Function() onDismiss,
    required Future<void> Function() onStopped,
    required void Function() onForegroundChanged,
  }) {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dismissRequested':
          onDismiss();
        case 'trackingStopped':
          await onStopped();
        case 'foregroundChanged':
          onForegroundChanged();
        default:
          throw MissingPluginException(
            'Unknown Android callback: ${call.method}',
          );
      }
    });
  }

  /// Apps on this phone with a home-screen icon: package name to app name.
  Future<Map<String, String>> androidInstalledApps() async {
    final value = await channel
        .invokeMapMethod<String, String>('installedApps')
        .timeout(const Duration(seconds: 20));
    return value ?? {};
  }

  /// Installed Android app labels and PNG icons, keyed by package name.
  /// Packages that are not installed are omitted.
  Future<Map<String, ({String label, Uint8List icon})>> androidAppDetails(
    List<String> packages,
  ) async {
    final value = await channel
        .invokeMapMethod<String, dynamic>('appDetails', {'packages': packages})
        .timeout(const Duration(seconds: 20));
    return {
      for (final MapEntry(:key, :value) in (value ?? {}).entries)
        key: (
          label: (value as Map)['label'] as String,
          icon: value['icon'] as Uint8List,
        ),
    };
  }

  /// Icons and names of Windows apps that are running or registered, keyed
  /// by lowercase executable name. Apps that cannot be found are omitted.
  Future<Map<String, ({String label, Uint8List icon})>> windowsAppDetails(
    List<String> executables,
  ) async {
    final details = <String, ({String label, Uint8List icon})>{};
    // The native side looks up a bounded number of apps per call.
    for (var i = 0; i < executables.length; i += 32) {
      final value = await windowsChannel
          .invokeMapMethod<String, dynamic>('appDetails', {
            'executables': executables.sublist(
              i,
              math.min(i + 32, executables.length),
            ),
          })
          .timeout(const Duration(seconds: 20));
      for (final MapEntry(:key, :value) in (value ?? {}).entries) {
        details[key] = (
          label: (value as Map)['label'] as String,
          icon: value['icon'] as Uint8List,
        );
      }
    }
    return details;
  }

  Future<void> openInstantBlocking() =>
      channel.invokeMethod<void>('openInstantBlocking');
  Future<void> requestBlockingAccess() =>
      channel.invokeMethod<void>('requestBlockingAccess');
  Future<String?> androidForegroundSource() => channel
      .invokeMethod<String>('foregroundSource')
      .timeout(const Duration(seconds: 20));
  Future<void> showAndroidBlock(String source, String message) => channel
      .invokeMethod<void>('showBlock', {'source': source, 'message': message});
  Future<void> hideAndroidBlock() => channel.invokeMethod<void>('hideBlock');

  Future<List<UsageInterval>> androidHistory(
    String deviceId,
    DateTime from,
    DateTime until,
  ) async {
    if (!isAndroid) return [];
    final values =
        await channel
            .invokeListMethod<dynamic>('readUsage', {
              'from': from.millisecondsSinceEpoch,
              'until': until.millisecondsSinceEpoch,
            })
            .timeout(const Duration(seconds: 20)) ??
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
