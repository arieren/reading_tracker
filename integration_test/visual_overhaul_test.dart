import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/screens/main_screen.dart';
import 'package:reading_tracker/screens/reader_screen.dart';

import 'package:reading_tracker/services/reading_position.dart';
import 'package:reading_tracker/services/reading_metadata.dart';

import 'package:reading_tracker/theme/app_theme.dart';
import 'package:reading_tracker/widgets/auth_form.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../test/book_repository_test.dart' show MemoryCloud;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cozy navigation and reader preserve place across SPA navigation', (
    tester,
  ) async {
    expect(appFlavor, 'staging');
    final directory = await Directory.systemTemp.createTemp(
      'visual-rehearsal-',
    );
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    final books = await Hive.openBox<Book>('books');
    final repo = BookRepository(
      books: books,
      outbox: await Hive.openBox<dynamic>('visual_outbox'),
      cloud: MemoryCloud(),
      currentUid: () => 'visual-rehearsal',
    );
    BookRepository.instance = repo;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final chapter =
          int.tryParse(request.uri.pathSegments.last.split('-').last) ?? 1;
      final title = request.uri.path.startsWith('/new/')
          ? 'New Adventure'
          : 'Cozy Journey';
      request.response.headers.contentType = ContentType.html;
      final newStory = request.uri.path.startsWith('/new/');
      request.response.write(
        '<!doctype html><html><head><title>${newStory ? 'Atsumaru' : '$title - Chapter $chapter | Atsumaru'}</title><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="background:#fffaf3;color:#30283d;font-family:sans-serif"><h1>$title</h1><h2 ${newStory ? 'data-current-chapter="$chapter"' : ''}>Chapter $chapter</h2><span data-media-type="Manhwa"></span><p>A fictional local page for reader verification.</p><div style="height:5000px;background:linear-gradient(#eee4f9,#d8eadf)"></div></body></html>',
      );
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 150 && !condition(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
      }
      expect(condition(), isTrue);
    }

    Widget app(Widget child, {bool dark = false}) => MaterialApp(
      theme: readingTheme(dark ? Brightness.dark : Brightness.light),
      home: child,
    );
    Future<void> reader(String url, {Book? book}) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => book == null
                    ? openReadingSite(context, url)
                    : openBookReader(context, book),
                child: const Text('Launch reader'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch reader'));
      await until(() => find.byType(WebViewWidget).evaluate().isNotEmpty);
    }

    try {
      await repo.save(
        Book(
          uid: 'visual-rehearsal',
          title: 'Cozy Journey',
          type: 'Manga',
          chapter: 0,
          linkURL: '$base/story/chapter-1',
        ),
      );
      await repo.sync(force: true);
      await reader('$base/story/chapter-1', book: repo.userBooks.single);
      await until(() => repo.userBooks.single.chapter == 1);
      var web = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      await web.runJavaScript(
        'document.title="Cozy Journey - Chapter 2 | Atsumaru";history.pushState({},"","/story/chapter-2");',
      );
      await until(
        () =>
            repo.userBooks.single.chapter == 2 &&
            repo.userBooks.single.linkURL!.endsWith('chapter-2'),
      );
      await web.runJavaScript(
        'document.title="Different Story - Chapter 99";history.pushState({},"","/other/chapter-99");',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      expect(repo.userBooks.single.chapter, 2);
      expect(repo.userBooks.single.linkURL, '$base/story/chapter-2');
      await web.runJavaScript(
        'document.title="Cozy Journey - Chapter 2 | Atsumaru";history.pushState({},"","/story/chapter-2");window.scrollTo(0,480);',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Hide reader controls'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(find.byTooltip('Show reader controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close reader'));
      await until(() => find.byType(ReaderScreen).evaluate().isEmpty);
      final saved = await ReadingPositionStore().read(
        uid: 'visual-rehearsal',
        bookId: repo.userBooks.single.id!,
        url: '$base/story/chapter-2',
      );
      expect(saved, greaterThan(300));
      await reader('$base/story/chapter-2', book: repo.userBooks.single);
      await until(
        () =>
            find.byTooltip('Place saved on this device').evaluate().isNotEmpty,
      );
      web = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      expect(
        await web.runJavaScriptReturningResult('window.scrollY'),
        isA<num>(),
      );
      expect(
        (await web.runJavaScriptReturningResult('window.scrollY') as num)
            .toDouble(),
        greaterThan(300),
      );
      await tester.tap(find.byTooltip('Close reader'));
      await until(() => find.byType(ReaderScreen).evaluate().isEmpty);
      await reader('$base/new/chapter-5');
      await until(
        () =>
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save to library'),
                )
                .onPressed !=
            null,
      );
      await tester.tap(find.text('Save to library'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(TextField, 'New Adventure'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);
      expect(find.text('Manhwa'), findsOneWidget);
      await tester.tap(find.text('Add to library'));
      await until(() => repo.userBooks.length == 2);
      expect(
        repo.userBooks
            .firstWhere((book) => book.title == 'New Adventure')
            .chapter,
        5,
      );
      expect(
        repo.userBooks
            .firstWhere((book) => book.title == 'New Adventure')
            .linkURL,
        '$base/new/chapter-5',
      );
      await tester.tap(find.byTooltip('Close reader'));
      await until(() => find.byType(ReaderScreen).evaluate().isEmpty);
      debugPrint(
        'PASS: SPA bookmark/chapter saving, cross-story rejection, focus, scroll restore and direct browser capture.',
      );

      await binding.convertFlutterSurfaceToImage();
      final snapshotDirectory = await getTemporaryDirectory();
      Future<void> snapshot(String name) async {
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
            .clearSnackBars();
        await tester.pumpAndSettle();
        // Surface capture after native platform views can omit clean layers.
        // Repaint the full fixture tree so header/toolbar pixels are included.
        void repaint(RenderObject object) {
          object.markNeedsPaint();
          object.visitChildren(repaint);
        }

        for (final view in binding.renderViews) {
          repaint(view);
        }
        await tester.pump();
        final bytes = await binding.takeScreenshot(name);
        await File('${snapshotDirectory.path}/$name.png').writeAsBytes(bytes);
      }

      await tester.pumpWidget(app(const MainScreen()));
      await tester.pumpAndSettle();
      await snapshot('home-light');
      await tester.tap(find.byTooltip('Edit New Adventure'));
      await tester.pumpAndSettle();
      await snapshot('editor-light');
      await tester.enterText(find.widgetWithText(TextField, 'Chapter'), '6');
      await tester.tap(find.text('Save'));
      await until(() => find.text('Edit book').evaluate().isEmpty);
      expect(
        repo.userBooks
            .firstWhere((book) => book.title == 'New Adventure')
            .chapter,
        6,
      );
      await tester.tap(find.text('Browse').last);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await snapshot('explore-light');
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      await snapshot('library-light');
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      await snapshot('add-light');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(const MainScreen(), dark: true));
      await tester.pumpAndSettle();
      await snapshot('home-dark');
      await tester.pumpWidget(
        app(const AuthForm(mode: AuthFormMode.login), dark: true),
      );
      await tester.pumpAndSettle();
      await snapshot('login-dark');
      var fixtureReady = false;
      final metadataController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => fixtureReady = true),
        );
      await tester.pumpWidget(
        app(Scaffold(body: WebViewWidget(controller: metadataController))),
      );
      await metadataController.loadHtmlString('''
        <html><head><title>Atsumaru</title></head><body>
          <a href="/manga/fixture"><span>Manhwa Info</span><span>The Stellar Swordmaster</span></a>
          <button>Previous Chapter 144</button><button>Chapter 145 / 146</button><button>Next Chapter 146</button>
          <a href="/manga/other"><span>Novel Info</span><span>Another Story</span></a>
        </body></html>
      ''', baseUrl: 'https://atsu.moe/read/fixture/chapter-id');
      await until(() => fixtureReady);
      dynamic extracted = await metadataController.runJavaScriptReturningResult(
        readingMetadataScript,
      );
      for (var i = 0; i < 2 && extracted is String; i++) {
        extracted = jsonDecode(extracted);
      }
      final metadata = ReadingPageMetadata.fromMap(extracted as Map);
      expect(metadata.title, 'The Stellar Swordmaster');
      expect(metadata.chapter, 145);
      expect(metadata.type, 'Manhwa');
      fixtureReady = false;
      await metadataController.loadHtmlString('''
        <html><head><title></title></head><body>
          <a href="/manga/3nRa"></a>
          <button aria-hidden="false"><p class="invisible">Break New World</p><span>Break New World</span></button>
          <button>Previous Chapter 34</button><button>Chapter 35 / 68</button><button>Next Chapter 36</button>
        </body></html>
      ''', baseUrl: 'https://atsu.moe/read/3nRa/Lavmv');
      await until(() => fixtureReady);
      dynamic compact = await metadataController.runJavaScriptReturningResult(
        readingMetadataScript,
      );
      for (var i = 0; i < 2 && compact is String; i++) {
        compact = jsonDecode(compact);
      }
      final compactMetadata = ReadingPageMetadata.fromMap(compact as Map);
      expect(compactMetadata.title, 'Break New World');
      expect(compactMetadata.chapter, 35);
      debugPrint(
        'PASS: Atsu reader controls detect active story, chapter and media type.',
      );
      debugPrint('PASS: light/dark visual navigation snapshots captured.');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await server.close(force: true);
      await ReadingPositionStore().removeUser('visual-rehearsal');

      repo.dispose();
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
