import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/main.dart';
import 'package:reading_tracker/services/app_update_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'version comparison rejects malformed input and compares numerically',
    () {
      expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.1.4', '1.1.4+15'), isFalse);
      expect(isNewerVersion('invalid', '1.0.0'), isFalse);
      expect(isNewerVersion('1.1.4', '1.2.0'), isFalse);
      expect(isNewerVersion(' 1.2.0 ', '1.1.4'), isTrue);
      expect(isNewerVersion('1.2.0', '1.2.0+16'), isFalse);
    },
  );
  testWidgets('pending update check does not block startup', (tester) async {
    final check = Completer<bool>();
    await tester.pumpWidget(
      MyApp(home: const Text('Library ready'), checkUpdate: () => check.future),
    );
    expect(find.text('Library ready'), findsOneWidget);
    check.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed update check preserves usable app', (tester) async {
    await tester.pumpWidget(
      MyApp(
        home: const Text('Library ready'),
        checkUpdate: () async => throw StateError('offline'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Library ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('required update has no dismiss and survives back navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(home: const Text('Library ready'), checkUpdate: () async => true),
    );
    await tester.pumpAndSettle();
    expect(find.text('A fresh chapter is here'), findsOneWidget);
    expect(find.text('Keep reading'), findsNothing);
    expect(find.text('Library ready'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('A fresh chapter is here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('bootstrap shows recoverable initialization failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      ApplicationBootstrap(
        initialize: () async => throw StateError('unavailable'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to start Reading Tracker.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('late update response preserves the existing screen state', (
    tester,
  ) async {
    final check = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateGate(
          checkUpdate: () => check.future,
          child: const Scaffold(body: TextField()),
        ),
      ),
    );
    // Showing a required update must not dispose an unsaved draft.
    final state = tester.state(find.byType(EditableText));
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    check.complete(true);
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(EditableText, skipOffstage: false)),
      same(state),
    );
    expect(find.text('Unsaved draft', skipOffstage: false), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('store failure stays recoverable and successful retry works', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => UpdateGate(
          checkUpdate: () async => true,
          openStore: () async => ++attempts > 1,
          child: child!,
        ),
        home: const Scaffold(body: Text('Library ready')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Update now'));
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open the store. Please try again later.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Update now'));
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('required update covers a route opened while checking', (
    tester,
  ) async {
    final check = Completer<bool>();
    await tester.pumpWidget(
      MyApp(
        checkUpdate: () => check.future,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Account screen')),
                ),
              ),
              child: const Text('Open account'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();
    expect(find.text('Account screen'), findsOneWidget);
    check.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Account screen'), findsNothing);
    expect(find.text('A fresh chapter is here'), findsOneWidget);
  });
}
