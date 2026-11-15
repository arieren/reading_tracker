import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../services/account_access_service.dart';
import '../services/auth_service.dart';
import '../widgets/credential_form.dart';

class AccountAccessScreen extends StatefulWidget {
  const AccountAccessScreen({super.key, this.service});
  final AccountAccessService? service;

  @override
  State<AccountAccessScreen> createState() => _AccountAccessScreenState();
}

class _AccountAccessScreenState extends State<AccountAccessScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? AccountAccessService();
  late AccountAccess _account;
  bool _busy = false;
  String? _message;
  bool _error = false;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    try {
      _account = _service.current;
    } on AccountSessionExpired {
      _sessionExpired = true;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && !_sessionExpired) {
      _refresh();
    }
  }

  Future<void> _refresh() => _run(() async => 'Sign-in details refreshed.');

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      // Reload after a mutation, including a provider change on this same UID.
      _account = await _service.refresh();
      if (mounted) {
        setState(() {
          _message = message;
          _error = false;
        });
      }
    } on Object catch (error) {
      if (error is AccountSessionExpired) {
        if (mounted) setState(() => _sessionExpired = true);
        return;
      }
      // A failed replacement may still have left a valid recovery login. Show
      // actual provider state without hiding the original error if reload fails.
      try {
        _account = await _service.refresh();
      } on AccountSessionExpired {
        if (mounted) setState(() => _sessionExpired = true);
        return;
      } on Object {
        /* Offline. */
      }
      if (mounted) {
        setState(() {
          _message = authenticationError(error);
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _returnToSignIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.leaveExpiredSession();
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Unable to finish signing out. Please try again.';
        });
      }
    }
  }

  Future<bool> _confirmGoogle(String email) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connect this Google account?'),
            content: Text(
              'Use $email for Google sign-in?\n\nYour library stays on this Reading Tracker account. Your account email may change to the Google address; your recovery password stays the same. An account already used by another Reading Tracker user cannot be connected here.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Connect'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _edit(CredentialAction action) async {
    if (_busy) return;
    final input = await Navigator.push<CredentialInput>(
      context,
      MaterialPageRoute(
        builder: (_) => CredentialForm(
          action: action,
          email: _account.email,
          googleEmail: _account.googleEmail,
        ),
      ),
    );
    if (!mounted || input == null) return;
    await _run(() async {
      switch (action) {
        case CredentialAction.addPassword:
          await _service.addPassword(input.newPassword);
          return 'Password login is ready. You can now use it as recovery or change your Google account.';
        case CredentialAction.changePassword:
          await _service.changePassword(input.password, input.newPassword);
          return 'Your Reading Tracker password was changed.';
        case CredentialAction.changeEmail:
          await _service.requestEmailChange(input.email, input.password);
          return 'Check ${input.email} for the verification link. After verifying, refresh here or sign in with the new email if asked.';
        case CredentialAction.google:
          if (_account.hasGoogle) {
            await _service.changeGoogle(
              password: input.password,
              confirm: _confirmGoogle,
            );
          } else {
            await _service.connectGoogle(
              password: input.password,
              confirm: _confirmGoogle,
            );
          }
          return 'Google sign-in settings refreshed. Your library stays on the same account.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionExpired) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sign in again')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_reset_rounded, size: 48),
                  const SizedBox(height: 20),
                  const Text(
                    'Your sign-in needs to be refreshed. If you verified a new email, use that address with your existing Reading Tracker password. Your library is still saved.',
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _returnToSignIn,
                    child: const Text('Return to sign-in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final googleSupported =
        kIsWeb ||
        [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Sign-in & security')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                const Icon(Icons.manage_accounts_outlined, size: 40),
                const SizedBox(height: 16),
                Text(
                  _account.email,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage how you sign in. Changing your login keeps your library, progress and offline books on this account.',
                ),
                const SizedBox(height: 24),
                if (_message != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _error ? colors.error : colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.password_rounded),
                        title: Text(
                          _account.hasPassword
                              ? 'Change password'
                              : 'Set up password recovery',
                        ),
                        subtitle: Text(
                          _account.hasPassword
                              ? 'Email login: ${_account.email}'
                              : 'Required before changing your Google account',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: !_busy,
                        onTap: () => _edit(
                          _account.hasPassword
                              ? CredentialAction.changePassword
                              : CredentialAction.addPassword,
                        ),
                      ),
                      if (_account.hasPassword)
                        ListTile(
                          leading: const Icon(Icons.alternate_email_rounded),
                          title: const Text('Change password-login email'),
                          subtitle: Text(
                            _account.hasGoogle
                                ? 'Changes email/password login. Your linked Google account is managed separately below.'
                                : 'Verify the new address before it changes',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: !_busy,
                          onTap: () => _edit(CredentialAction.changeEmail),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(
                      _account.hasGoogle
                          ? 'Change Google account'
                          : 'Connect Google',
                    ),
                    subtitle: Text(
                      _account.hasGoogle
                          ? 'Connected: ${_account.googleEmail ?? _account.email}'
                          : 'Sign in with Google to this same library',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_busy && googleSupported && _account.hasPassword,
                    onTap: () => _edit(CredentialAction.google),
                  ),
                ),
                if (!googleSupported)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Manage Google sign-in from Android, iOS, macOS or the web app.',
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh sign-in details'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
