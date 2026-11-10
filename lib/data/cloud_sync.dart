import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/activity.dart';
import 'local_store.dart';

/// This checkpoint syncs usage and device heartbeats, not session/rule state.
class CloudSync {
  CloudSync({required this.client, required this.store});
  final SupabaseClient client;
  final LocalStore store;
  bool _busy = false;
  List<Map<String, dynamic>> devices = [];
  DateTime? lastSync;

  Future<void> synchronize({
    required String deviceId,
    required String platform,
    required DateTime since,
  }) async {
    if (_busy) return;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before syncing.');
    _busy = true;
    try {
      final owner = await store.setting('cloud_owner');
      if (owner != null && owner != user.id) {
        throw StateError(
          'This local database belongs to a different account. Do not upload it to another user.',
        );
      }
      await store.saveSetting('cloud_owner', user.id);
      await client.from('devices').upsert({
        'user_id': user.id,
        'id': deviceId,
        'label': '$platform device',
        'platform': platform,
      }, onConflict: 'user_id,id');
      final pending = await store.usage(pendingOnly: true);
      for (var start = 0; start < pending.length; start += 100) {
        final batch = pending.skip(start).take(100).toList();
        await client
            .from('usage_intervals')
            .upsert(
              batch.map((i) => {...i.toJson(), 'user_id': user.id}).toList(),
              onConflict: 'user_id,id',
            );
        for (final interval in batch) {
          await store.markUploaded(interval);
        }
      }
      // Paginate explicitly: Supabase's default row limit is not a day boundary.
      for (var offset = 0; ; offset += 500) {
        final rows = await client
            .from('usage_intervals')
            .select()
            .eq('user_id', user.id)
            .gt('ended_at', since.toIso8601String())
            .order('id')
            .range(offset, offset + 499);
        await store.transaction(() async {
          for (final row in rows) {
            await store.putUsage(UsageInterval.fromJson(row), pending: false);
          }
        });
        if (rows.length < 500) break;
      }
      devices = await client
          .from('devices')
          .select()
          .eq('user_id', user.id)
          .order('label');
      lastSync = DateTime.now().toUtc();
      await store.saveSetting('last_usage_sync', lastSync!.toIso8601String());
    } finally {
      _busy = false;
    }
  }
}
