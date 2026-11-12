import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase emits persistence callbacks without awaiting them. Serialize those
/// writes and seal storage before a reset so a late refresh cannot restore auth.
class DeviceAuthStorage extends LocalStorage {
  DeviceAuthStorage(this._delegate);
  final LocalStorage _delegate;
  Future<void> _tail = Future.value();
  bool _sealed = false;

  Future<void> _queue(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<void> initialize() => _delegate.initialize();
  @override
  Future<bool> hasAccessToken() async {
    await _tail;
    return _delegate.hasAccessToken();
  }

  @override
  Future<String?> accessToken() async {
    await _tail;
    return _delegate.accessToken();
  }

  @override
  Future<void> persistSession(String session) => _queue(() async {
    if (!_sealed) await _delegate.persistSession(session);
  });
  @override
  Future<void> removePersistedSession() =>
      _queue(_delegate.removePersistedSession);

  Future<void> clearForReset() async {
    _sealed = true;
    await _queue(_delegate.removePersistedSession);
  }
}
