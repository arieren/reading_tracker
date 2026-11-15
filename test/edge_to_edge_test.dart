import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/screens/main_screen.dart';
import 'package:reading_tracker/theme/app_theme.dart';
import 'package:reading_tracker/theme/system_ui.dart';

import 'book_repository_test.dart' show MemoryCloud;

void main() {
  late Directory directory;
  late BookRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('reading-insets-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    repository = BookRepository(
      books: await Hive.openBox<Book>('books'),
      outbox: await Hive.openBox<dynamic>('inset_outbox'),
      cloud: MemoryCloud(),
      currentUid: () => 'reader',
    );
    BookRepository.instance = repository;
  });
  tearDown(() async {
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  for (final brightness in Brightness.values) {
    for (final bottom in [24.0, 48.0]) {
      testWidgets(
        'system bars and keyboard keep controls reachable in $brightness with inset $bottom',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          tester.view.viewPadding = FakeViewPadding(top: 32, bottom: bottom);
          tester.view.padding = FakeViewPadding(top: 32, bottom: bottom);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewPadding);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpWidget(
            MaterialApp(
              theme: readingTheme(brightness),
              home: const MainScreen(),
            ),
          );
          await tester.pumpAndSettle();
          final headerPosition = tester.getTopLeft(
            find.byTooltip('Open library overview'),
          );
          expect(
            tester.getTopLeft(find.byTooltip('Open library overview')).dy,
            greaterThanOrEqualTo(32),
          );
          expect(
            tester.getBottomRight(find.text('Add').last).dy,
            lessThanOrEqualTo(800 - bottom),
          );
          final style = readingSystemUiStyle(brightness);
          expect(
            style.systemNavigationBarIconBrightness,
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          );
          await tester.tap(find.text('Add').last);
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.byTooltip('Open library overview')),
            headerPosition,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          tester.view.padding = const FakeViewPadding(top: 32);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          tester.view.padding = FakeViewPadding(top: 32, bottom: bottom);
          await tester.pumpAndSettle();
          expect(
            tester.getBottomRight(find.text('Add').last).dy,
            lessThanOrEqualTo(800 - bottom),
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
