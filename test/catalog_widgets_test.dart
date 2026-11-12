import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/screens/add_book_screen.dart';
import 'package:reading_tracker/services/catalog_service.dart';
import 'package:reading_tracker/services/import_service.dart';
import 'package:reading_tracker/widgets/book_import_dialog.dart';

http.Response matches(String title) => http.Response(
  jsonEncode({
    'data': [
      {'title': title, 'type': 'Manhwa', 'images': null},
    ],
  }),
  200,
);

void main() {
  testWidgets('canceling automatic lookup discards the whole import', (
    tester,
  ) async {
    List<ImportEntry>? imported;
    var closed = false;
    var calls = 0;
    final response = Completer<http.Response>();
    final catalog = CatalogService(
      request: (_) {
        calls++;
        return response.future;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                imported = await showDialog<List<ImportEntry>>(
                  context: context,
                  builder: (_) => BookImportDialog(catalog: catalog),
                );
                closed = true;
              },
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'First 12\nSecond 9');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    response.complete(matches('First result'));
    await tester.pump();
    expect(closed, isTrue);
    expect(imported, isNull);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add search displays progress and ignores stale responses', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final current = Completer<http.Response>();
    final catalog = CatalogService(
      request: (uri) =>
          uri.queryParameters['q'] == 'Old' ? old.future : current.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AddBookScreen(catalog: catalog, onBookAdded: () {}),
      ),
    );
    final field = find.widgetWithText(TextField, 'Title');
    await tester.enterText(field, 'Old');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.enterText(field, 'Current');
    await tester.pump(const Duration(milliseconds: 600));
    current.complete(matches('Current result'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Current result'), findsOneWidget);
    old.complete(matches('Old result'));
    await tester.pump();
    expect(find.text('Old result'), findsNothing);
    await tester.tap(find.text('Current result'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Current result');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('add search distinguishes failure from no matches and retries', (
    tester,
  ) async {
    var calls = 0;
    final catalog = CatalogService(
      request: (_) async => ++calls == 1
          ? http.Response('', 503)
          : http.Response('{"data":[]}', 200),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AddBookScreen(catalog: catalog, onBookAdded: () {}),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Unknown');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(
      find.text('Catalog unavailable. Please retry or use manual entry.'),
      findsOneWidget,
    );
    expect(find.textContaining('No matches found'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('No matches found'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), '');
    await tester.pump();
    expect(find.textContaining('No matches found'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('import selected match preserves chapter and other entries', (
    tester,
  ) async {
    List<ImportEntry>? imported;
    final catalog = CatalogService(
      request: (uri) async => uri.queryParameters['q'] == 'Other'
          ? http.Response('{"data":[]}', 200)
          : http.Response(
              jsonEncode({
                'data': [
                  {'title': 'Matched title', 'type': 'Manhwa'},
                  {'title': 'Alternate title', 'type': 'Light Novel'},
                ],
              }),
              200,
            ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                imported = await showDialog<List<ImportEntry>>(
                  context: context,
                  builder: (_) => BookImportDialog(catalog: catalog),
                );
              },
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Original 22\nOther 4');
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Matched title'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose catalog match').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alternate title (Light Novel)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(imported!.first.title, 'Alternate title');
    expect(imported!.first.type, 'Light Novel');
    expect(imported!.first.chapter, 22);
    expect(imported!.last.title, 'Other');
    expect(imported!.last.chapter, 4);
  });

  testWidgets('direct import automatically selects the first match and cover', (
    tester,
  ) async {
    List<ImportEntry>? imported;
    final catalog = CatalogService(
      request: (_) async => http.Response(
        jsonEncode({
          'data': [
            {
              'title': 'Top result',
              'type': 'Manga',
              'images': {
                'jpg': {'image_url': 'https://example.com/cover.jpg'},
              },
            },
            {'title': 'Second result', 'type': 'Novel'},
          ],
        }),
        200,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                imported = await showDialog<List<ImportEntry>>(
                  context: context,
                  builder: (_) => BookImportDialog(catalog: catalog),
                );
              },
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Entered title 17');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(imported!.single.title, 'Top result');
    expect(imported!.single.type, 'Manga');
    expect(imported!.single.imageUrl, 'https://example.com/cover.jpg');
    expect(imported!.single.chapter, 17);
  });

  testWidgets(
    'unavailable catalog does not prevent importing original titles',
    (tester) async {
      List<ImportEntry>? imported;
      final catalog = CatalogService(
        request: (_) async => http.Response('', 503),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  imported = await showDialog<List<ImportEntry>>(
                    context: context,
                    builder: (_) => BookImportDialog(catalog: catalog),
                  );
                },
                child: const Text('Open import'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Original 22');
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose catalog match'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Catalog unavailable.'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
      await tester.pumpAndSettle();
      expect(imported!.single.title, 'Original');
      expect(imported!.single.chapter, 22);
    },
  );
}
