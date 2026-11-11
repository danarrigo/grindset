import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/activity.dart';
import '../data/cloud_sync.dart';

class CloudPanel extends StatefulWidget {
  const CloudPanel({
    super.key,
    required this.controller,
    this.cloud,
    required this.onChanged,
  });
  final AppController controller;
  final CloudSync? cloud;
  final VoidCallback onChanged;
  @override
  State<CloudPanel> createState() => _CloudPanelState();
}

class _CloudPanelState extends State<CloudPanel> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onChanged();
      }
    }
  }

  Future<void> _authenticate(bool create) => _run(() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.isEmpty) {
      throw ArgumentError('Enter an email and password.');
    }
    final auth = widget.cloud!.client.auth;
    if (create) {
      if (_password.text.length < 8) {
        throw ArgumentError('Use at least 8 characters.');
      }
      await auth.signUp(email: email, password: _password.text);
      if (mounted) {
        setState(
          () => _message =
              'Check your email to confirm your account, then sign in.',
        );
      }
    } else {
      await auth.signInWithPassword(email: email, password: _password.text);
    }
    _password.clear();
  });

  @override
  Widget build(BuildContext context) {
    final cloud = widget.cloud;
    final user = cloud?.client.auth.currentUser;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account & cloud', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (cloud == null) ...[
          const Text(
            'Cloud sync is not configured. Your timers and history still work locally.',
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Add your public Supabase configuration and apply the migration. See README.md for setup.',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ] else if (user == null) ...[
          const Text(
            'Sign in on each device to synchronize usage automatically.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) {
              if (!_busy) _authenticate(false);
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _authenticate(false),
                child: const Text('Sign in'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _authenticate(true),
                child: const Text('Create account'),
              ),
            ],
          ),
        ] else ...[
          Text(user.email ?? 'Signed in'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy || cloud.syncing
                    ? null
                    : () => _run(() async {
                        await cloud.synchronize(
                          deviceId: widget.controller.deviceId,
                          platform: widget.controller.tracker.isWindows
                              ? 'Windows'
                              : 'Android',
                          since: accountDay(
                            widget.controller.now,
                            widget.controller.location,
                          ).$1,
                        );
                        await widget.controller.reloadUsage();
                        if (mounted) {
                          setState(() => _message = 'Usage synchronized.');
                        }
                      }),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sync now'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(cloud.client.auth.signOut),
                child: const Text('Sign out'),
              ),
            ],
          ),
          if (cloud.lastSync != null)
            Text(
              'Last successful usage sync: ${cloud.lastSync!.toLocal()}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Usage sync runs automatically while signed in, including background tracking. Offline uploads retry with backoff. Shared sessions, rules and account-timezone sync are not connected yet.',
          style: TextStyle(fontSize: 12, color: colors.tertiary, height: 1.6),
        ),
        if (cloud?.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(
              'Usage sync needs attention: ${cloud!.lastError}. Last-confirmed data is kept locally.',
            ),
          ),
        if (_busy || (cloud?.syncing ?? false))
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(_message!),
          ),
      ],
    );
  }
}
