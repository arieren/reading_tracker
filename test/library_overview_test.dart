import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/widgets/library_overview.dart';

import 'book_repository_test.dart' show MemoryCloud;

void main() {
  testWidgets('header opens a useful shelf overview with navigation and sync', (
    tester,
  ) async {
    late Directory directory;
    late BookRepository repository;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('library-overview-');
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
      final books = await Hive.openBox<Book>('overview_books');
      await books.add(
        Book(
          id: 'book-1',
          uid: 'reader',
          title: 'Story',
          type: 'Manga',
          chapter: 12,
        ),
      );
      repository = BookRepository(
        books: books,
        outbox: await Hive.openBox<dynamic>('overview_outbox'),
        cloud: MemoryCloud(),
        currentUid: () => 'reader',
      );
    });
    addTearDown(() async {
      repository.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    });
    int? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: LibraryHeaderButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => LibraryOverview(
                    repository: repository,
                    onNavigate: (index) => destination = index,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Open library overview'));
    await tester.pumpAndSettle();
    expect(find.text('Your shelf'), findsOneWidget);
    expect(find.text('1 story in your library'), findsOneWidget);
    expect(find.text('Manga · 1'), findsOneWidget);
    await tester.tap(find.text('Open library'));
    expect(destination, 2);
    await tester.tap(find.text('Back to Home'));
    expect(destination, 0);
    await tester.runAsync(() async {
      await tester.tap(find.text('Sync now'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Cloud sync complete.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
