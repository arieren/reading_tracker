import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/screens/account_access_screen.dart';
import 'package:reading_tracker/widgets/session_gate.dart';
import 'package:reading_tracker/services/account_access_service.dart';
import 'package:reading_tracker/services/auth_service.dart';

// Fictional OIDC identities accepted only by the local Auth emulator.
GoogleAccountSelection selection(String id) => GoogleAccountSelection(
  id: id,
  email: '$id@example.invalid',
  credential: GoogleAuthProvider.credential(
    idToken: jsonEncode({
      'sub': id,
      'email': '$id@example.invalid',
      'email_verified': true,
    }),
  ),
);

Future<void> verifyEmail(FirebaseAuth auth, String email) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'http://10.0.2.2:9095/emulator/v1/projects/demo-reading-tracker/oobCodes',
      ),
    );
    final response = await request.close();
    final payload = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    final codes = (payload['oobCodes'] as List).cast<Map>();
    final code =
        codes.lastWhere((item) => item['newEmail'] == email)['oobCode']
            as String;
    await auth.applyActionCode(code);
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'account changes retain UID and migrated library in native Firebase',
    (tester) async {
      expect(
        const bool.fromEnvironment('RUN_ACCOUNT_ACCESS_EMULATOR_TEST'),
        isTrue,
      );
      final app = await Firebase.initializeApp(
        name: 'account-access-emulator',
        options: const FirebaseOptions(
          apiKey: 'local-emulator-only',
          appId: '1:1234567890:android:0123456789',
          messagingSenderId: '1234567890',
          projectId: 'demo-reading-tracker',
        ),
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      final db = FirebaseFirestore.instanceFor(app: app);
      await auth.useAuthEmulator('10.0.2.2', 9095);
      db.useFirestoreEmulator('10.0.2.2', 8085);
      Future<void> library(String uid) async {
        expect(auth.currentUser?.uid, uid);
        final data =
            (await db
                    .doc('users/$uid/books/access-fixture')
                    .get(const GetOptions(source: Source.server)))
                .data()!;
        expect(data['uid'], uid);
        expect(data['chapter'], 12);
        expect(data['title'], 'Account access fixture');
      }

      try {
        const googleUid = 'account-access-google';
        final old = selection('old-google');
        final replacement = selection('new-google');
        await auth.signInWithCredential(old.credential);
        final picks = <GoogleAccountSelection>[];
        final service = AccountAccessService(
          auth: auth,
          selectGoogle: () async => picks.removeAt(0),
        );
        await library(googleUid);
        picks.add(old);
        await service.addPassword('Recovery-password-12345');
        expect((await service.refresh()).hasPassword, isTrue);
        picks.addAll([old, replacement]);
        await service.changeGoogle(
          password: 'Recovery-password-12345',
          confirm: (_) async => true,
        );
        expect((await service.refresh()).googleId, replacement.id);
        await library(googleUid);

        // Another Firebase account already owns this Google identity.
        picks.addAll([replacement, selection('taken-google')]);
        await expectLater(
          service.changeGoogle(
            password: 'Recovery-password-12345',
            confirm: (_) async => true,
          ),
          throwsA(isA<StateError>()),
        );
        expect((await service.refresh()).googleId, replacement.id);
        await library(googleUid);
        final recoveryEmail = service.current.email;
        await auth.signOut();
        await auth.signInWithEmailAndPassword(
          email: recoveryEmail,
          password: 'Recovery-password-12345',
        );
        await library(googleUid);
        await auth.signOut();
        await auth.signInWithCredential(replacement.credential);
        await library(googleUid);

        // Simulate process loss after unlink: password recovery still reaches the
        // same library, and Connect Google can finish without a new Firebase user.
        await auth.currentUser!.unlink('google.com');
        await auth.signOut();
        await auth.signInWithEmailAndPassword(
          email: recoveryEmail,
          password: 'Recovery-password-12345',
        );
        expect((await service.refresh()).hasGoogle, isFalse);
        picks.add(replacement);
        await service.connectGoogle(
          password: 'Recovery-password-12345',
          confirm: (_) async => true,
        );
        await library(googleUid);

        // Reproduce a password email changed while the original Google identity
        // remains linked, then replace Google from the password-authenticated
        // session. Reauthenticating through its old email is unnecessary.
        await service.requestEmailChange(
          'final-google@example.invalid',
          'Recovery-password-12345',
        );
        await verifyEmail(auth, 'final-google@example.invalid');
        await auth.signOut();
        await auth.signInWithEmailAndPassword(
          email: 'final-google@example.invalid',
          password: 'Recovery-password-12345',
        );
        expect((await service.refresh()).googleEmail, replacement.email);
        final finalGoogle = selection('final-google');
        picks.addAll([replacement, finalGoogle]);
        await service.changeGoogle(
          password: 'Recovery-password-12345',
          confirm: (_) async => true,
        );
        expect((await service.refresh()).googleId, finalGoogle.id);
        await library(googleUid);

        await auth.signOut();
        const passwordUid = 'account-access-password';
        await auth.signInWithEmailAndPassword(
          email: 'password-login@example.invalid',
          password: 'Original-password-12345',
        );
        await library(passwordUid);
        final passwordService = AccountAccessService(auth: auth);
        await passwordService.changePassword(
          'Original-password-12345',
          'Changed-password-12345',
        );
        await passwordService.requestEmailChange(
          'changed-login@example.invalid',
          'Changed-password-12345',
        );
        expect(auth.currentUser!.email, 'password-login@example.invalid');
        await tester.pumpWidget(
          MaterialApp(
            home: SessionGate(
              changes: auth.userChanges(),
              initialUser: auth.currentUser,
              signedIn: (_) => Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AccountAccessScreen(service: passwordService),
                      ),
                    ),
                    child: const Text('Open sign-in settings'),
                  ),
                ),
              ),
              signedOut: (_) =>
                  const Scaffold(body: Text('Sign-in recovery page')),
            ),
          ),
        );
        await tester.tap(find.text('Open sign-in settings'));
        await tester.pumpAndSettle();
        await verifyEmail(auth, 'changed-login@example.invalid');
        // Local Auth may retain its token longer than production after the
        // action code. Explicitly end it with the settings route still open.
        await auth.signOut();
        await tester.pumpAndSettle();
        expect(find.text('Sign-in recovery page'), findsOneWidget);
        expect(find.text('Sign-in & security'), findsNothing);
        expect(tester.takeException(), isNull);
        await auth.signInWithEmailAndPassword(
          email: 'changed-login@example.invalid',
          password: 'Changed-password-12345',
        );
        expect(auth.currentUser!.emailVerified, isTrue);
        await library(passwordUid);
        await auth.signOut();
        await expectLater(
          auth.signInWithEmailAndPassword(
            email: 'password-login@example.invalid',
            password: 'Original-password-12345',
          ),
          throwsA(isA<FirebaseAuthException>()),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await auth.signOut();
        await db.terminate();
        await app.delete();
      }
    },
  );
}
