import 'package:cloud_firestore/cloud_firestore.dart';

class StorageMigrationInProgress implements Exception {}

enum BookStorageLayout { legacy, user }

/// Only an administrator can change routing. Never guess on a failed read.
class BookStorage {
  BookStorage(
    this.db, {
    this.enabled = const bool.fromEnvironment('USER_BOOK_STORAGE'),
  });
  final FirebaseFirestore db;
  final bool enabled;

  DocumentReference<Map<String, dynamic>> metadata(String uid) =>
      db.collection('storage_migrations').doc(uid);

  BookStorageLayout _decode(Map<String, dynamic>? data) {
    if (data == null) return BookStorageLayout.legacy;
    return switch (data['state']) {
      'legacy' => BookStorageLayout.legacy,
      'copying' => throw StorageMigrationInProgress(),
      'ready' => BookStorageLayout.user,
      _ => throw StateError('Unrecognized cloud storage state.'),
    };
  }

  Future<BookStorageLayout> read(String uid) async => enabled
      ? _decode(
          (await metadata(uid).get(const GetOptions(source: Source.server)))
              .data(),
        )
      : BookStorageLayout.legacy;

  Future<BookStorageLayout> readInTransaction(
    Transaction transaction,
    String uid,
  ) async => enabled
      ? _decode((await transaction.get(metadata(uid))).data())
      : BookStorageLayout.legacy;

  CollectionReference<Map<String, dynamic>> collection(
    String uid,
    String name,
    BookStorageLayout layout,
  ) => layout == BookStorageLayout.user
      ? db.collection('users').doc(uid).collection(name)
      : db.collection(name);
}
