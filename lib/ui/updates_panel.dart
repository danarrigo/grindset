import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform/app_updates.dart';

class UpdatesPanel extends StatefulWidget {
  const UpdatesPanel({
    super.key,
    this.loadVersion,
    this.loadRelease,
    this.openDownload,
    this.android,
  });

  final Future<String> Function()? loadVersion;
  final Future<AppRelease> Function()? loadRelease;
  final Future<bool> Function(Uri)? openDownload;
  final bool? android;

  @override
  State<UpdatesPanel> createState() => _UpdatesPanelState();
}

class _UpdatesPanelState extends State<UpdatesPanel> {
  bool _busy = false;
  String? _installed;
  String? _message;
  AppRelease? _release;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = null;
      _release = null;
    });
    try {
      final installed =
          await (widget.loadVersion?.call() ??
              PackageInfo.fromPlatform().then((info) => info.version));
      final release =
          await (widget.loadRelease?.call() ?? const AppUpdates().latest());
      final newer = release.isNewerThan(installed);
      if (mounted) {
        setState(() {
          _installed = installed;
          _release = newer ? release : null;
          _message = newer
              ? null
              : 'No newer release found. Installed v$installed.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not check for updates. Check your connection and try again. Your installation has not changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final release = _release;
    if (release == null) return;
    final url = release.downloadUrl(
      android: widget.android ?? Platform.isAndroid,
    );
    try {
      final opened =
          await (widget.openDownload?.call(url) ??
              launchUrl(url, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Browser did not open.');
      if (mounted) {
        setState(
          () => _message = 'Download opened in your browser. Run the installer or open the APK and approve the update. Do not uninstall your existing release.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message = 'Could not open your browser. Download manually: $url',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        widget.android != null || Platform.isWindows || Platform.isAndroid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('App updates', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'Check for a new release, then download it through your browser. You choose when to install; existing release data stays in place. Nothing is silently installed.',
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy || !supported ? null : _check,
          icon: const Icon(Icons.system_update_outlined),
          label: Text(_busy ? 'Checking...' : 'Check for updates'),
        ),
        if (_release case final release?) ...[
          const SizedBox(height: 16),
          Text(
            'Grindset ${release.version} is available',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_installed != null) Text('Installed v$_installed'),
          const SizedBox(height: 8),
          Text(release.notes),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('Download update'),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          SelectableText(_message!),
        ],
        const SizedBox(height: 12),
        Text(
          'Android release APKs cannot replace differently signed debug previews. Export before changing signing identities. Windows installers remain unsigned; do not disable security protections.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
