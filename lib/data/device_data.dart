import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_controller.dart';
import 'cloud_sync.dart';
import 'device_auth_storage.dart';

/// Reset is terminal for this runtime. The caller closes the app afterward;
/// the next launch creates a new device identity with tracking off.
class DeviceData {
  DeviceData({required this.controller, this.cloud, this.authStorage});
  final AppController controller;
  final CloudSync? cloud;
  final DeviceAuthStorage? authStorage;

  Future<void> reset() async {
    await controller.prepareForReset();
    await cloud
        ?.close(); // Drain requests before removing their account binding.
    final auth = cloud?.client.auth;
    if (auth != null) {
      try {
        await auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // GoTrue clears the in-memory session before attempting remote logout.
        // Offline reset is safe only if that local sign-out actually happened.
        if (auth.currentSession != null) rethrow;
      }
    }
    await authStorage?.clearForReset();
    await controller.store.clearLocalData();
  }
}
