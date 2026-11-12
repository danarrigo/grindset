import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keep a user-session tray app, not a Windows service in the wrong desktop.
class DesktopLifecycle with WindowListener, TrayListener {
  DesktopLifecycle({required this.quit});
  final Future<void> Function() quit;

  Future<void> initialize({bool background = false}) async {
    await windowManager.ensureInitialized();
    launchAtStartup.setup(
      appName: 'Lockin',
      appPath: Platform.resolvedExecutable,
      args: ['--background'],
    );
    await trayManager.setIcon('assets/tray.ico');
    await trayManager.setToolTip('Lockin - foreground activity and focus');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Open Lockin'),
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
        size: const Size(400, 600),
        minimumSize: const Size(360, 520),
        center: true,
        title: 'Lockin',
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

  Future<void> enableStartup() => launchAtStartup.enable();
  Future<void> disableStartup() => launchAtStartup.disable();
  Future<void> show() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
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
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }
}
