import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/screens/add_book_screen.dart';
import 'package:reading_tracker/services/auth_service.dart';
import 'package:reading_tracker/widgets/auth_form.dart';
import 'package:reading_tracker/widgets/book_cover.dart';
import 'package:reading_tracker/widgets/book_editor.dart';
import 'package:reading_tracker/screens/reader_screen.dart';

import 'book_repository_test.dart' show MemoryCloud;

class FakeAuthentication extends AuthService {
  int calls = 0;
  String? email, password;
  final completion = Completer<void>();
  @override
  Future<void> signInEmail(String email, String password) async {
    calls++;
    this.email = email;
    this.password = password;
    await completion.future;
  }
}

void main() {
  late Directory directory;
  late Box<Book> books;
  late BookRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reading_tracker_form_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    books = await Hive.openBox<Book>('form_books');
    final outbox = await Hive.openBox<dynamic>('form_outbox');
    repository = BookRepository(
      books: books,
      outbox: outbox,
      cloud: MemoryCloud()..offline = true,
      currentUid: () => 'alice',
    );
  });
  tearDown(() async {
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  testWidgets('editor saves progress without trimming saved non-URL text', (
    tester,
  ) async {
    const savedText = '  number notes  ';
    final book = Book(
      uid: 'alice',
      id: 'legacy-text',
      title: 'Story',
      type: 'Manga',
      chapter: 1,
      linkURL: savedText,
    );
    await tester.runAsync(() => books.add(book));
    BookRepository.instance = repository;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showBookEditor(context, book),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved text will be kept'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Chapter'), '9');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      for (
        var attempt = 0;
        attempt < 100 && repository.userBooks.single.chapter != 9;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(repository.userBooks.single.chapter, 9);
    expect(repository.userBooks.single.linkURL, savedText);
    expect(find.text('Edit book'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('saved text is never opened as a reader URL', (tester) async {
    final book = Book(
      title: 'Story',
      type: 'Manga',
      chapter: 1,
      linkURL: 'number notes',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => openBookReader(context, book),
              child: const Text('Read'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Read'));
    await tester.pump();
    expect(find.text('Add a valid reading link first.'), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);
    expect(book.linkURL, 'number notes');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'login preserves password bytes and prevents overlapping submissions',
    (tester) async {
      final auth = FakeAuthentication();
      await tester.pumpWidget(
        MaterialApp(
          home: AuthForm(mode: AuthFormMode.login, auth: auth),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'reader@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        ' password with spaces ',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pump();
      expect(auth.calls, 1);
      expect(auth.password, ' password with spaces ');
      expect(find.text('Please wait...'), findsOneWidget);
      auth.completion.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manual entry without an image uses the book placeholder and saves',
    (tester) async {
      var added = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AddBookScreen(
            repository: repository,
            currentUid: () => 'alice',
            onBookAdded: () => added++,
          ),
        ),
      );
      await tester.tap(find.text('Manual Entry'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'No cover story',
      );
      final cover = tester.widget<BookCover>(find.byType(BookCover));
      expect(cover.imageUrl, isEmpty);
      expect(
        find.descendant(
          of: find.byType(BookCover),
          matching: find.byIcon(Icons.book),
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final button = find.text('Add to Library');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(button);
        for (var i = 0; i < 100 && added == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(added, 1);
      expect(books.values.single.imageUrl, isEmpty);
      await tester.runAsync(() => repository.sync(force: true));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving Add resets manual entry to a clean search form', (
    tester,
  ) async {
    var active = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: active ? 0 : 1,
                    children: [
                      AddBookScreen(
                        repository: repository,
                        currentUid: () => 'alice',
                        onBookAdded: () {},
                        isActive: active,
                      ),
                      const Center(child: Text('Other page')),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => active = !active),
                  child: const Text('Switch tab'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manual Entry'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Manual draft',
    );
    await tester.tap(find.text('Switch tab'));
    await tester.pump();
    await tester.tap(find.text('Switch tab'));
    await tester.pump();
    expect(find.text('Search & Add'), findsOneWidget);
    expect(find.text('Manual Entry'), findsOneWidget);
    expect(find.text('Use Search'), findsNothing);
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

  testWidgets('manual cover entered in the form reaches the saved book', (
    tester,
  ) async {
    var added = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AddBookScreen(
          repository: repository,
          currentUid: () => 'alice',
          onBookAdded: () => added++,
        ),
      ),
    );
    await tester.tap(find.text('Manual Entry'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'My Story');
    final cover = find.widgetWithText(TextField, 'Image URL (optional)');
    await tester.ensureVisible(cover);
    await tester.enterText(cover, 'https://example.com/cover.png');
    await tester.pump();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final button = find.text('Add to Library');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(button);
      for (var i = 0; i < 100 && added == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(books.values.single.imageUrl, 'https://example.com/cover.png');
    expect(added, 1);
    await tester.runAsync(() => repository.sync(force: true));
    await tester.pumpWidget(const SizedBox());
  });
}
