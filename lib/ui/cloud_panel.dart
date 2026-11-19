import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show OtpType, SignOutScope;

import '../app_controller.dart';
import '../core/activity.dart';
import '../data/cloud_sync.dart';
import '../data/shared_state.dart';
import '../platform/app_links.dart';

import 'package:url_launcher/url_launcher.dart';

class CloudPanel extends StatefulWidget {
  const CloudPanel({
    super.key,
    required this.controller,
    this.cloud,
    required this.onChanged,
    this.resetDevice,
  });
  final AppController controller;
  final CloudSync? cloud;
  final VoidCallback onChanged;

  /// Clears this device and closes Grindset; runs after account deletion.
  final Future<void> Function()? resetDevice;
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
      await auth.signUp(
        email: email,
        password: _password.text,
        emailRedirectTo: AppLinks.confirmation.toString(),
      );
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
    final owner = await widget.controller.store.setting('cloud_owner');
    final signedIn = auth.currentUser;
    if (owner != null && signedIn != null && owner != signedIn.id) {
      try {
        await auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        if (auth.currentSession != null) rethrow;
      }
      throw StateError(
        'This device still holds another account\'s data. Export it and use Reset this device below before signing in to a different account. Nothing was uploaded to the new account.',
      );
    }
  });

  Future<void> _resendConfirmation() => _run(() async {
    final email = _email.text.trim();
    if (!email.contains('@')) throw ArgumentError('Enter your email first.');
    await widget.cloud!.client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: AppLinks.confirmation.toString(),
    );
    if (mounted) {
      setState(
        () => _message = 'Confirmation email requested. Open the newest link, then return here and sign in.',
      );
    }
  });

  String _describe(String kind, Map<String, dynamic>? value) {
    if (value == null) return 'Deleted';
    if (kind == 'setting') return 'Timezone: ${value['timezone']}';
    final rule = ActivityRule.fromJson({...value, 'focus_block': false});
    String time(int minute) =>
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final schedules = rule.schedules
        .map(
          (s) =>
              '${s.weekdays.map((d) => days[d - 1]).join(', ')} ${time(s.startMinute)}-${time(s.endMinute)}',
        )
        .join('\n');
    return '${rule.name}\nSources: ${rule.sources.join(', ')}\nDaily budget: ${rule.dailyMinutes == null ? 'None' : '${rule.dailyMinutes} min'}\nSchedules: ${schedules.isEmpty ? 'None' : schedules}';
  }

  Future<void> _review(SharedConflict conflict) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review offline edit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Another device changed this item. Confirmed state is currently in use. Applying your saved edit is an explicit replacement, and can conflict again if another edit arrives.',
              ),
              const SizedBox(height: 20),
              Text('Confirmed', style: Theme.of(context).textTheme.titleMedium),
              SelectableText(
                _describe(conflict.change.kind, conflict.confirmedValue),
              ),
              const SizedBox(height: 20),
              Text(
                'Your saved edit',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SelectableText(
                _describe(conflict.change.kind, conflict.change.value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep confirmed'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use saved edit'),
          ),
        ],
      ),
    );
    if (retry == null || !mounted) return;
    await _run(() async {
      final cloud = widget.cloud!;
      await cloud.resolveConflict(
        conflict.change.mutationId,
        retry: retry,
        baseRevision: conflict.confirmedRevision,
      );
      await widget.controller.reloadSharedState();
      if (retry) cloud.requestSync();
    });
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account and everything synced to it: rules, focus history and usage from every device. It cannot be undone.\n\n'
          'This device is then reset and Grindset closes. Other devices sign out at their next sync but keep what is stored on them until you reset them too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.cloud!.client.rpc<dynamic>('delete_account');
      await widget.resetDevice!();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cloud = widget.cloud;
    final user = cloud?.client.auth.currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account & cloud', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (cloud == null) ...[
          const Text(
            'Sync isn\'t available in this build. Everything still works on this device.',
          ),
        ] else if (user == null) ...[
          const Text(
            'Sign in on each device to share rules, the focus timer and usage between them.',
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
              TextButton(
                onPressed: _busy ? null : _resendConfirmation,
                child: const Text('Resend confirmation email'),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  AppLinks.resetPassword,
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Forgot password?'),
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
                        await widget.controller.reloadSharedState();
                        if (mounted) {
                          setState(
                            () => _message =
                                'Account state and usage synchronized.',
                          );
                        }
                      }),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sync now'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(cloud.client.auth.signOut),
                child: const Text('Sign out'),
              ),
              if (widget.resetDevice != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _busy ? null : _deleteAccount,
                  child: const Text('Delete account'),
                ),
            ],
          ),
          if (cloud.lastSync != null)
            Text(
              'Last successful sync: ${cloud.lastSync!.toLocal()}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
        if (user != null && cloud != null) ...[
          if (cloud.notice?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Text(cloud.notice!),
            TextButton(
              onPressed: _busy ? null : () => _run(cloud.dismissNotice),
              child: const Text('Dismiss'),
            ),
          ],
          if (cloud.conflicts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Saved offline edits (${cloud.conflicts.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final conflict in cloud.conflicts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  conflict.change.kind == 'setting'
                      ? 'Account timezone'
                      : (conflict.change.value?['name'] as String? ??
                            'Deleted rule'),
                ),
                subtitle: const Text(
                  'Confirmed state is in use. Your edit is saved for review.',
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _review(conflict),
                  child: const Text('Review'),
                ),
              ),
          ],
        ],
        if (cloud?.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(
              'Sync problem: ${cloud!.lastError}. Your data is safe on this device.',
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
