import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/main.dart';
import 'package:reading_tracker/theme/app_theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('required update displays in both themes on Android', (
    tester,
  ) async {
    expect(appFlavor, 'staging');
    await binding.convertFlutterSurfaceToImage();
    for (final brightness in Brightness.values) {
      var launches = 0;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(brightness),
          theme: readingTheme(brightness),
          builder: (_, child) => UpdateGate(
            checkUpdate: () async => true,
            openStore: () async {
              launches++;
              return true;
            },
            child: child!,
          ),
          home: const Scaffold(body: Text('Library underneath')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Library underneath'), findsNothing);
      expect(find.text('Keep reading'), findsNothing);
      await tester.ensureVisible(find.text('Update now'));
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.text('A fresh chapter is here'), findsOneWidget);
      final name = 'app-update-${brightness.name}';
      await binding.takeScreenshot(name);
    }
  });
}
