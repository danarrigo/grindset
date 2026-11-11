import 'dart:io';

import 'package:flutter/material.dart';
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
import 'data/local_store.dart';
import 'platform/desktop_lifecycle.dart';
import 'platform/native_tracker.dart';
import 'ui/appearance.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final store = LocalStore.file(
      File(p.join(directory.path, 'lockin.sqlite')),
    );
    final controller = AppController(store: store, tracker: NativeTracker());
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    await controller.initialize(initialTimezone: zone);
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    CloudSync? cloud;
    String? startupWarning;
    if (url.isNotEmpty && key.isNotEmpty) {
      try {
        await Supabase.initialize(url: url, publishableKey: key);
        cloud = CloudSync(client: Supabase.instance.client, store: store);
        await cloud.startAutomatic(
          deviceId: controller.deviceId,
          platform: Platform.isWindows ? 'Windows' : 'Android',
          since: () => accountDay(controller.now, controller.location).$1,
          onDownloaded: controller.reloadUsage,
        );
      } catch (error) {
        startupWarning =
            'Cloud setup failed; local mode remains available. $error';
      }
    }
    DesktopLifecycle? desktop;
    if (Platform.isWindows) {
      desktop = DesktopLifecycle(
        quit: () async {
          await cloud?.close();
          controller.dispose();
          await store.close();
          await desktop?.dispose();
          await windowManager.destroy();
        },
      );
      try {
        await desktop.initialize(background: args.contains('--background'));
        controller.showBlock = desktop.show;
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
        enableStartup: desktop?.enableStartup,
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
                'Lockin could not open its local database or platform settings.\n\n$error\n\nYour data has not been reset. Fix the issue and restart.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
