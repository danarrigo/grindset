import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Website logos, fetched once from the site itself and kept on disk.
///
/// Requests go only to the site being shown (its home page and icon files),
/// never to a third-party icon service, and carry no cookies or account data.
class SiteLogos {
  SiteLogos(this.directory);
  final Directory directory;

  static const _maxBytes = 512 * 1024;
  static const _keep = Duration(days: 30);
  static const _retry = Duration(days: 3);

  final _memory = <String, Uint8List?>{};
  final _loading = <String, Future<Uint8List?>>{};
  int _running = 0;
  final _waiting = <Completer<void>>[];

  /// The logo if it is already loaded; null while loading or if none.
  Uint8List? cached(String host) => _memory[host];

  /// Loads a logo from disk, or from the site when missing or stale.
  Future<Uint8List?> load(String host) {
    if (_memory.containsKey(host)) return Future.value(_memory[host]);
    return _loading[host] ??= _load(host)
        // A block body: returning the removed future would make the load
        // wait for itself and never finish.
        .whenComplete(() {
          _loading.remove(host);
        });
  }

  Future<Uint8List?> _load(String host) async {
    final file = File('${directory.path}${Platform.pathSeparator}$host');
    Uint8List? logo;
    try {
      final stat = file.statSync();
      final fresh =
          stat.type == FileSystemEntityType.file &&
          DateTime.now().difference(stat.modified) <
              (stat.size == 0 ? _retry : _keep);
      if (fresh) {
        logo = stat.size == 0 ? null : await file.readAsBytes();
        return _memory[host] = logo;
      }
    } on FileSystemException {
      // Not cached yet.
    }
    await _slot();
    try {
      // A slow or stalling site gives up quickly and keeps its letter tile.
      logo = await _fetch(host)
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
    } finally {
      _release();
    }
    try {
      await directory.create(recursive: true);
      // An empty file remembers "no logo" so the site is not asked again
      // for a few days.
      await file.writeAsBytes(logo ?? Uint8List(0), flush: true);
    } on FileSystemException {
      // Still shown this session.
    }
    return _memory[host] = logo;
  }

  // At most four sites at a time, so a big rule does not open dozens of
  // connections at once.
  Future<void> _slot() async {
    if (_running < 4) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _running--;
    } else {
      _waiting.removeAt(0).complete();
    }
  }

  Future<Uint8List?> _fetch(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 (compatible; Grindset)';
    try {
      final home = Uri.https(host, '/');
      final candidates = <Uri>[];
      final page = await _get(client, home);
      if (page != null) {
        candidates.addAll(
          _iconLinks(utf8.decode(page.$1, allowMalformed: true), page.$2),
        );
      }
      candidates.addAll([
        home.resolve('/apple-touch-icon.png'),
        home.resolve('/favicon.ico'),
      ]);
      // Keep the sharpest: a site's first icon is often a tiny favicon.
      final tried = <Uri>{};
      Uint8List? best;
      var bestWidth = 0;
      for (final uri in candidates) {
        if (uri.scheme != 'https' || !tried.add(uri) || tried.length > 6) {
          continue;
        }
        final body = await _get(client, uri);
        if (body == null) continue;
        final width = await _width(body.$1);
        if (width > bestWidth) {
          best = body.$1;
          bestWidth = width;
        }
        if (bestWidth >= 96) break;
      }
      return bestWidth >= 16 ? best : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The body and final address of a successful small response.
  Future<(Uint8List, Uri)?> _get(HttpClient client, Uri uri) async {
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200 || response.contentLength > _maxBytes) {
        await response.drain<void>().catchError((_) {});
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.add(chunk);
        if (bytes.length > _maxBytes) return null;
      }
      final redirects = response.redirects;
      final at = redirects.isEmpty
          ? uri
          : uri.resolveUri(redirects.last.location);
      return (bytes.takeBytes(), at);
    } catch (_) {
      return null;
    }
  }

  /// Icons the page declares, best first: touch icons are large PNGs, then
  /// the biggest declared icon. SVG cannot be shown, so it is skipped.
  static List<Uri> _iconLinks(String html, Uri page) {
    final found = <(int, Uri)>[];
    for (final tag in RegExp(
      r'<link\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html).map((m) => m[0]!)) {
      String? attribute(String name) => RegExp(
        '\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
        caseSensitive: false,
      ).firstMatch(tag)?.let((m) => m[2] ?? m[3] ?? m[4]);
      final rel = attribute('rel')?.toLowerCase() ?? '';
      final href = attribute('href');
      if (href == null || !rel.contains('icon')) continue;
      final type = attribute('type')?.toLowerCase() ?? '';
      if (type.contains('svg') || href.toLowerCase().contains('.svg')) {
        continue;
      }
      final Uri uri;
      try {
        uri = page.resolve(href.trim());
      } on FormatException {
        continue;
      }
      final size =
          int.tryParse(
            RegExp(r'(\d+)x\d+').firstMatch(attribute('sizes') ?? '')?[1] ?? '',
          ) ??
          0;
      final rank = rel.contains('apple-touch-icon') ? 1000 + size : size;
      found.add((rank, uri));
    }
    found.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final entry in found) entry.$2];
  }

  /// The image's width, or 0 when it cannot be shown or would be invisible
  /// on the white tile (a white logo on a transparent background).
  static Future<int> _width(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final pixels = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      codec.dispose();
      if (pixels == null) return 0;
      var visible = 0;
      var opaque = 0;
      for (var i = 0; i + 3 < pixels.lengthInBytes; i += 4) {
        if (pixels.getUint8(i + 3) < 128) continue;
        opaque++;
        final light =
            pixels.getUint8(i) > 230 &&
            pixels.getUint8(i + 1) > 230 &&
            pixels.getUint8(i + 2) > 230;
        if (!light) visible++;
      }
      return opaque > 0 && visible >= opaque * .05 ? width : 0;
    } catch (_) {
      return 0;
    }
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
