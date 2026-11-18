import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_controller.dart';
import 'core/activity.dart';
import 'data/cloud_sync.dart';
import 'data/device_auth_storage.dart';
import 'data/device_data.dart';
import 'data/local_store.dart';
import 'platform/desktop_lifecycle.dart';
import 'platform/browser_bridge.dart';
import 'platform/native_tracker.dart';
import 'platform/completion_alerts.dart';
import 'platform/export_files.dart';
import 'platform/site_logos.dart';
import 'ui/appearance.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    final dataArgument = args
        .where((a) => a.startsWith('--data-dir='))
        .firstOrNull;
    final customDirectory = dataArgument?.substring('--data-dir='.length);
    if (customDirectory != null && customDirectory.isEmpty) {
      throw ArgumentError('The data directory must not be empty.');
    }
    final directory = customDirectory == null
        ? await getApplicationSupportDirectory()
        : Directory(customDirectory);
    await directory.create(recursive: true);
    final store = LocalStore.file(
      File(p.join(directory.path, 'lockin.sqlite')),
    );
    final controller = AppController(
      store: store,
      tracker: NativeTracker(),
      completionAlerts:
          !args.contains('--no-alerts') &&
              (Platform.isWindows || Platform.isAndroid)
          ? CompletionAlerts(android: Platform.isAndroid)
          : null,
    );
    controller.siteLogos = SiteLogos(
      Directory(p.join(directory.path, 'logos')),
    );
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    await controller.initialize(initialTimezone: zone);
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    CloudSync? cloud;
    DeviceAuthStorage? authStorage;
    String? startupWarning;
    // Isolated native acceptance must not reuse a real account's auth storage.
    if (!args.contains('--local-only') && url.isNotEmpty && key.isNotEmpty) {
      try {
        authStorage = DeviceAuthStorage(
          SharedPreferencesLocalStorage(
            persistSessionKey:
                'sb-${Uri.parse(url).host.split('.').first}-auth-token',
          ),
        );
        await Supabase.initialize(
          url: url,
          publishableKey: key,
          authOptions: FlutterAuthClientOptions(localStorage: authStorage),
        );
        cloud = CloudSync(client: Supabase.instance.client, store: store);
        await cloud.startAutomatic(
          deviceId: controller.deviceId,
          platform: Platform.isWindows ? 'Windows' : 'Android',
          since: () => accountDay(controller.now, controller.location).$1,
          onDownloaded: controller.reloadSharedState,
        );
        controller.onSharedChange = cloud.requestSync;
      } catch (error) {
        startupWarning =
            'Cloud setup failed; local mode remains available. $error';
      }
    }
    DesktopLifecycle? desktop;
    Future<void>? closing;
    Future<void> quit() => closing ??= () async {
      await cloud?.close();
      await controller.browserBridge?.close();
      controller.dispose();
      await store.close();
      await desktop?.dispose();
      if (Platform.isWindows) {
        await windowManager.destroy();
      } else {
        await SystemNavigator.pop();
      }
    }();
    Future<void> resetDevice() async {
      try {
        await DeviceData(
          controller: controller,
          cloud: cloud,
          authStorage: authStorage,
        ).reset();
        await desktop?.disableStartup();
        await quit();
      } catch (error) {
        // A partial reset must not return to a runtime with disposed sync or
        // sealed credentials. Keep only a safe, closable recovery surface.
        runApp(
          MaterialApp(
            theme: lockinTheme(Brightness.light),
            darkTheme: lockinTheme(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Reset could not finish'),
                      const SizedBox(height: 16),
                      SelectableText(
                        'Some steps may have completed. Close and reopen Grindset before retrying. Cloud records were not deleted.\n\n$error',
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: quit,
                        child: const Text('Close Grindset'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        if (Platform.isWindows) await windowManager.setPreventClose(false);
        return;
      }
    }

    if (Platform.isWindows) {
      final bridge = BrowserBridge(
        store: store,
        now: () => controller.now,
        trackingEnabled: () => controller.trackingEnabled,
        restrictions: controller.websiteRestrictions,
        onOverride: controller.overrideSource,
      );
      try {
        await bridge.start();
        controller.browserBridge = bridge;
      } catch (error) {
        startupWarning =
            'The browser extension bridge could not start. App tracking still works: $error';
      }
      desktop = DesktopLifecycle(
        quit: quit,
        manageStartup: customDirectory == null,
      );
      try {
        await desktop.initialize(background: args.contains('--background'));
        controller.restrictWindowsApp = desktop.showRestriction;
        controller.restoreWindowsApp = desktop.restoreRestrictedApp;
        controller.addListener(() {
          if (controller.blockedSource == null) {
            unawaited(
              desktop!.dismissRestriction().catchError((Object error) {
                controller.reportRestrictionFailure(error);
              }),
            );
          }
        });
        controller.requestForegroundCheck();
      } catch (error) {
        startupWarning =
            'Tray setup failed. Background operation is not ready: $error';
        // Do not hide the only window when no usable tray exists.
        await windowManager.setPreventClose(false);
        await windowManager.show();
      }
    }
    runApp(
      LockinApp(
        controller: controller,
        cloud: cloud,
        startupWarning: startupWarning,
        enableStartup: desktop?.manageStartup == true
            ? desktop?.enableStartup
            : null,
        exportData: () => ExportFiles.save(store, exportedAt: controller.now),
        resetDevice: resetDevice,
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        theme: lockinTheme(Brightness.light),
        darkTheme: lockinTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'Grindset could not open its local database or platform settings.\n\n$error\n\nYour data has not been reset. Fix the issue and restart.',
              ),
            ),
          ),
        ),
      ),
    );
    if (Platform.isWindows) {
      // The runner no longer overrides Dart visibility on its first frame.
      // Fatal startup must still expose a closable window, even at sign-in.
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(false);
      await windowManager.show();
    }
  }
}
