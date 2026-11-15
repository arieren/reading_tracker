import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/screens/account_access_screen.dart';
import 'package:reading_tracker/services/account_access_service.dart';
import 'package:reading_tracker/widgets/credential_form.dart';
import 'package:reading_tracker/widgets/reset_draft_on_return.dart';
import 'package:reading_tracker/widgets/account_identity_summary.dart';

class _Service extends Fake implements AccountAccessService {
  _Service({bool password = false})
    : account = AccountAccess(
        uid: 'owner',
        email: 'reader@example.invalid',
        emailVerified: true,
        hasPassword: password,
        googleId: 'google-id',
        googleEmail: 'reader@example.invalid',
      );
  AccountAccess account;
  int added = 0, switched = 0, requested = 0;
  bool expired = false, offline = false;
  @override
  AccountAccess get current {
    if (expired) throw AccountSessionExpired();
    return account;
  }

  @override
  Future<AccountAccess> refresh() async {
    if (expired) throw AccountSessionExpired();
    if (offline) throw FirebaseAuthException(code: 'network-request-failed');
    return account;
  }

  @override
  Future<void> leaveExpiredSession() async {}
  @override
  Future<void> addPassword(String password) async {
    added++;
    account = AccountAccess(
      uid: account.uid,
      email: account.email,
      emailVerified: true,
      hasPassword: true,
      googleId: account.googleId,
      googleEmail: account.googleEmail,
    );
  }

  @override
  Future<void> changeGoogle({
    required String password,
    required Future<bool> Function(String email) confirm,
  }) async {
    if (await confirm('preferred@example.invalid')) switched++;
  }

  @override
  Future<void> requestEmailChange(String email, String password) async {
    requested++;
  }
}

void main() {
  Future<void> open(WidgetTester tester, _Service service) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [draftRouteObserver],
        home: AccountAccessScreen(service: service),
      ),
    );
  }

  Future<void> reveal(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
    scrollable: find.byType(Scrollable).first,
      );
  testWidgets(
    'Google switching stays disabled until password recovery is configured',
    (tester) async {
      final service = _Service();
      await open(tester, service);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Change Google account'),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Set up password recovery'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(service.added, 0);
      expect(find.text('Use at least six characters.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'backup-password',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'backup-password',
      );
      await reveal(tester, find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(service.added, 1);
      await reveal(tester, find.text('Change Google account'));
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Change Google account'),
            )
            .enabled,
        isTrue,
      );
    },
  );
  testWidgets(
    'Google replacement confirmation can cancel without changing login',
    (tester) async {
      final service = _Service(password: true);
      await open(tester, service);
      await reveal(tester, find.text('Change Google account'));
      await tester.tap(find.text('Change Google account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'),
        'backup-password',
      );
      await reveal(tester, find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('preferred@example.invalid'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.switched, 0);
      expect(find.text('Sign-in & security'), findsOneWidget);
    },
  );
  testWidgets('email change requires a different valid address', (
    tester,
  ) async {
    final service = _Service(password: true);
    await open(tester, service);
    await reveal(tester, find.text('Change password-login email'));
    await tester.tap(find.text('Change password-login email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New email'),
      'reader@example.invalid',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'backup-password',
    );
    await reveal(tester, find.text('Send verification link'));
    await tester.tap(find.text('Send verification link'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a different email address.'), findsOneWidget);
    expect(service.requested, 0);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New email'),
      'personal@example.invalid',
    );
    await reveal(tester, find.text('Send verification link'));
    await tester.tap(find.text('Send verification link'));
    await tester.pumpAndSettle();
    expect(service.requested, 1);
    expect(
      find.textContaining('Check personal@example.invalid'),
      findsOneWidget,
    );
  });
  testWidgets('cancelling and reopening a credential form clears passwords', (
    tester,
  ) async {
    final service = _Service(password: true);
    await open(tester, service);
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'private-draft',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Current password'),
    );
    expect(field.controller!.text, isEmpty);
    expect(find.byType(CredentialForm), findsOneWidget);
  });
  testWidgets(
    'settings opened after session expiration show recovery instead of crashing',
    (tester) async {
      final service = _Service()..expired = true;
      await open(tester, service);
      expect(find.text('Return to sign-in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('verification refresh with an expired session shows recovery', (
    tester,
  ) async {
    final service = _Service(password: true);
    await open(tester, service);
    service.expired = true;
    await reveal(tester, find.text('Refresh sign-in details'));
    await tester.tap(find.text('Refresh sign-in details'));
    await tester.pumpAndSettle();
    expect(find.text('Return to sign-in'), findsOneWidget);
    expect(find.text('Change password'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'offline refresh keeps settings available without expiring the session',
    (tester) async {
      final service = _Service(password: true)..offline = true;
      await open(tester, service);
      await reveal(tester, find.text('Refresh sign-in details'));
      await tester.tap(find.text('Refresh sign-in details'));
      await tester.pumpAndSettle();
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Return to sign-in'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'profile distinguishes password email from the linked Google identity',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountIdentitySummary(
              account: AccountAccess(
                uid: 'owner',
                email: 'new@example.invalid',
                emailVerified: true,
                hasPassword: true,
                googleId: 'google',
                googleEmail: 'old@example.invalid',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Email & password sign-in'), findsOneWidget);
      expect(find.text('new@example.invalid'), findsOneWidget);
      expect(find.text('Google sign-in'), findsOneWidget);
      expect(find.text('old@example.invalid'), findsOneWidget);
    },
  );
}
