import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'account_deletion_service.dart';

import 'package:google_sign_in/google_sign_in.dart';

class GoogleAccountSelection {
  const GoogleAccountSelection({
    required this.id,
    required this.email,
    required this.credential,
  });
  final String id;
  final String email;
  final OAuthCredential credential;
}

class AuthService {
  static Future<void>? _googleInitialization;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  Future<GoogleAccountSelection> selectGoogleAccount({
    bool chooseAccount = false,
  }) async {
    try {
      await (_googleInitialization ??= GoogleSignIn.instance.initialize());
    } on Object catch (_) {
      _googleInitialization = null;
      rethrow;
    }
    // This clears Google's picker selection, not the Firebase app session.
    if (chooseAccount) await GoogleSignIn.instance.signOut();
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw StateError(
        'Google could not verify this account. Please try again.',
      );
    }
    return GoogleAccountSelection(
      id: account.id,
      email: account.email,
      credential: GoogleAuthProvider.credential(idToken: token),
    );
  }

  Future<OAuthCredential> _googleCredential() async =>
      (await selectGoogleAccount()).credential;

  Future<void> signInGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    if (![
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform)) {
      throw StateError('Use email and password to sign in on this platform.');
    }
    await _auth.signInWithCredential(await _googleCredential());
  }

  Future<void> signInEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await result.user!.reload();
    final user = _auth.currentUser!;
    if (!user.emailVerified) {
      try {
        await user.sendEmailVerification();
      } finally {
        await _auth.signOut();
      }
      throw StateError(
        'Verify your email before signing in. A verification email has been sent.',
      );
    }
  }

  Future<void> signUp(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    try {
      await result.user!.sendEmailVerification();
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleInitialization != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } on Object catch (_) {}
    }
  }

  Future<void> requestAccountDeletion() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    await user.getIdToken(true);
    await AccountDeletionService().delete(
      user.uid,
      deleteIdentity: () async {
        try {
          await user.delete();
        } on FirebaseAuthException catch (error) {
          if (error.code != 'user-not-found') rethrow;
        }
      },
    );
  }

  Future<void> reauthenticate({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    if (kIsWeb && user.providerData.any((p) => p.providerId == 'google.com')) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }
    final credential =
        user.providerData.any((p) => p.providerId == 'google.com')
        ? await _googleCredential()
        : EmailAuthProvider.credential(
            email: user.email!,
            password: password ?? '',
          );
    await user.reauthenticateWithCredential(credential);
  }
}

String authenticationError(Object error) {
  if (error is GoogleSignInException) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return 'Google sign-in was cancelled or could not complete. Please try again.';
    }
    return 'Google sign-in could not complete. Check your connection and try again.';
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email or password is incorrect.',
      'email-already-in-use' => 'An account already uses that email address.',
      'weak-password' =>
        'Choose a stronger password (at least six characters).',
      'too-many-requests' =>
        'Too many attempts. Please wait before trying again.',
      'network-request-failed' =>
        'Unable to connect. Please check your connection.',
      'requires-recent-login' =>
        'Please verify your current sign-in before changing your account.',
      'credential-already-in-use' ||
      'account-exists-with-different-credential' => 'That sign-in belongs to another Reading Tracker account. No libraries were merged.',
      'user-mismatch' =>
        'Choose the Google account currently linked to this account.',
      'invalid-email' => 'Enter a valid email address.',
      'provider-already-linked' => 'This sign-in method is already connected.',
      'user-token-expired' || 'invalid-user-token' => 'Please sign in again. If you verified a new email, use the new address with your existing password.',
      'popup-closed-by-user' ||
      'cancelled-popup-request' => 'Google sign-in was cancelled.',
      'popup-blocked' => 'Allow the Google sign-in popup and try again.',
      'operation-not-allowed' =>
        'This sign-in change is unavailable. Please try again later.',
      _ => 'Unable to complete this request. Please try again.',
    };
  }
  return error is StateError
      ? error.message.toString()
      : 'Unable to complete this request. Please try again.';
}
