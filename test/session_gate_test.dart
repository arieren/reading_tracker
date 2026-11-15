import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/widgets/session_gate.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  bool get emailVerified => true;
}

void main() {
  late StreamController<User?> users;
  setUp(() => users = StreamController<User?>());
  tearDown(() => users.close());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          changes: users.stream,
          initialUser: _User('owner'),
          signedIn: (user) => Scaffold(
            body: Column(
              children: [
                Text('Library ${user.uid}'),
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PopScope(
                          canPop: false,
                          child: const Scaffold(
                            body: Text('Sensitive settings'),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open settings'),
                  ),
                ),
              ],
            ),
          ),
          signedOut: (notice) => Scaffold(
            body: Column(
              children: [
                const Text('Sign-in page'),
                if (notice != null) Text(notice),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'expired session removes pushed routes even when back is blocked',
    (tester) async {
      await open(tester);
      users.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Sensitive settings'), findsNothing);
      expect(find.text('Sign-in page'), findsOneWidget);
      expect(find.textContaining('verified a new email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('profile update on the same UID preserves the current route', (
    tester,
  ) async {
    await open(tester);
    users.add(_User('owner'));
    await tester.pumpAndSettle();
    expect(find.text('Sensitive settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('different UID removes previous account settings', (
    tester,
  ) async {
    await open(tester);
    users.add(_User('other'));
    await tester.pumpAndSettle();
    expect(find.text('Sensitive settings'), findsNothing);
    expect(find.text('Library other'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
