import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/widgets/reading_dialogs.dart';

void main() {
  testWidgets(
    'bookmark confirmation prefills detected details and keeps corrections',
    (tester) async {
      ReadingBookmarkInput? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showReadingBookmarkDialog(
                    context,
                    title: 'The Stellar Swordmaster',
                    chapter: 145,
                    type: 'Manhwa',
                  );
                },
                child: const Text('Save page'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save page'));
      await tester.pumpAndSettle();
      expect(find.text('The Stellar Swordmaster'), findsOneWidget);
      expect(find.text('Manhwa'), findsOneWidget);
      expect(find.text('145'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Chapter'), '144');
      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();
      expect(result, (
        title: 'The Stellar Swordmaster',
        chapter: 144,
        type: 'Manhwa',
      ));
    },
  );
}
