import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/widgets/book_metadata.dart';
import 'package:reading_tracker/widgets/library_empty_state.dart';

void main() {
  testWidgets('book metadata wraps on a narrow screen with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 140,
                child: BookMetadata(type: 'Light Novel', chapter: 12345),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Light Novel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'an empty library remains refreshable and reports offline status',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryEmptyState(
              title: 'No books',
              message: 'Add a book',
              refresh: () async {
                attempts++;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(
        find.text('Cloud unavailable; showing saved books.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
