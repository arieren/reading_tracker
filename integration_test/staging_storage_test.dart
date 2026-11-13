import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/services/account_deletion_service.dart';
import 'package:reading_tracker/services/firebase_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'staging native storage survives offline reopen, legacy edits and deletion',
    (tester) async {
      expect(appFlavor, 'staging', reason: 'Never run against production.');
      await initializeFirebaseEnvironment();
      final options = Firebase.app().options;
      expect(options.projectId, 'reading-tracker-test-a734e');
      final token = DateTime.now().microsecondsSinceEpoch.toString();
      final email = 'native-storage-$token@example.invalid';
      final password = List.generate(
        32,
        (_) => Random.secure().nextInt(36).toRadixString(36),
      ).join();
      final apps = <FirebaseApp>[];
      FirebaseAuth? auth;
      FirebaseFirestore? db;
      User? user;
      Directory? directory;
      BookRepository? repository;
      var identityDeleted = false;
      try {
        for (final name in ['current', 'legacy']) {
          apps.add(
            await Firebase.initializeApp(
              name: 'storage-$name-$token',
              options: options,
            ),
          );
        }
        auth = FirebaseAuth.instanceFor(app: apps[0]);
        db = FirebaseFirestore.instanceFor(app: apps[0]);
        user = (await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        )).user!;
        final uid = user.uid;
        final legacyAuth = FirebaseAuth.instanceFor(app: apps[1]);
        await legacyAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final legacyDb = FirebaseFirestore.instanceFor(app: apps[1]);
        final database = db;
        directory = await Directory.systemTemp.createTemp(
          'reading-tracker-storage-',
        );
        Hive.init(directory.path);
        if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
        Future<BookRepository> reopen() async => BookRepository(
          books: await Hive.openBox<Book>('rehearsal_books'),
          outbox: await Hive.openBox<dynamic>('rehearsal_outbox'),
          deletionState: await Hive.openBox<dynamic>('rehearsal_deletion'),
          cloud: FirestoreBookCloud(
            firestore: database,
            legacyCompatibility: true,
          ),
          currentUid: () => uid,
        );
        repository = await reopen();
        Book draft(Book source, {int? chapter, String? title}) => Book(
          id: source.id,
          uid: uid,
          title: title ?? source.title,
          type: source.type,
          chapter: chapter ?? source.chapter,
          lastRead: source.lastRead,
          linkURL: source.linkURL,
          imageUrl: source.imageUrl,
        );
        await repository.save(
          Book(
            uid: uid,
            title: 'Native rehearsal',
            type: 'Manga',
            chapter: 1,
            lastRead: DateTime.utc(2025, 11, 13),
          ),
        );
        expect(await repository.sync(force: true), isTrue);
        final id = repository.userBooks.single.id!;
        final ref = legacyDb.collection('books').doc(id);
        const savedText = '  number notes  ';
        await ref.update({'linkURL': savedText});
        expect(await repository.sync(force: true), isTrue);
        expect(repository.userBooks.single.linkURL, savedText);
        expect(
          (await ref.get(const GetOptions(source: Source.server)))
              .data()!['lastRead'],
          isA<String>(),
        );

        // Save to Hive while disconnected, then close/reopen its actual files.
        await database.disableNetwork();
        try {
          var original = repository.userBooks.single;
          await repository.save(
            draft(original, chapter: 5),
            original: original,
          );
          expect(repository.pendingCount, 1);
          repository.dispose();
          repository = null;
          await Hive.close();
          repository = await reopen();
          await repository.recoverLocalChanges();
          expect(repository.userBooks.single.chapter, 5);
          expect(repository.pendingCount, 1);
        } finally {
          await database.enableNetwork();
        }
        expect(await repository.sync(force: true), isTrue);
        expect(repository.pendingCount, 0);
        expect(repository.userBooks.single.linkURL, savedText);
        expect(
          (await ref.get(const GetOptions(source: Source.server)))
              .data()!['chapter'],
          5,
        );

        // Exact old-client partial update: no revision or updatedAt advancement.
        await ref.update({'chapter': 8});
        expect(await repository.sync(force: true), isTrue);
        expect(repository.userBooks.single.chapter, 8);
        var original = repository.userBooks.single;
        await repository.save(draft(original, chapter: 9), original: original);
        await ref.update({'chapter': 10});
        await repository.sync(force: true);
        expect(repository.conflicts, hasLength(1));
        await repository.resolveConflict(id, keepLocal: false);
        expect(repository.userBooks.single.chapter, 10);

        original = repository.userBooks.single;
        await repository.save(
          draft(original, title: 'Renamed locally'),
          original: original,
        );
        await ref.update({'chapter': 11});
        expect(await repository.sync(force: true), isTrue);
        expect(repository.userBooks.single.chapter, 11);
        expect(repository.userBooks.single.title, 'Renamed locally');

        await repository.deleteBooks([repository.userBooks.single]);
        expect(await repository.sync(force: true), isTrue);
        expect(
          (await ref.get(const GetOptions(source: Source.server))).exists,
          isFalse,
        );
        await expectLater(
          ref.set({
            'uid': uid,
            'title': 'Stale legacy create',
            'type': 'Manga',
            'chapter': 1,
            'imageUrl': '',
            'linkURL': '',
            'lastRead': null,
          }),
          throwsA(
            isA<FirebaseException>().having(
              (error) => error.code,
              'code',
              'permission-denied',
            ),
          ),
        );

        await repository.save(
          Book(uid: uid, title: 'Cleanup', type: 'Novel', chapter: 0),
        );
        expect(await repository.sync(force: true), isTrue);
        final service = AccountDeletionService(firestore: database);
        await expectLater(
          repository.deleteAccount(
            reauthenticate: () async {},
            requestDeletion: () => service.delete(
              uid,
              deleteIdentity: () async {
                throw StateError(
                  'Simulated interruption before identity deletion',
                );
              },
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
          requestDeletion: () => service.delete(
            uid,
            deleteIdentity: () async {
              await user!.delete();
              identityDeleted = true;
            },
          ),
        );
        expect(repository.userBooks, isEmpty);
        expect(repository.pendingCount, 0);
        expect(repository.deletionPending, isFalse);
      } finally {
        // Cleanup is restricted to the disposable identity, never existing users.
        if (!identityDeleted && user != null && db != null) {
          await db.enableNetwork();
          await AccountDeletionService(firestore: db)
              .delete(user.uid, deleteIdentity: () => user!.delete());
        }
        repository?.dispose();
        await Hive.close();
        if (directory != null) {
          final root = await Directory.systemTemp.resolveSymbolicLinks();
          final resolved = await directory.resolveSymbolicLinks();
          if (!resolved.startsWith('$root${Platform.pathSeparator}') ||
              !resolved
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('reading-tracker-storage-')) {
            throw StateError('Unexpected temporary storage path.');
          }
          await directory.delete(recursive: true);
        }
        for (final app in apps) {
          await FirebaseAuth.instanceFor(app: app).signOut();
          await FirebaseFirestore.instanceFor(app: app).terminate();
          await app.delete();
        }
      }
    },
    skip: !const bool.fromEnvironment('RUN_STAGING_CHECKS'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
