import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/firebase_environment.dart';

void main() {
  test('staging and production resolve to separate Firebase projects', () {
    expect(firebaseProjectForFlavor('staging'), 'reading-tracker-test-a734e');
    expect(firebaseProjectForFlavor('production'), 'reading-tracker-67f66');
    expect(firebaseProjectForFlavor(null), 'reading-tracker-67f66');
  });
  test('unknown environments fail rather than falling back to production', () {
    expect(() => firebaseProjectForFlavor('unknown'), throwsStateError);
  });
}
