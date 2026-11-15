import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reading_tracker/screens/app_update_screen.dart';
import 'package:reading_tracker/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('update screen fits a small viewport in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: readingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AppUpdateScreen(onUpdate: () => opened = true),
        ),
      );
      await tester.ensureVisible(find.text('Update now'));
      await tester.tap(find.text('Update now'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
