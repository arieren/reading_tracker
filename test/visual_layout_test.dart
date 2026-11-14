import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/screens/home_screen.dart';
import 'package:reading_tracker/screens/browse_screen.dart';

import 'package:reading_tracker/theme/app_theme.dart';
import 'package:reading_tracker/widgets/auth_form.dart';
import 'package:reading_tracker/widgets/book_editor.dart';

import 'book_repository_test.dart' show MemoryCloud;

void main() {
  late Directory directory;
  late BookRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('reading-layout-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    repo = BookRepository(
      books: await Hive.openBox<Book>('books'),
      outbox: await Hive.openBox<dynamic>('outbox'),
      cloud: MemoryCloud(),
      currentUid: () => 'alice',
    );
    BookRepository.instance = repo;
    await repo.save(
      Book(
        uid: 'alice',
        title: 'A Garden Under the Moonlight',
        type: 'Manhwa',
        chapter: 42,
        linkURL: '',
      ),
    );
  });
  tearDown(() async {
    repo.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'home and login fit small screens in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget wrap(Widget child) => MaterialApp(
          theme: readingTheme(dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 720),
              textScaler: TextScaler.linear(1.6),
              disableAnimations: true,
            ),
            child: child,
          ),
        );
        await tester.pumpWidget(wrap(HomeScreen(onExplore: () {})));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Read now'), findsOneWidget);
        await tester.pumpWidget(wrap(const AuthForm(mode: AuthFormMode.login)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'editor scrolls above the keyboard and cancels without changing data',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: readingTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBookEditor(context, repo.userBooks.single),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit book'), findsOneWidget);
      final image = find.widgetWithText(TextField, 'Image link (optional)');
      await tester.ensureVisible(image);
      await tester.enterText(image, 'https://example.com/new-cover.jpg');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.ensureVisible(image);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.userBooks.single.imageUrl, anyOf(isNull, isEmpty));
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('custom website can be saved, opened and removed in Browse', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: readingTheme(Brightness.light),
        home: BrowseScreen(
          onOpen: (url) async {
            opened.add(url);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add website'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'My reader');
    await tester.enterText(
      find.widgetWithText(TextField, 'Website address'),
      'https://example.com',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('My reader'));
    await tester.tap(find.text('My reader'));
    await tester.pumpAndSettle();
    expect(opened, ['https://example.com']);
    await tester.tap(find.byTooltip('Options for My reader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove website'));
    await tester.pumpAndSettle();
    expect(find.text('My reader'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Browse has website shortcuts without a catalog request', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: readingTheme(Brightness.light),
        home: BrowseScreen(
          onOpen: (url) async {
            opened.add(url);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atsu'), findsOneWidget);
    expect(find.text('WEBTOON'), findsNothing);
    expect(find.text('MANGA Plus'), findsNothing);
    await tester.tap(find.text('Atsu'));
    await tester.pumpAndSettle();
    expect(opened, ['https://atsu.moe/explore']);
    await tester.enterText(
      find.widgetWithText(TextField, 'Website or reading link'),
      'javascript:alert(1)',
    );
    await tester.tap(find.byTooltip('Open website'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(find.textContaining('Enter a full'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
