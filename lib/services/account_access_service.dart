import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

class AccountSessionExpired extends StateError {
  AccountSessionExpired()
    : super(
        'Please sign in again. If you verified a new email, use the new address with your existing password.',
      );
}

class AccountAccess {
  const AccountAccess({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.hasPassword,
    this.googleId,
    this.googleEmail,
  });
  final String uid;
  final String email;
  final bool emailVerified;
  final bool hasPassword;
  final String? googleId;
  final String? googleEmail;
  bool get hasGoogle => googleId != null;

  factory AccountAccess.fromUser(User user) {
    final google = user.providerData.where((p) => p.providerId == 'google.com');
    return AccountAccess(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
      hasPassword: user.providerData.any((p) => p.providerId == 'password'),
      googleId: google.isEmpty ? null : google.first.uid,
      googleEmail: google.isEmpty ? null : google.first.email,
    );
  }
}

/// Changes authentication on the existing UID only. Never creates, signs into,
/// or merges another Firebase account, and never rewrites library ownership.
class AccountAccessService {
  AccountAccessService({
    FirebaseAuth? auth,
    Future<GoogleAccountSelection> Function()? selectGoogle,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _selectGoogle =
           selectGoogle ??
           (() => AuthService().selectGoogleAccount(chooseAccount: true)) {
    _ownerUid = _auth.currentUser?.uid;
  }

  final FirebaseAuth _auth;
  final Future<GoogleAccountSelection> Function() _selectGoogle;
  late final String? _ownerUid;
  bool _busy = false;

  AccountAccess get current => AccountAccess.fromUser(_user());
  User _user([String? uid]) {
    final user = _auth.currentUser;
    if (user == null || user.uid != (uid ?? _ownerUid)) {
      throw AccountSessionExpired();
    }
    return user;
  }

  Future<T> _change<T>(Future<T> Function(User) action) async {
    if (_busy) throw StateError('Another sign-in change is still running.');
    _busy = true;
    try {
      return await action(_user());
    } finally {
      _busy = false;
    }
  }

  Future<AccountAccess> refresh() async {
    final user = _user();
    try {
      await user.reload();
    } on FirebaseAuthException catch (error) {
      if ([
        'user-token-expired',
        'invalid-user-token',
        'user-disabled',
        'user-not-found',
      ].contains(error.code)) {
        throw AccountSessionExpired();
      }
      rethrow;
    }
    return AccountAccess.fromUser(_user(user.uid));
  }

  Future<void> leaveExpiredSession() async {
    // Do not sign out a different account that took over this app session.
    if (_auth.currentUser?.uid == _ownerUid) await _auth.signOut();
  }

  Future<void> _passwordCheck(User user, String password) async {
    if (!AccountAccess.fromUser(user).hasPassword || password.isEmpty) {
      throw StateError('Enter your current email sign-in password.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    _user(user.uid);
  }

  GoogleAuthProvider _googleProvider() =>
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});

  Future<OAuthCredential?> _googleCheck(User user) async {
    if (kIsWeb) {
      final result = await user.reauthenticateWithPopup(_googleProvider());
      _user(user.uid);
      return result.credential is OAuthCredential
          ? result.credential as OAuthCredential
          : null;
    }
    final selection = await _selectGoogle();
    _user(user.uid);
    await user.reauthenticateWithCredential(selection.credential);
    _user(user.uid);
    return selection.credential;
  }

  Future<void> addPassword(String password) => _change((user) async {
    final account = AccountAccess.fromUser(user);
    if (account.hasPassword) {
      throw StateError('A password is already configured.');
    }
    if (!account.hasGoogle || !account.emailVerified || account.email.isEmpty) {
      throw StateError('Verify your current email before adding a password.');
    }
    await _googleCheck(user);
    // Setting a password on this verified, recently authenticated user enables
    // email/password access without changing the account's existing email.
    await _user(user.uid).updatePassword(password);
    await _user(user.uid).reload();
    _user(user.uid);
  });

  Future<void> changePassword(String currentPassword, String newPassword) =>
      _change((user) async {
        await _passwordCheck(user, currentPassword);
        await _user(user.uid).updatePassword(newPassword);
        _user(user.uid);
      });

  Future<void> requestEmailChange(String newEmail, String password) =>
      _change((user) async {
        final email = newEmail.trim();
        if (email.toLowerCase() == user.email?.toLowerCase()) {
          throw StateError('Enter a different email address.');
        }
        await _passwordCheck(user, password);
        // Firebase changes the address only after the new inbox is verified.
        await _user(user.uid).verifyBeforeUpdateEmail(email);
        _user(user.uid);
      });

  Future<void> connectGoogle({
    required String password,
    required Future<bool> Function(String email) confirm,
  }) => _change((user) async {
    if (AccountAccess.fromUser(user).hasGoogle) {
      throw StateError(
        'Use Change Google account for an existing Google login.',
      );
    }
    await _passwordCheck(user, password);
    if (kIsWeb) {
      if (!await confirm('the Google account you select')) return;
      await _user(user.uid).linkWithPopup(_googleProvider());
    } else {
      final selection = await _selectGoogle();
      _user(user.uid);
      if (!await confirm(selection.email)) return;
      await _user(user.uid).linkWithCredential(selection.credential);
    }
    await _user(user.uid).reload();
    _user(user.uid);
  });

  Future<void> changeGoogle({
    required String password,
    required Future<bool> Function(String email) confirm,
  }) => _change((user) async {
    final account = AccountAccess.fromUser(user);
    if (!account.hasGoogle || !account.hasPassword || !account.emailVerified) {
      throw StateError(
        'Set up an email/password recovery login before switching Google accounts.',
      );
    }
    // Prove the recovery password works before touching the Google provider.
    await _passwordCheck(user, password);
    OAuthCredential? oldCredential;
    GoogleAccountSelection? selection;
    if (!kIsWeb) {
      // The recovery password already reauthenticated this Firebase user.
      // Reauthenticating again through the old Google email can fail after the
      // password-login email changed. Capture its matching credential for
      // rollback without replacing the freshly verified Firebase session.
      final original = await _selectGoogle();
      _user(user.uid);
      if (original.id != account.googleId) {
        throw FirebaseAuthException(code: 'user-mismatch');
      }
      oldCredential = original.credential;
      selection = await _selectGoogle();
      _user(user.uid);
      if (selection.id == account.googleId) {
        throw StateError(
          'That is your current Google account. Choose a different one.',
        );
      }
    }
    if (!await confirm(selection?.email ?? 'the Google account you select')) {
      return;
    }
    final before = AccountAccess.fromUser(_user(user.uid));
    if (!before.hasPassword || before.googleId != account.googleId) {
      throw StateError(
        'Your sign-in methods changed. Refresh settings and try again.',
      );
    }
    await _user(user.uid).unlink('google.com');
    try {
      if (kIsWeb) {
        await _user(user.uid).linkWithPopup(_googleProvider());
      } else {
        await _user(user.uid).linkWithCredential(selection!.credential);
      }
      await _user(user.uid).reload();
      _user(user.uid);
    } on Object catch (error) {
      // A request can succeed on the server even if its response is lost.
      // Read back first; never remove a provider as a speculative rollback.
      try {
        await _user(user.uid).reload();
        final now = AccountAccess.fromUser(_user(user.uid));
        if (selection != null && now.googleId == selection.id) return;
        if (now.googleId == account.googleId) rethrow;
        if (!now.hasGoogle && oldCredential != null) {
          await _user(user.uid).linkWithCredential(oldCredential);
          throw StateError(
            '${authenticationError(error)} Your original Google login was restored.',
          );
        }
      } on StateError {
        rethrow;
      } on Object {
        /* Recovery password remains linked if restoration fails. */
      }
      throw StateError(
        '${authenticationError(error)} If Google is unavailable, use your existing password with your account email. Refresh these settings before retrying. Your library has not been moved.',
      );
    }
  });
}
