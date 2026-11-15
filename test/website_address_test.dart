import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/screens/browse_screen.dart';
import 'package:reading_tracker/services/reading_page.dart';
import 'package:reading_tracker/services/reading_sites.dart';
import 'package:reading_tracker/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('browser-style domains become HTTPS while other schemes and notes stay invalid', () {
    expect(normalizeWebAddress(' reader.example '), 'https://reader.example');
    expect(
      normalizeWebAddress('books.example/title/book?x=1#chapter'),
      'https://books.example/title/book?x=1#chapter',
    );
    expect(
      normalizeWebAddress('reader.example:8443/path'),
      'https://reader.example:8443/path',
    );
    expect(
      normalizeWebAddress('//reader.example/book'),
      'https://reader.example/book',
    );
    expect(
      normalizeWebAddress('http://localhost:8080/book'),
      'http://localhost:8080/book',
    );
    expect(
      normalizeWebAddress('reader.example/my book'),
      'https://reader.example/my%20book',
    );
    for (final value in [
      'javascript:alert(1)',
      'file:///private',
      'mailto:user@example.com',
      'user:password@example.com',
      'not a website',
      'reading notes',
    ]) {
      expect(isReadingUrl(normalizeWebAddress(value)), isFalse, reason: value);
    }
  });
  test('website store normalizes domains and detects duplicates', () async {
    final store = ReadingSiteStore();
    await store.add('My books', 'books.example');
    expect((await store.load()).last.url, 'https://books.example');
    await expectLater(
      store.add('Again', 'https://books.example/'),
      throwsFormatException,
    );
  });
  testWidgets(
    'Add website size stays stable while typing and showing an error',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: readingTheme(Brightness.light),
          home: const BrowseScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add website'));
      await tester.pumpAndSettle();
      final emptySize = tester.getSize(find.byType(AlertDialog));
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My books',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Website address'),
        'not a website',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AlertDialog)), emptySize);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a valid website'), findsOneWidget);
      expect(tester.getSize(find.byType(AlertDialog)), emptySize);
      await tester.enterText(
        find.widgetWithText(TextField, 'Website address'),
        'books.example',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await ReadingSiteStore().load()).last.url,
        'https://books.example',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Browse opens a bare domain as an HTTPS website', (tester) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScreen(
          onOpen: (url) async {
            opened = url;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Website or reading link'),
      'reader.example',
    );
    await tester.tap(find.byTooltip('Open website'));
    await tester.pumpAndSettle();
    expect(opened, 'https://reader.example');
    expect(tester.takeException(), isNull);
  });
}
