import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/data/book_cloud.dart';
import 'package:reading_tracker/models/book_codec.dart';

Map<String, dynamic> book({int chapter = 1, String title = 'Story'}) => {
  'uid': 'alice',
  'title': title,
  'type': 'Manga',
  'chapter': chapter,
  'imageUrl': '',
  'linkURL': '',
  'lastRead': '2025-11-13T10:20:33.315090Z',
};

// Reproduce the native plugin path that replaces a callback exception with a
// generic platform failure. Domain refusals must survive that boundary.
class CallbackWrappingFirestore extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    try {
      return await super.runTransaction(
        transactionHandler,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } on Object {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unknown');
    }
  }
}

void main() {
  test(
    'native callback wrapping retains conflict and deletion refusals',
    () async {
      final db = CallbackWrappingFirestore();
      final cloud = FirestoreBookCloud(firestore: db);
      await db.doc('books/one').set(book(chapter: 3));
      await expectLater(
        cloud.write(
          'one',
          book(chapter: 2),
          changes: {'chapter': 2},
          base: book(chapter: 1),
        ),
        throwsA(isA<BookConflictException>()),
      );
      expect((await db.doc('books/one').get()).data()!['chapter'], 3);
      await db.doc('account_deletions/alice').set({'uid': 'alice'});
      await expectLater(
        cloud.delete('one', uid: 'alice'),
        throwsA(isA<AccountDeletionPendingException>()),
      );
      expect((await db.doc('books/one').get()).exists, isTrue);
    },
  );
  late FakeFirebaseFirestore db;
  late FirestoreBookCloud cloud;
  setUp(() {
    db = FakeFirebaseFirestore();
    cloud = FirestoreBookCloud(firestore: db);
  });
  test('migration feature is opt-in and absent metadata uses legacy', () async {
    await db.collection('storage_migrations').doc('alice').set({
      'state': 'ready',
    });
    await cloud.write('old', book());
    expect((await db.collection('books').doc('old').get()).exists, isTrue);
    await db.collection('storage_migrations').doc('alice').delete();
    cloud = FirestoreBookCloud(firestore: db, userBookStorage: true);
    expect((await cloud.fetch('alice')).keys, ['old']);
  });
  test(
    'routing cutover invalidates the old full snapshot and cursors',
    () async {
      cloud = FirestoreBookCloud(firestore: db, userBookStorage: true);
      await cloud.write('one', book());
      await cloud.write('removed', book());
      expect((await cloud.fetch('alice')).length, 2);
      await db.doc('users/alice/books/one').set(book(chapter: 8));
      await db.doc('storage_migrations/alice').set({'state': 'ready'});
      final rows = await cloud.fetch('alice');
      expect(rows.keys, ['one']);
      expect(rows['one']!['chapter'], 8);
    },
  );
  test('copying pauses all cloud operations without changing books', () async {
    cloud = FirestoreBookCloud(firestore: db, userBookStorage: true);
    await db.collection('books').doc('one').set(book());
    await db.doc('storage_migrations/alice').set({'state': 'copying'});
    await expectLater(
      cloud.fetch('alice'),
      throwsA(isA<StorageMigrationInProgress>()),
    );
    await expectLater(
      cloud.write('one', book(chapter: 9)),
      throwsA(isA<StorageMigrationInProgress>()),
    );
    await expectLater(
      cloud.delete('one', uid: 'alice'),
      throwsA(isA<StorageMigrationInProgress>()),
    );
    expect((await db.doc('books/one').get()).data()!['chapter'], 1);
  });
  test(
    'nested upgrades and deletions leave frozen legacy copies untouched',
    () async {
      cloud = FirestoreBookCloud(
        firestore: db,
        userBookStorage: true,
        legacyCompatibility: true,
      );
      await db.doc('storage_migrations/alice').set({'state': 'ready'});
      await db.doc('books/one').set(book());
      await db.doc('users/alice/books/one').set(book());
      await cloud.write(
        'one',
        book(chapter: 6),
        changes: {'uid': 'alice', 'chapter': 6},
        operationId: 'edit',
      );
      final row = (await db.doc('users/alice/books/one').get()).data()!;
      expect(row['chapter'], 6);
      expect(row['revision'], 1);
      expect(row['lastRead'], isA<String>());
      expect((await db.doc('books/one').get()).data()!['chapter'], 1);
      await cloud.delete('one', uid: 'alice');
      expect((await db.doc('users/alice/books/one').get()).exists, isFalse);
      expect(
        (await db.doc('users/alice/book_deletions/one').get()).exists,
        isTrue,
      );
      expect((await db.doc('books/one').get()).exists, isTrue);
      await expectLater(
        cloud.write('one', book()),
        throwsA(isA<DeletedBookException>()),
      );
    },
  );
  test(
    'unknown migration states fail closed instead of empty reconciliation',
    () async {
      cloud = FirestoreBookCloud(firestore: db, userBookStorage: true);
      await db.doc('storage_migrations/alice').set({'state': 'unexpected'});
      await expectLater(cloud.fetch('alice'), throwsStateError);
    },
  );
  test(
    'unfinished account deletion blocks fetches and all normal mutations',
    () async {
      await cloud.write('one', book(), operationId: 'create');
      await db.collection('account_deletions').doc('alice').set({
        'uid': 'alice',
        'status': 'pending',
      });
      await expectLater(
        cloud.fetch('alice'),
        throwsA(isA<AccountDeletionPendingException>()),
      );
      await expectLater(
        cloud.write('one', book(chapter: 4)),
        throwsA(isA<AccountDeletionPendingException>()),
      );
      await expectLater(
        cloud.delete('one', uid: 'alice'),
        throwsA(isA<AccountDeletionPendingException>()),
      );
      expect(
        (await db.collection('books').doc('one').get()).data()!['chapter'],
        1,
      );
    },
  );
  test(
    'writes native timestamps and increments revision with idempotent retry',
    () async {
      await cloud.write('one', book(), operationId: 'create');
      var remote = (await db.collection('books').doc('one').get()).data()!;
      expect(remote['lastRead'], isA<Timestamp>());
      expect(remote['updatedAt'], isA<Timestamp>());
      expect(remote['revision'], 1);
      await cloud.write('one', book(), operationId: 'create');
      remote = (await db.collection('books').doc('one').get()).data()!;
      expect(remote['revision'], 1);
      await cloud.write(
        'one',
        book(chapter: 2),
        changes: {'uid': 'alice', 'chapter': 2},
        base: book(),
        operationId: 'edit',
      );
      expect(
        (await db.collection('books').doc('one').get()).data()!['revision'],
        2,
      );
    },
  );
  test(
    'disjoint edits merge but competing edits raise an explicit conflict',
    () async {
      await cloud.write('one', book(), operationId: 'create');
      await cloud.write(
        'one',
        book(chapter: 9),
        changes: {'chapter': 9, 'uid': 'alice'},
        base: book(),
        operationId: 'chapter',
      );
      final merged = await cloud.write(
        'one',
        book(title: 'Rename'),
        changes: {'title': 'Rename', 'uid': 'alice'},
        base: book(),
        operationId: 'title',
      );
      expect(merged['chapter'], 9);
      await expectLater(
        cloud.write(
          'one',
          book(chapter: 3),
          changes: {'chapter': 3, 'uid': 'alice'},
          base: book(),
          operationId: 'conflict',
        ),
        throwsA(isA<BookConflictException>()),
      );
      expect(
        (await db.collection('books').doc('one').get()).data()!['chapter'],
        9,
      );
    },
  );
  test('deletion permanently blocks stale updates and retries', () async {
    await cloud.write('one', book(), operationId: 'create');
    await cloud.delete('one', uid: 'alice');
    await cloud.delete('one', uid: 'alice');
    expect((await db.collection('books').doc('one').get()).exists, isFalse);
    expect(
      (await db.collection('book_deletions').doc('one').get()).data()!['uid'],
      'alice',
    );
    await expectLater(
      cloud.write('one', book(), operationId: 'create'),
      throwsA(isA<DeletedBookException>()),
    );
    await expectLater(
      cloud.write('one', book(chapter: 5), operationId: 'stale'),
      throwsA(isA<DeletedBookException>()),
    );
  });
  test('missing previously synced record is not silently recreated', () async {
    await expectLater(
      cloud.write('missing', book(), allowCreate: false),
      throwsA(isA<DeletedBookException>()),
    );
  });
  test(
    'initial full read includes legacy rows and incremental read retains them',
    () async {
      await db.collection('books').doc('legacy').set(book());
      await cloud.write('new', book(title: 'New'), operationId: 'new');
      expect((await cloud.fetch('alice')).keys.toSet(), {'legacy', 'new'});
      await cloud.write(
        'new',
        book(chapter: 8),
        changes: {'chapter': 8, 'uid': 'alice'},
        operationId: 'update',
      );
      var rows = await cloud.fetch('alice');
      expect(rows['new']!['chapter'], 8);
      expect(rows.containsKey('legacy'), isTrue);
      await cloud.delete('new', uid: 'alice');
      rows = await cloud.fetch('alice');
      expect(rows.keys, ['legacy']);
      expect(await cloud.fetch('bob'), isEmpty);
      expect((await cloud.fetch('alice')).keys, ['legacy']);
    },
  );
  test(
    'legacy strings and timestamps normalize to the same comparison value',
    () {
      final timestamp = Timestamp.fromDate(DateTime.utc(2025, 1, 2, 3));
      expect(
        normalizeCloudBook({'lastRead': timestamp})['lastRead'],
        normalizeCloudBook({'lastRead': '2025-01-02T03:00:00Z'})['lastRead'],
      );
    },
  );
  test('compatibility writes keep dates readable by the old app', () async {
    cloud = FirestoreBookCloud(firestore: db, legacyCompatibility: true);
    await cloud.write('one', book(), operationId: 'create');
    final remote = (await db.collection('books').doc('one').get()).data()!;
    expect(remote['lastRead'], isA<String>());
    expect(DateTime.parse(remote['lastRead'] as String).isUtc, isTrue);
    expect(remote['updatedAt'], isA<Timestamp>());
    expect(remote['revision'], 1);
  });
  test(
    'compatibility reads detect unversioned edits and direct deletes',
    () async {
      cloud = FirestoreBookCloud(firestore: db, legacyCompatibility: true);
      await db.collection('books').doc('legacy').set(book());
      await cloud.write('modern', book(), operationId: 'create');
      expect((await cloud.fetch('alice')).length, 2);
      // Old clients do not advance updatedAt or create deletion markers.
      await db.collection('books').doc('legacy').update({'chapter': 7});
      await db.collection('books').doc('modern').delete();
      final rows = await cloud.fetch('alice');
      expect(rows.keys, ['legacy']);
      expect(rows['legacy']!['chapter'], 7);
    },
  );
  test(
    'compatibility edits preserve legacy changes and detect conflicts',
    () async {
      cloud = FirestoreBookCloud(firestore: db, legacyCompatibility: true);
      await cloud.write('one', book(), operationId: 'create');
      await db.collection('books').doc('one').update({'chapter': 7});
      final merged = await cloud.write(
        'one',
        book(title: 'Renamed'),
        changes: {'title': 'Renamed', 'uid': 'alice'},
        base: book(),
        operationId: 'rename',
      );
      expect(merged['chapter'], 7);
      expect(merged['revision'], 2);
      await expectLater(
        cloud.write(
          'one',
          book(chapter: 4),
          changes: {'chapter': 4, 'uid': 'alice'},
          base: book(),
          operationId: 'conflict',
        ),
        throwsA(isA<BookConflictException>()),
      );
    },
  );
}
