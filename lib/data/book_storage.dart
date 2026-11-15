import 'package:cloud_firestore/cloud_firestore.dart';

class StorageMigrationInProgress implements Exception {}

enum BookStorageLayout { legacy, user }

/// Only an administrator can change routing. Never guess on a failed read.
class BookStorage {
  BookStorage(
    this.db, {
    this.enabled = const bool.fromEnvironment('USER_BOOK_STORAGE'),
    this.accountDefault = const bool.fromEnvironment(
      'ACCOUNT_STORAGE_DEFAULT',
      defaultValue: true,
    ),
  });
  final FirebaseFirestore db;
  final bool enabled;
  // The matching rules allow this read even while the default is inactive.
  // Version 1.2.0 did not read this administrator-owned setting.
  final bool accountDefault;

  DocumentReference<Map<String, dynamic>> metadata(String uid) =>
      db.collection('storage_migrations').doc(uid);
  DocumentReference<Map<String, dynamic>> get defaults =>
      db.collection('storage_configuration').doc('books');

  BookStorageLayout _decode(Map<String, dynamic>? data) {
    if (data == null) return BookStorageLayout.legacy;
    return switch (data['state']) {
      'legacy' => BookStorageLayout.legacy,
      'copying' => throw StorageMigrationInProgress(),
      'ready' => BookStorageLayout.user,
      _ => throw StateError('Unrecognized cloud storage state.'),
    };
  }

  Future<BookStorageLayout> read(String uid) async {
    if (!enabled) return BookStorageLayout.legacy;
    final checkpoint = await metadata(uid)
        .get(const GetOptions(source: Source.server));
    if (checkpoint.exists || !accountDefault) return _decode(checkpoint.data());
    return _decode(
      (await defaults.get(const GetOptions(source: Source.server))).data(),
    );
  }

  Future<BookStorageLayout> readInTransaction(
    Transaction transaction,
    String uid,
  ) async {
    if (!enabled) return BookStorageLayout.legacy;
    final checkpoint = await transaction.get(metadata(uid));
    if (checkpoint.exists || !accountDefault) return _decode(checkpoint.data());
    return _decode((await transaction.get(defaults)).data());
  }

  CollectionReference<Map<String, dynamic>> collection(
    String uid,
    String name,
    BookStorageLayout layout,
  ) => layout == BookStorageLayout.user
      ? db.collection('users').doc(uid).collection(name)
      : db.collection(name);
}
