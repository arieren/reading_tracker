import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/account_access_service.dart';
import 'package:reading_tracker/services/auth_service.dart';

class _Info extends Fake implements UserInfo {
  _Info(this.providerId, this.uid, this.email);
  @override
  final String providerId;
  @override
  final String uid;
  @override
  final String email;
}

class _Result extends Fake implements UserCredential {}

class _User extends Fake implements User {
  @override
  String get uid => 'library-owner';
  @override
  String? email = 'original@example.invalid';
  @override
  bool emailVerified = true;
  @override
  final List<UserInfo> providerData = [];
  final calls = <String>[];
  String password = 'current-password';
  bool rejectNew = false, rejectRestore = false, lostNewResponse = false;
  String? verificationEmail;
  String? get googleId =>
      providerData.where((p) => p.providerId == 'google.com').firstOrNull?.uid;

  @override
  Future<void> reload() async {
    calls.add('reload');
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    calls.add('reauth:${credential.providerId}');
    if (credential is EmailAuthCredential && credential.password != password) {
      throw FirebaseAuthException(code: 'wrong-password');
    }
    if (credential is OAuthCredential && credential.idToken != googleId) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    return _Result();
  }

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    calls.add('link:${credential.providerId}');
    if (credential is EmailAuthCredential) {
      password = credential.password!;
      providerData.add(_Info('password', email!, email!));
    } else if (credential is OAuthCredential) {
      final id = credential.idToken!;
      if (id == 'new-google' && rejectNew) {
        throw FirebaseAuthException(code: 'credential-already-in-use');
      }
      if (id == 'old-google' && rejectRestore) {
        throw FirebaseAuthException(code: 'network-request-failed');
      }
      if (googleId != null) {
        throw FirebaseAuthException(code: 'provider-already-linked');
      }
      providerData.add(_Info('google.com', id, '$id@example.invalid'));
      if (id == 'new-google' && lostNewResponse) {
        throw FirebaseAuthException(code: 'network-request-failed');
      }
    }
    return _Result();
  }

  @override
  Future<User> unlink(String providerId) async {
    calls.add('unlink:$providerId');
    providerData.removeWhere((p) => p.providerId == providerId);
    return this;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('update-password');
    password = newPassword;
    if (!providerData.any((p) => p.providerId == 'password')) {
      providerData.add(_Info('password', email!, email!));
    }
  }

  @override
  Future<void> verifyBeforeUpdateEmail(
    String newEmail, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    calls.add('verify-email');
    verificationEmail = newEmail;
  }
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  User? currentUser;
}

class _OtherUser extends Fake implements User {
  @override
  String get uid => 'another-owner';
}

GoogleAccountSelection _google(String id) => GoogleAccountSelection(
  id: id,
  email: '$id@example.invalid',
  credential: GoogleAuthProvider.credential(idToken: id),
);

void main() {
  late _User user;
  late _Auth auth;
  late List<GoogleAccountSelection> selections;
  late AccountAccessService service;
  setUp(() {
    user = _User()
      ..providerData.add(
        _Info('google.com', 'old-google', 'original@example.invalid'),
      );
    auth = _Auth(user);
    selections = [_google('old-google'), _google('new-google')];
    service = AccountAccessService(
      auth: auth,
      selectGoogle: () async => selections.removeAt(0),
    );
  });
  void password() =>
      user.providerData.add(_Info('password', user.email!, user.email!));

  test(
    'Google-only users cannot unlink without a working recovery login',
    () async {
      await expectLater(
        service.changeGoogle(password: '', confirm: (_) async => true),
        throwsStateError,
      );
      expect(user.googleId, 'old-google');
      expect(user.calls, isEmpty);
    },
  );
  test(
    'password recovery is linked on the same UID after Google reauthentication',
    () async {
      await service.addPassword('backup-password');
      expect(service.current.hasPassword, isTrue);
      expect(service.current.uid, 'library-owner');
      expect(user.calls.take(2), ['reauth:google.com', 'update-password']);
    },
  );
  test('wrong recovery password leaves Google untouched', () async {
    password();
    await expectLater(
      service.changeGoogle(password: 'wrong', confirm: (_) async => true),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(user.googleId, 'old-google');
    expect(user.calls, ['reauth:password']);
  });
  test(
    'choosing the current Google account again does not unlink it',
    () async {
      password();
      selections = [_google('old-google'), _google('old-google')];
      await expectLater(
        service.changeGoogle(
          password: user.password,
          confirm: (_) async => true,
        ),
        throwsStateError,
      );
      expect(user.googleId, 'old-google');
      expect(user.calls, isNot(contains('unlink:google.com')));
    },
  );
  test(
    'cancelled Google picker does not unlink the current provider',
    () async {
      password();
      service = AccountAccessService(
        auth: auth,
        selectGoogle: () async => throw StateError('Picker cancelled'),
      );
      await expectLater(
        service.changeGoogle(
          password: user.password,
          confirm: (_) async => true,
        ),
        throwsStateError,
      );
      expect(user.googleId, 'old-google');
      expect(user.calls, isNot(contains('unlink:google.com')));
    },
  );
  test('cancelled confirmation never unlinks Google', () async {
    password();
    await service.changeGoogle(
      password: user.password,
      confirm: (_) async => false,
    );
    expect(user.googleId, 'old-google');
    expect(user.calls, isNot(contains('unlink:google.com')));
  });
  test('Google replacement preserves UID and password', () async {
    password();
    await service.changeGoogle(
      password: user.password,
      confirm: (email) async => email == 'new-google@example.invalid',
    );
    expect(service.current.uid, 'library-owner');
    expect(service.current.googleId, 'new-google');
    expect(service.current.hasPassword, isTrue);
    expect(user.password, 'current-password');
  });
  test(
    'credential collision restores original Google without merging accounts',
    () async {
      password();
      user.rejectNew = true;
      await expectLater(
        service.changeGoogle(
          password: user.password,
          confirm: (_) async => true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('restored'),
          ),
        ),
      );
      expect(user.googleId, 'old-google');
      expect(service.current.hasPassword, isTrue);
    },
  );
  test('failed restoration retains a usable password login', () async {
    password();
    user.rejectNew = true;
    user.rejectRestore = true;
    await expectLater(
      service.changeGoogle(password: user.password, confirm: (_) async => true),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('existing password'),
        ),
      ),
    );
    expect(user.googleId, isNull);
    expect(service.current.hasPassword, isTrue);
    expect(user.password, 'current-password');
  });
  test(
    'lost success response is read back without reverting new Google',
    () async {
      password();
      user.lostNewResponse = true;
      await service.changeGoogle(
        password: user.password,
        confirm: (_) async => true,
      );
      expect(user.googleId, 'new-google');
      expect(user.calls.where((call) => call == 'link:google.com').length, 1);
    },
  );
  test(
    'email change is verified first and does not immediately replace email',
    () async {
      password();
      await service.requestEmailChange(' new@example.invalid ', user.password);
      expect(user.email, 'original@example.invalid');
      expect(user.verificationEmail, 'new@example.invalid');
      expect(user.calls, ['reauth:password', 'verify-email']);
    },
  );
  test('password change requires current password', () async {
    password();
    await expectLater(
      service.changePassword('wrong', 'new-password'),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(user.password, 'current-password');
    await service.changePassword('current-password', 'new-password');
    expect(user.password, 'new-password');
  });
  test(
    'session switch during confirmation prevents destructive operations',
    () async {
      password();
      await expectLater(
        service.changeGoogle(
          password: user.password,
          confirm: (_) async {
            auth.currentUser = null;
            return true;
          },
        ),
        throwsStateError,
      );
      expect(user.googleId, 'old-google');
    },
  );
  test('overlapping credential changes are rejected', () async {
    password();
    final confirm = Completer<bool>();
    final ready = Completer<void>();
    final first = service.changeGoogle(
      password: user.password,
      confirm: (_) {
        ready.complete();
        return confirm.future;
      },
    );
    await ready.future;
    await expectLater(
      service.changePassword(user.password, 'another-password'),
      throwsStateError,
    );
    confirm.complete(false);
    await first;
  });
  test(
    'settings cannot act on a different user after the screen was opened',
    () async {
      auth.currentUser = _OtherUser();
      await expectLater(
        service.changePassword('current-password', 'new-password'),
        throwsStateError,
      );
      expect(user.calls, isEmpty);
    },
  );
  test(
    'password-only account can connect Google without changing UID',
    () async {
      user.providerData.clear();
      password();
      selections = [_google('new-google')];
      await service.connectGoogle(
        password: user.password,
        confirm: (_) async => true,
      );
      expect(service.current.uid, 'library-owner');
      expect(service.current.googleId, 'new-google');
      expect(service.current.hasPassword, isTrue);
    },
  );
}
