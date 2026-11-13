import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/account_deletion_service.dart';

void main() {
  test('cancelled migration cleanup removes partial nested copies and routing metadata', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('storage_migrations/alice').set({'state': 'legacy'});
    await db.doc('users/alice/books/partial').set({'uid': 'alice'});
    await AccountDeletionService(
      firestore: db,
      userBookStorage: true,
    ).delete('alice', deleteIdentity: () async {});
    expect((await db.doc('users/alice/books/partial').get()).exists, isFalse);
    expect((await db.doc('storage_migrations/alice').get()).exists, isFalse);
  });
  test(
    'migrated cleanup removes both layouts but not other accounts',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('storage_migrations/alice').set({'state': 'ready'});
      for (final path in [
        'books/old',
        'book_deletions/old',
        'users/alice/books/new',
        'users/alice/book_deletions/new',
      ]) {
        await db.doc(path).set({'uid': 'alice'});
      }
      await db.doc('users/bob/books/other').set({'uid': 'bob'});
      await AccountDeletionService(
        firestore: db,
        userBookStorage: true,
      ).delete('alice', deleteIdentity: () async {});
      expect((await db.collection('books').get()).docs, isEmpty);
      expect((await db.collection('book_deletions').get()).docs, isEmpty);
      expect(
        (await db.collection('users').doc('alice').collection('books').get())
            .docs,
        isEmpty,
      );
      expect((await db.doc('users/bob/books/other').get()).exists, isTrue);
      expect(
        (await db.doc('account_deletions/alice').get()).data()!['status'],
        'data-cleared',
      );
    },
  );
  test(
    'copying blocks account deletion before its irreversible lock',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('storage_migrations/alice').set({'state': 'copying'});
      await expectLater(
        AccountDeletionService(
          firestore: db,
          userBookStorage: true,
        ).delete('alice', deleteIdentity: () async {}),
        throwsA(isA<Exception>()),
      );
      expect((await db.doc('account_deletions/alice').get()).exists, isFalse);
    },
  );
  test(
    'Spark cleanup resumes after data was cleared but identity deletion failed',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 225; i++) {
        await db.collection('books').doc('a$i').set({'uid': 'alice'});
      }
      await db.collection('books').doc('bob').set({'uid': 'bob'});
      await db.collection('book_deletions').doc('deleted').set({
        'uid': 'alice',
      });
      final service = AccountDeletionService(firestore: db);
      await expectLater(
        service.delete(
          'alice',
          deleteIdentity: () async => throw StateError('reauth needed'),
        ),
        throwsStateError,
      );
      expect((await db.collection('books').get()).docs.single.id, 'bob');
      expect((await db.collection('book_deletions').get()).docs, isEmpty);
      final job = db.collection('account_deletions').doc('alice');
      expect((await job.get()).data()!['status'], 'data-cleared');
      var deleted = false;
      await service.delete(
        'alice',
        deleteIdentity: () async {
          deleted = true;
        },
      );
      expect(deleted, isTrue);
      expect((await job.get()).exists, isTrue);
    },
  );
}
