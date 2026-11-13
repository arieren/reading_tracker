import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/account_deletion_service.dart';

void main() {
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
