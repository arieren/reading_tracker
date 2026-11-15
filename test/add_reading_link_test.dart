import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/screens/add_book_screen.dart';
import 'package:reading_tracker/services/reading_link_service.dart';

import 'book_repository_test.dart' show MemoryCloud;

class FakeReadingLinks extends ReadingLinkService {
  int calls = 0;
  ReadingLinkMatch? result;
  @override
  Future<ReadingLinkMatch?> find(Book book) async {
    calls++;
    return result;
  }
}

void main() {
  late Directory directory;
  late BookRepository repo;
  late FakeReadingLinks links;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('add-reading-link-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    repo = BookRepository(
      books: await Hive.openBox<Book>('books'),
      outbox: await Hive.openBox<dynamic>('outbox'),
      cloud: MemoryCloud(),
      currentUid: () => 'alice',
    );
    links = FakeReadingLinks();
  });
  tearDown(() async {
    repo.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  for (final found in [true, false]) {
    testWidgets(
      'Add preserves local saving with ${found ? 'an exact match' : 'no exact match'}',
      (tester) async {
        links.result = found
            ? const ReadingLinkMatch(
                'https://atsu.moe/manga/story',
                image: 'https://images.example/cover.jpg',
              )
            : null;
        var added = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AddBookScreen(
              repository: repo,
              readingLinks: links,
              currentUid: () => 'alice',
              onBookAdded: () => added++,
            ),
          ),
        );
        await tester.tap(find.text('Manual Entry'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Title'),
          'My Story',
        );
        await tester.ensureVisible(find.byType(DropdownButton<String>));
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manhwa').last);
        await tester.pumpAndSettle();
        final save = find.text('Add to Library');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(save);
          for (var i = 0; i < 100 && added == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump();
        expect(added, 1);
        expect(links.calls, 1);
        expect(
          repo.userBooks.single.linkURL,
          found ? 'https://atsu.moe/manga/story' : '',
        );
        if (found) {
          expect(
            repo.userBooks.single.imageUrl,
            'https://images.example/cover.jpg',
          );
        }
        await tester.runAsync(() => repo.sync(force: true));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
