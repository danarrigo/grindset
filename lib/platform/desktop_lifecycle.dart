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
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Open Grindset'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit (stops tracking)'),
        ],
      ),
    );
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
  }

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
