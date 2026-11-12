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
    },
  );
  testWidgets('optional update check does not block startup', (tester) async {
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
  testWidgets('Update Later restores content without invalid navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(home: const Text('Library ready'), checkUpdate: () async => true),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Update Available!'), findsOneWidget);
    await tester.tap(find.text('Update Later'));
    await tester.pumpAndSettle();
    expect(find.text('Library ready'), findsOneWidget);
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
}
