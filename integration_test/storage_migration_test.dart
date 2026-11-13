import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/services/account_deletion_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native migrated storage retains offline progress and cleans both layouts',
    (tester) async {
      // These credentials/project are fictional and accepted only by local emulators.
      final app = await Firebase.initializeApp(
        name: 'migration-emulator',
        options: const FirebaseOptions(
          apiKey: 'local-emulator-only',
          appId: '1:1234567890:android:0123456789',
          messagingSenderId: '1234567890',
          projectId: 'demo-reading-tracker',
        ),
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      final db = FirebaseFirestore.instanceFor(app: app);
      db.useFirestoreEmulator('10.0.2.2', 8085);
      await auth.useAuthEmulator('10.0.2.2', 9095);
      final user = (await auth.signInWithEmailAndPassword(
        email: 'migration-native@example.invalid',
        password: 'Local-emulator-fixture-12345',
      )).user!;
      const uid = 'migration-native-fixture';
      expect(user.uid, uid);
      final directory = await Directory.systemTemp.createTemp(
        'reading-tracker-migration-',
      );
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
      BookRepository? repository;
      Future<BookRepository> reopen() async => BookRepository(
        books: await Hive.openBox<Book>('migration_books'),
        outbox: await Hive.openBox<dynamic>('migration_outbox'),
        deletionState: await Hive.openBox<dynamic>('migration_deletion'),
        cloud: FirestoreBookCloud(
          firestore: db,
          userBookStorage: true,
          legacyCompatibility: true,
        ),
        currentUid: () => uid,
      );
      try {
        repository = await reopen();
        expect(await repository.sync(force: true), isTrue);
        expect(repository.userBooks.single.id, 'native-fixture');
        final denied = isA<FirebaseException>().having(
          (error) => error.code,
          'code',
          'permission-denied',
        );
        await expectLater(
          db
              .doc('books/native-fixture')
              .get(const GetOptions(source: Source.server)),
          throwsA(denied),
        );
        await db.disableNetwork();
        try {
          final original = repository.userBooks.single;
          await repository.save(
            Book(
              id: original.id,
              uid: uid,
              title: original.title,
              type: original.type,
              chapter: 7,
              lastRead: original.lastRead,
            ),
            original: original,
          );
          repository.dispose();
          repository = null;
          await Hive.close();
          repository = await reopen();
          await repository.recoverLocalChanges();
          expect(repository.userBooks.single.chapter, 7);
          expect(repository.pendingCount, 1);
        } finally {
          await db.enableNetwork();
        }
        expect(await repository.sync(force: true), isTrue);
        expect(repository.pendingCount, 0);
        final ref = db.doc('users/$uid/books/native-fixture');
        final remote = (await ref.get(const GetOptions(source: Source.server)))
            .data()!;
        expect(remote['chapter'], 7);
        expect(remote['revision'], 1);
        expect(remote['lastRead'], isA<String>());
        await repository.deleteBooks([repository.userBooks.single]);
        expect(await repository.sync(force: true), isTrue);
        expect(
          (await db.doc('users/$uid/book_deletions/native-fixture').get())
              .exists,
          isTrue,
        );
        await expectLater(
          ref.set({
            ...remote,
            'revision': 1,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          throwsA(denied),
        );
        await repository.save(
          Book(uid: uid, title: 'Account cleanup', type: 'Novel', chapter: 0),
        );
        expect(await repository.sync(force: true), isTrue);
        final service = AccountDeletionService(
          firestore: db,
          userBookStorage: true,
        );
        await expectLater(
          repository.deleteAccount(
            reauthenticate: () async {},
            requestDeletion: () => service.delete(
              uid,
              deleteIdentity: () async =>
                  throw StateError('Interrupted before Auth deletion'),
            ),
          ),
          throwsStateError,
        );
        expect(repository.deletionPending, isTrue);
        expect(repository.userBooks, isNotEmpty);
        repository.dispose();
        repository = null;
        await Hive.close();
        repository = await reopen();
        expect(repository.deletionPending, isTrue);
        await repository.deleteAccount(
          reauthenticate: () async {},
          requestDeletion: () =>
              service.delete(uid, deleteIdentity: user.delete),
        );
        expect(repository.userBooks, isEmpty);
        expect(repository.pendingCount, 0);
        expect(repository.deletionPending, isFalse);
      } finally {
        repository?.dispose();
        await Hive.close();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await directory.resolveSymbolicLinks();
        if (!resolved.startsWith('$root${Platform.pathSeparator}') ||
            !resolved
                .split(Platform.pathSeparator)
                .last
                .startsWith('reading-tracker-migration-')) {
          throw StateError('Unexpected temporary storage path.');
        }
        await directory.delete(recursive: true);
        await auth.signOut();
        await db.terminate();
        await app.delete();
      }
    },
    skip: !const bool.fromEnvironment('RUN_MIGRATION_EMULATOR_TEST'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
