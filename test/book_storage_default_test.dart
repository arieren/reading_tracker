import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/data/book_storage.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());
  test('published routing stays legacy without a checkpoint even if a default exists', () async {
    await db.doc('storage_configuration/books').set({'state': 'ready'});
    expect(
      await BookStorage(db, enabled: true, accountDefault: false).read('new'),
      BookStorageLayout.legacy,
    );
  });
  test('opt-in future accounts follow the server default in reads and transactions', () async {
    final storage = BookStorage(db, enabled: true, accountDefault: true);
    expect(await storage.read('new'), BookStorageLayout.legacy);
    await db.doc('storage_configuration/books').set({'state': 'ready'});
    expect(await storage.read('new'), BookStorageLayout.user);
    expect(
      await db.runTransaction(
        (transaction) => storage.readInTransaction(transaction, 'new'),
      ),
      BookStorageLayout.user,
    );
    expect((await storage.metadata('new').get()).exists, isFalse);
  });
  test(
    'explicit existing-account checkpoints always override the global default',
    () async {
      final storage = BookStorage(db, enabled: true, accountDefault: true);
      await db.doc('storage_configuration/books').set({'state': 'ready'});
      await storage.metadata('existing').set({'state': 'legacy'});
      expect(await storage.read('existing'), BookStorageLayout.legacy);
      await storage.metadata('existing').set({'state': 'copying'});
      await expectLater(
        storage.read('existing'),
        throwsA(isA<StorageMigrationInProgress>()),
      );
      await storage.metadata('existing').set({'state': 'unexpected'});
      await expectLater(storage.read('existing'), throwsStateError);
    },
  );
  test('activation pause and unknown defaults fail closed', () async {
    final storage = BookStorage(db, enabled: true, accountDefault: true);
    await db.doc('storage_configuration/books').set({'state': 'copying'});
    await expectLater(
      storage.read('new'),
      throwsA(isA<StorageMigrationInProgress>()),
    );
    await db.doc('storage_configuration/books').set({'state': 'unexpected'});
    await expectLater(storage.read('new'), throwsStateError);
    expect(
      await BookStorage(db, enabled: false, accountDefault: true).read('new'),
      BookStorageLayout.legacy,
    );
  });
}
