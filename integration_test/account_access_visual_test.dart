import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/screens/account_access_screen.dart';
import 'package:reading_tracker/screens/main_screen.dart';
import 'package:reading_tracker/services/account_access_service.dart';
import 'package:reading_tracker/theme/app_theme.dart';

import '../test/book_repository_test.dart' show MemoryCloud;

class _PreviewAccess extends Fake implements AccountAccessService {
  @override
  AccountAccess get current => const AccountAccess(
    uid: 'preview-reader',
    email: 'reader@example.invalid',
    emailVerified: true,
    hasPassword: true,
    googleId: 'preview-google',
    googleEmail: 'reader@example.invalid',
  );
  @override
  Future<AccountAccess> refresh() async => current;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'account settings and library header fit Android in both themes',
    (tester) async {
      expect(appFlavor, 'staging');
      final directory = await Directory.systemTemp.createTemp(
        'account-access-preview-',
      );
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
      final repository = BookRepository(
        books: await Hive.openBox<Book>('books'),
        outbox: await Hive.openBox<dynamic>('preview_outbox'),
        cloud: MemoryCloud(),
        currentUid: () => 'preview-reader',
      );
      BookRepository.instance = repository;
      await repository.save(
        Book(
          uid: 'preview-reader',
          title: 'A Garden Under the Moonlight',
          type: 'Manhwa',
          chapter: 42,
        ),
      );
      await binding.convertFlutterSurfaceToImage();
      try {
        for (final brightness in Brightness.values) {
          Widget app(Widget child) => MaterialApp(
            key: UniqueKey(),
            theme: readingTheme(brightness),
            home: child,
          );
          await tester.pumpWidget(
            app(AccountAccessScreen(service: _PreviewAccess())),
          );
          await tester.pumpAndSettle();
          await binding.takeScreenshot('account-access-${brightness.name}');
          await tester.pumpWidget(app(const MainScreen()));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Open library overview'), findsOneWidget);
          await binding.takeScreenshot('library-header-${brightness.name}');
          await tester.tap(find.byTooltip('Open library overview'));
          await tester.pumpAndSettle();
          expect(find.text('1 story in your library'), findsOneWidget);
          await binding.takeScreenshot('library-overview-${brightness.name}');
          await tester.tap(find.text('Open library'));
          await tester.pumpAndSettle();
          expect(find.text('Library'), findsWidgets);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        repository.dispose();
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
