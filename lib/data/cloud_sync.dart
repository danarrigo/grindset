import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/activity.dart';
import 'local_store.dart';
import 'shared_state.dart';

/// Confirmed usage is retryable and idempotent; offline intervals are never guessed.
class CloudSync extends ChangeNotifier {
  CloudSync({required this.client, required this.store});
  final SupabaseClient client;
  final LocalStore store;
  late final _shared = SharedState(store);
  List<SharedConflict> conflicts = [];
  String? notice;
  static const _requestTimeout = Duration(seconds: 20);
  Future<void>? _inFlight;
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  bool _busy = false;
  bool _disposed = false;
  bool _automaticRunning = false;
  bool _queued = false;
  VoidCallback? _wake;

  void requestSync() {
    if (_disposed) return;
    _queued = true;
    if (!_busy && !_automaticRunning) _wake?.call();
  }

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
        if (_automaticRunning || _busy) {
          schedule(interval);
          return;
        }
        _automaticRunning = true;
        _queued = false;
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
            _queued
                ? Duration.zero
                : Duration(
                    milliseconds: math.min(
                      300000,
                      interval.inMilliseconds * (1 << _failures),
                    ),
                  ),
          );
        }
      });
    }

    _wake = () => schedule(Duration.zero);
    _auth = client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user.id;
      if (visibleUser != user) {
        visibleUser = user;
        devices = [];
        conflicts = [];
        notice = null;
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
          if (_queued && !_automaticRunning && !_disposed) _wake?.call();
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
      await _synchronizeShared(user.id, deviceId);
      final zone = tz.getLocation(await store.setting('timezone') ?? 'UTC');
      final canonicalDay = accountDay(DateTime.now().toUtc(), zone).$1;
      final usageSince = canonicalDay.isBefore(since) ? canonicalDay : since;
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
            .gt('ended_at', usageSince.toIso8601String())
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

  Future<void> _synchronizeShared(String owner, String deviceId) async {
    await _shared.seed();
    Future<void> upload(List<SharedChange> changes) async {
      if (changes.isEmpty) return;
      _checkActive(owner);
      final response = await client
          .rpc(
            'apply_shared_changes',
            params: {
              'p_device_id': deviceId,
              'p_expected_owner': owner,
              'p_changes': changes.map((c) => c.toJson()).toList(),
            },
          )
          .timeout(_requestTimeout);
      _checkActive(owner);
      if (response is! List || response.length != changes.length) {
        throw const FormatException(
          'Shared sync returned incomplete acknowledgements.',
        );
      }
      final byId = {for (final change in changes) change.mutationId: change};
      final seen = <String>{};
      await store.transaction(() async {
        for (final item in response) {
          final result = Map<String, dynamic>.from(item as Map);
          final id = result['mutation_id'];
          final change = byId[id];
          if (change == null ||
              !seen.add(id as String) ||
              result['applied'] is! bool) {
            throw const FormatException('Invalid shared sync acknowledgement.');
          }
          await _shared.accept(
            change,
            applied: result['applied'] as bool,
            record: Map<String, dynamic>.from(result['record'] as Map),
          );
        }
      });
    }

    // Reconcile the shared slot before capturing history uploads. Losing local
    // sessions are trimmed at the actual reconciliation time, not their deadline.
    await upload(await _shared.pending(focusOnly: true));
    final pending = await _shared.pending(excludeFocus: true);
    for (var offset = 0; offset < pending.length; offset += 100) {
      await upload(pending.skip(offset).take(100).toList());
    }
    var cursor = int.tryParse(await store.setting('shared_cursor') ?? '') ?? 0;
    while (true) {
      _checkActive(owner);
      final rows = await client
          .from('shared_state')
          .select('kind,id,revision,value')
          .eq('user_id', owner)
          .gt('revision', cursor)
          .order('revision')
          .limit(500)
          .timeout(_requestTimeout);
      _checkActive(owner);
      await store.transaction(() async {
        for (final row in rows) {
          final revision = row['revision'] as int;
          if (revision <= cursor) {
            throw const FormatException(
              'Shared sync revisions are not ordered.',
            );
          }
          await _shared.receive(row);
          cursor = revision;
        }
        await store.saveSetting('shared_cursor', '$cursor');
      });
      if (rows.length < 500) break;
    }
    conflicts = await _shared.conflicts();
    notice = await store.setting('shared_notice');
  }

  Future<void> resolveConflict(
    String mutationId, {
    required bool retry,
    int? baseRevision,
  }) async {
    final owner = client.auth.currentUser?.id;
    if (owner == null || owner != await store.setting('cloud_owner')) {
      throw StateError('Sign in to the owner account before resolving edits.');
    }
    _checkActive(owner);
    await _shared.resolveConflict(
      mutationId,
      retry: retry,
      baseRevision: baseRevision,
    );
    conflicts = await _shared.conflicts();
    _changed();
  }

  Future<void> dismissNotice() async {
    await store.saveSetting('shared_notice', '');
    notice = null;
    _changed();
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
    _wake = null;
    _timer?.cancel();
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
