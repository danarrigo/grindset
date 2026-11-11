import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/activity.dart';
import 'local_store.dart';

/// Confirmed usage is retryable and idempotent; offline intervals are never guessed.
class CloudSync extends ChangeNotifier {
  CloudSync({required this.client, required this.store});
  final SupabaseClient client;
  final LocalStore store;
  static const _requestTimeout = Duration(seconds: 20);
  Future<void>? _inFlight;
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  bool _busy = false;
  bool _disposed = false;
  bool _automaticRunning = false;
  int _generation = 0;
  int _failures = 0;
  List<Map<String, dynamic>> devices = [];
  DateTime? lastSync;
  String? lastError;
  bool get syncing => _busy;

  Future<void> startAutomatic({
    required String deviceId,
    required String platform,
    required DateTime Function() since,
    required Future<void> Function() onDownloaded,
    Duration interval = const Duration(seconds: 30),
  }) async {
    if (_disposed) throw StateError('Cloud sync is closed.');
    if (interval <= Duration.zero) {
      throw ArgumentError('Choose a positive sync interval.');
    }
    _timer?.cancel();
    await _auth?.cancel();
    final generation = ++_generation;
    final owner = await store.setting('cloud_owner');
    lastSync = owner == client.auth.currentUser?.id
        ? DateTime.tryParse(await store.setting('last_usage_sync') ?? '')
        : null;
    var visibleUser = client.auth.currentUser?.id;
    void schedule(Duration delay) {
      if (_disposed || generation != _generation) return;
      _timer?.cancel();
      _timer = Timer(delay, () async {
        if (_disposed || generation != _generation) return;
        if (_automaticRunning) {
          schedule(interval);
          return;
        }
        _automaticRunning = true;
        try {
          if (client.auth.currentUser != null) {
            await synchronize(
              deviceId: deviceId,
              platform: platform,
              since: since(),
            );
            if (!_disposed) await onDownloaded();
            _failures = 0;
          }
        } catch (error) {
          _failures = math.min(_failures + 1, 4);
          lastError = error.toString();
          _changed();
        } finally {
          _automaticRunning = false;
          schedule(
            Duration(
              milliseconds: math.min(
                300000,
                interval.inMilliseconds * (1 << _failures),
              ),
            ),
          );
        }
      });
    }

    _auth = client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user.id;
      if (visibleUser != user) {
        visibleUser = user;
        devices = [];
        lastSync = null;
        lastError = null;
        _changed();
      }
      schedule(Duration.zero);
    });
    schedule(Duration.zero);
  }

  Future<void> synchronize({
    required String deviceId,
    required String platform,
    required DateTime since,
  }) {
    if (_disposed) return Future.error(StateError('Cloud sync is closed.'));
    final pending = _inFlight;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation =
        _synchronize(
          deviceId: deviceId,
          platform: platform,
          since: since,
        ).whenComplete(() {
          if (identical(_inFlight, operation)) _inFlight = null;
        });
    _inFlight = operation;
    return operation;
  }

  void _checkActive(String owner) {
    if (_disposed || client.auth.currentUser?.id != owner) {
      throw StateError(
        'Sync stopped because the account or app lifetime changed.',
      );
    }
  }

  Future<void> _synchronize({
    required String deviceId,
    required String platform,
    required DateTime since,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before syncing.');
    _busy = true;
    lastError = null;
    _changed();
    try {
      final owner = await store.setting('cloud_owner');
      if (owner != null && owner != user.id) {
        throw StateError(
          'This local database belongs to a different account. Do not upload it to another user.',
        );
      }
      _checkActive(user.id);
      await store.saveSetting('cloud_owner', user.id);
      await client
          .from('devices')
          .upsert({
            'user_id': user.id,
            'id': deviceId,
            'label': '$platform device',
            'platform': platform,
          }, onConflict: 'user_id,id')
          .timeout(_requestTimeout);
      final pending = await store.usage(pendingOnly: true);
      for (var start = 0; start < pending.length; start += 100) {
        _checkActive(user.id);
        final batch = pending.skip(start).take(100).toList();
        await client
            .from('usage_intervals')
            .upsert(
              batch.map((i) => {...i.toJson(), 'user_id': user.id}).toList(),
              onConflict: 'user_id,id',
            )
            .timeout(_requestTimeout);
        _checkActive(user.id);
        for (final interval in batch) {
          await store.markUploaded(interval);
        }
      }
      // Supabase's row limit is not a day boundary. Fetch every confirmed page.
      for (var offset = 0; ; offset += 500) {
        _checkActive(user.id);
        final rows = await client
            .from('usage_intervals')
            .select()
            .eq('user_id', user.id)
            .gt('ended_at', since.toIso8601String())
            .order('id')
            .range(offset, offset + 499)
            .timeout(_requestTimeout);
        _checkActive(user.id);
        await store.transaction(() async {
          for (final row in rows) {
            await store.putUsage(UsageInterval.fromJson(row), pending: false);
          }
        });
        if (rows.length < 500) break;
      }
      final confirmedDevices = await client
          .from('devices')
          .select()
          .eq('user_id', user.id)
          .order('label')
          .timeout(_requestTimeout);
      _checkActive(user.id);
      final completed = DateTime.now().toUtc();
      await store.saveSetting('last_usage_sync', completed.toIso8601String());
      devices = confirmedDevices;
      lastSync = completed;
    } catch (error) {
      lastError = error.toString();
      rethrow;
    } finally {
      _busy = false;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> close() async {
    dispose();
    try {
      await _inFlight;
    } catch (_) {
      /* Pending observations remain retryable. */
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
