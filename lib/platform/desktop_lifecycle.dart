import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'native_tracker.dart';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keep a user-session tray app, not a Windows service in the wrong desktop.
class DesktopLifecycle with WindowListener, TrayListener {
  DesktopLifecycle({
    required this.quit,
    this.manageStartup = true,
    LaunchAtStartup? startup,
  }) : _startup = startup ?? launchAtStartup;
  final Future<void> Function() quit;
  final bool manageStartup;
  final LaunchAtStartup _startup;
  Future<void> _restrictionWork = Future.value();
  int _restrictionEpoch = 0;
  bool _restrictionRequested = false;
  bool _restrictionVisible = false;

  /// Whether the window can be seen: not hidden in the tray or minimized.
  final visible = ValueNotifier(true);

  Future<void> initialize({bool background = false}) async {
    await windowManager.ensureInitialized();
    if (manageStartup) {
      _startup.setup(
        // Keep the existing registry identity to avoid duplicate startup entries.
        appName: 'Lockin',
        appPath: Platform.resolvedExecutable,
        args: ['--background'],
      );
    }
    await trayManager.setIcon('assets/tray.ico');
    await trayManager.setToolTip('Grindset - foreground activity and focus');
    await trayManager.setContextMenu(_menu());
    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1120, 720),
        minimumSize: const Size(840, 560),
        center: true,
        title: 'Grindset',
        backgroundColor: const Color(0xFF09090A),
      ),
    );
    // The SDK callback is void-returning; do not discard visibility failures
    // or finish initialization before the OS show/hide operation completes.
    if (background) {
      await windowManager.hide();
    } else {
      await show();
    }
    visible.value = !background;
  }

  /// Whether Grindset starts when the user signs in to Windows, including
  /// Task Manager's Startup apps switch. Null where startup is not managed.
  Future<bool?> startupEnabled() async =>
      manageStartup ? await _startup.isEnabled() : null;

  Future<void> enableStartup() async {
    if (manageStartup) await _startup.enable();
  }

  Future<void> disableStartup() async {
    if (manageStartup) await _startup.disable();
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _serializeRestriction(Future<void> Function() action) {
    final operation = _restrictionWork.then((_) => action());
    _restrictionWork = operation.catchError((Object _) {});
    return operation;
  }

  Future<bool> showRestriction(ForegroundApp app) async {
    final epoch = ++_restrictionEpoch;
    _restrictionRequested = true;
    var shown = false;
    await _serializeRestriction(() async {
      if (epoch != _restrictionEpoch) return;
      final status = await NativeTracker.windowsChannel
          .invokeMethod<String>('presentRestriction', {
            'pid': app.processId,
            'source': app.source,
          })
          .timeout(const Duration(seconds: 5));
      _restrictionVisible = shown = status == 'shown';
    });
    return shown && epoch == _restrictionEpoch;
  }

  Future<void> dismissRestriction() {
    if (!_restrictionRequested && !_restrictionVisible) return Future.value();
    ++_restrictionEpoch;
    _restrictionRequested = false;
    return _serializeRestriction(() async {
      _restrictionVisible = false;
      await NativeTracker.windowsChannel
          .invokeMethod<void>('dismissRestriction')
          .timeout(const Duration(seconds: 5));
    });
  }

  static const _keepRunningTask = 'Grindset strict mode';

  /// While strict mode is locked, Windows reopens Grindset in the background
  /// every minute if it was ended, and Quit is unavailable.
  Future<void> keepRunning(bool locked) async {
    await trayManager.setContextMenu(_menu(quitLocked: locked));
    final result = await Process.run('schtasks.exe', [
      if (locked) ...[
        '/create',
        '/tn',
        _keepRunningTask,
        '/sc',
        'minute',
        '/mo',
        '1',
        '/f',
        '/tr',
        '"${Platform.resolvedExecutable}" --background',
      ] else ...[
        '/delete',
        '/tn',
        _keepRunningTask,
        '/f',
      ],
    ]);
    // Deleting a task that does not exist is fine.
    if (locked && result.exitCode != 0) {
      throw StateError('Could not keep Grindset running: ${result.stderr}');
    }
  }

  Menu _menu({bool quitLocked = false}) => Menu(
    items: [
      MenuItem(key: 'open', label: 'Open Grindset'),
      MenuItem.separator(),
      MenuItem(
        key: 'quit',
        label: quitLocked
            ? 'Quit (paused by strict mode)'
            : 'Quit (stops tracking)',
        disabled: quitLocked,
      ),
    ],
  );

  @override
  void onWindowEvent(String eventName) {
    switch (eventName) {
      case 'show' || 'restore':
        visible.value = true;
      case 'hide' || 'minimize':
        visible.value = false;
    }
  }

  @override
  void onWindowClose() {
    if (!_restrictionRequested) unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'open') unawaited(show());
    if (menuItem.key == 'quit') unawaited(quit());
  }

  Future<void> dispose() async {
    await dismissRestriction();
    await _restrictionWork;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }
}
