import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/activity.dart';
import '../data/local_store.dart';

class BrowserObservation {
  const BrowserObservation({
    required this.source,
    required this.observedAt,
    required this.mediaPlaying,
  });
  final String source;
  final DateTime observedAt;
  final bool mediaPlaying;
}

/// A paired, loopback-only bridge. Its wire format has hosts, never URLs/titles.
class BrowserBridge {
  BrowserBridge({
    required this.store,
    required this.now,
    required this.trackingEnabled,
    required this.restrictions,
    this.askForPass,
  });
  final LocalStore store;
  final DateTime Function() now;
  final bool Function() trackingEnabled;
  final Map<String, Object> Function() restrictions;

  /// Asks an AI for a few minutes on a blocked site, with a reason.
  final Future<({bool allow, String message, int? minutes})> Function(
    String host,
    String reason,
  )?
  askForPass;
  HttpServer? _server;
  final _requests = <Future<void>>{};
  final _random = Random.secure();
  String _token = '';
  String? _pairing;
  DateTime? _pairingUntil;
  int _attempts = 0;
  final _observations = <String, BrowserObservation>{};
  final _lastHeartbeat = <String, DateTime>{};

  /// Chrome/Edge extension IDs, or a Firefox-based browser's per-install UUID.
  static final _extensionOrigin = RegExp(
    r'^(chrome-extension://[a-p]{32}|moz-extension://[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
  );

  /// The browser an extension reports, and its Windows app.
  static const _browsers = {
    'chrome': 'windows:chrome.exe',
    'edge': 'windows:msedge.exe',
    'firefox': 'windows:firefox.exe',
  };

  /// Firefox-based browsers look identical to the extension, so a "firefox"
  /// heartbeat counts while any of them is in front.
  static const _geckoBrowsers = {
    'windows:firefox.exe',
    'windows:zen.exe',
    'windows:librewolf.exe',
    'windows:floorp.exe',
    'windows:waterfox.exe',
  };
  int get port => _server!.port;
  bool get isListening => _server != null;
  DateTime? lastPolicyRequestAt;

  Future<void> start({int port = 47831}) async {
    if (_server != null) {
      throw StateError('The browser bridge is already running.');
    }
    _token = await store.setting('browser_pair_token') ?? _newToken();
    await store.saveSetting('browser_pair_token', _token);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) {
      late final Future<void> pending;
      pending = _handle(request)
          .catchError((Object error) {
            // A disconnected peer must not terminate the collector. Bodies are never logged.
          })
          .whenComplete(() => _requests.remove(pending));
      _requests.add(pending);
      unawaited(pending);
    });
  }

  String _newToken() =>
      base64Url.encode(List.generate(32, (_) => _random.nextInt(256)));

  String beginPairing() {
    _pairing = _random.nextInt(1000000).toString().padLeft(6, '0');
    _pairingUntil = now().add(const Duration(minutes: 5));
    _attempts = 0;
    return _pairing!;
  }

  Future<void> disconnect() async {
    _token = _newToken();
    await store.saveSetting('browser_pair_token', _token);
    _pairing = null;
    _observations.clear();
    _lastHeartbeat.clear();
    lastPolicyRequestAt = null;
  }

  /// When the extension in this browser last reported, even without a page
  /// open. Switching to a browser makes a running extension report at once.
  DateTime? lastHeartbeat(String foregroundSource) =>
      _lastHeartbeat[_extensionSource(foregroundSource)];

  /// Whether the extension can tell Grindset it runs in this browser.
  static bool supports(String foregroundSource) =>
      _extensionSource(foregroundSource) != null;

  static String? _extensionSource(String foregroundSource) {
    final source = foregroundSource.toLowerCase();
    if (_geckoBrowsers.contains(source)) return _browsers['firefox'];
    return _browsers.values.contains(source) ? source : null;
  }

  BrowserObservation? observationFor(String foregroundSource) {
    if (!trackingEnabled()) return null;
    final value =
        _observations[_geckoBrowsers.contains(foregroundSource)
            ? _browsers['firefox']
            : foregroundSource];
    if (value == null ||
        now().difference(value.observedAt) > const Duration(seconds: 12) ||
        value.observedAt.isAfter(now())) {
      return null;
    }
    return value;
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > 4096) {
        throw const FormatException('Request too large.');
      }
      bytes.addAll(chunk);
    }
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Expected an object.');
    }
    return body;
  }

  void _reply(HttpRequest request, int status, Object value) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final origin = request.headers.value('origin');
      // Privileged extension GETs can omit Origin. Only this read-only route
      // permits that omission, and it still requires the bearer token below.
      final originlessRulesRead =
          origin == null &&
          request.method == 'GET' &&
          request.uri.path == '/v1/rules';
      if (!originlessRulesRead &&
          (origin == null || !_extensionOrigin.hasMatch(origin))) {
        _reply(request, 403, {'error': 'Browser extension origin required.'});
        return;
      }
      if (origin != null) {
        request.response.headers.set('Access-Control-Allow-Origin', origin);
      }
      request.response.headers.set('Cache-Control', 'no-store');
      if (request.method == 'OPTIONS') {
        request.response.headers.set(
          'Access-Control-Allow-Methods',
          'GET,POST,OPTIONS',
        );
        request.response.headers.set(
          'Access-Control-Allow-Headers',
          'Authorization,Content-Type',
        );
        request.response.statusCode = 204;
        return;
      }
      if (request.uri.path == '/v1/pair' && request.method == 'POST') {
        final body = await _body(request);
        if (_pairing == null ||
            _pairingUntil == null ||
            !now().isBefore(_pairingUntil!) ||
            _attempts >= 5 ||
            body['code'] != _pairing) {
          _attempts++;
          _reply(request, 403, {
            'error': 'Pairing code is invalid, expired or rate-limited.',
          });
          return;
        }
        _pairing = null;
        _reply(request, 200, {'token': _token});
        return;
      }
      if (request.headers.value('authorization') != 'Bearer $_token') {
        _reply(request, 401, {
          'error': 'Pair the extension with Grindset first.',
        });
        return;
      }
      if (request.uri.path == '/v1/rules' && request.method == 'GET') {
        _reply(request, 200, restrictions());
        lastPolicyRequestAt = now();
      } else if (request.uri.path == '/v1/heartbeat' &&
          request.method == 'POST') {
        final body = await _body(request);
        if (body.keys.any(
              (key) => !{
                'browser',
                'domain',
                'focused',
                'mediaPlaying',
              }.contains(key),
            ) ||
            !_browsers.containsKey(body['browser']) ||
            body['focused'] is! bool ||
            body['mediaPlaying'] is! bool) {
          throw const FormatException('Invalid heartbeat.');
        }
        final browserSource = _browsers[body['browser']]!;
        _lastHeartbeat[browserSource] = now();
        final domain = body['domain'];
        if (domain != null &&
            (domain is! String || websiteHost(domain) == null)) {
          throw const FormatException('Host identifiers only.');
        }
        if (trackingEnabled() && body['focused'] == true && domain is String) {
          _observations[browserSource] = BrowserObservation(
            source: 'web:${websiteHost(domain)}',
            observedAt: now(),
            mediaPlaying: body['mediaPlaying'] == true,
          );
        } else {
          _observations.remove(browserSource);
        }
        _reply(request, 200, {'enabled': trackingEnabled()});
      } else if (request.uri.path == '/v1/pass' &&
          request.method == 'POST' &&
          askForPass != null) {
        final body = await _body(request);
        final domain = body['domain'];
        final reason = body['reason'];
        if (body.keys.any((key) => key != 'domain' && key != 'reason') ||
            domain is! String ||
            websiteHost(domain) == null ||
            reason is! String ||
            reason.trim().isEmpty ||
            reason.length > 120) {
          throw const FormatException('Invalid request.');
        }
        try {
          final verdict = await askForPass!(websiteHost(domain)!, reason);
          _reply(request, 200, {
            'allow': verdict.allow,
            'message': verdict.message,
            'minutes': ?verdict.minutes,
          });
        } on Exception catch (error) {
          // The AI check's own errors are written for people.
          _reply(request, 200, {'allow': false, 'message': '$error'});
        }
      } else {
        _reply(request, 404, {'error': 'Unknown browser request.'});
      }
    } on FormatException {
      _reply(request, 400, {
        'error': 'Invalid request. Send host identifiers, never page URLs or titles.',
      });
    } on Exception {
      // Never log a request body or reflect it into an error response.
      try {
        _reply(request, 503, {
          'error': 'The local browser bridge is unavailable.',
        });
      } catch (_) {
        /* Disconnected client. */
      }
    } finally {
      try {
        await request.response.close();
      } on Exception {
        /* Disconnected client. */
      }
    }
  }

  Future<void> close() async {
    _observations.clear();
    lastPolicyRequestAt = null;
    await _server?.close(force: true);
    _server = null;
    await Future.wait(_requests.toList());
  }
}
