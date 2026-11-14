import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/screens/main_screen.dart';
import 'package:reading_tracker/screens/browse_screen.dart';
import 'package:reading_tracker/widgets/auth_form.dart';
import 'package:reading_tracker/widgets/reset_draft_on_return.dart';

import 'book_repository_test.dart' show MemoryCloud;

void main() {
  late Directory directory;
  late BookRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('form-navigation-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    repo = BookRepository(
      books: await Hive.openBox<Book>('books'),
      outbox: await Hive.openBox<dynamic>('outbox'),
      cloud: MemoryCloud(),
      currentUid: () => 'alice',
    );
    BookRepository.instance = repo;
  });
  tearDown(() async {
    repo.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('changing tabs clears Browse, Library and search-mode Add text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [draftRouteObserver],
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Unsaved query',
    );
    await tester.tap(find.text('Browse').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Website or reading link'),
      'https://example.com',
    );
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved library filter');
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('Browse').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Title'))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning from a page clears input; closing a dialog does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [draftRouteObserver],
        home: Builder(
          builder: (context) => BrowseScreen(
            onOpen: (_) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      Scaffold(appBar: AppBar(title: const Text('Other page'))),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Website or reading link');
    await tester.enterText(field, 'https://example.com');
    await tester.tap(find.text('Add website'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller!.text,
      'https://example.com',
    );
    await tester.tap(find.byTooltip('Open website'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('login fields clear after visiting password reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [draftRouteObserver],
        home: const AuthForm(mode: AuthFormMode.login),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'person@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'unsaved password',
    );
    final reset = find.text('Forgot Password?');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Email'))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Password'))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
