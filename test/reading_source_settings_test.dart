import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/services/reading_link_service.dart';
import 'package:reading_tracker/services/reading_sites.dart';
import 'package:reading_tracker/widgets/reading_source_setting.dart';
import 'package:reading_tracker/screens/book_import_screen.dart';
import 'package:reading_tracker/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('preferred reading site can be changed and survives reopening', (
    tester,
  ) async {
    await ReadingSiteStore().add('My reader', 'https://reader.example/');
    Widget app() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: const ReadingSourceSetting()),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Atsu'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<ReadingSource>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My reader').last);
    await tester.pumpAndSettle();
    expect(
      (await ReadingSourcePreferences().load()).url,
      'https://reader.example/',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('My reader'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'import fits a small dark screen with enlarged text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: readingTheme(Brightness.dark),
          home: const BookImportScreen(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tokyo Ghoul 7');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(find.text('Review matches'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
