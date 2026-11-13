import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/book_storage.dart';

/// Spark-compatible cleanup. The server-side job marker locks future writes;
/// reopening the app resumes the same bounded cleanup after reauthentication.
class AccountDeletionService {
  AccountDeletionService({
    FirebaseFirestore? firestore,
    this.userBookStorage = const bool.fromEnvironment('USER_BOOK_STORAGE'),
  }) : _provided = firestore;
  final FirebaseFirestore? _provided;
  final bool userBookStorage;
  FirebaseFirestore get _db => _provided ?? FirebaseFirestore.instance;

  Future<void> delete(
    String uid, {
    required Future<void> Function() deleteIdentity,
  }) async {
    final job = _db.collection('account_deletions').doc(uid);
    final storage = BookStorage(_db, enabled: userBookStorage);
    await _db.runTransaction((transaction) async {
      await storage.readInTransaction(transaction, uid);
      final existing = await transaction.get(job);
      if (!existing.exists) {
        transaction.set(job, {
          'uid': uid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    // The deletion lock prevents migration/copying from starting. Remove retained
    // legacy copies too, so a backup location cannot keep deleted account data.
    await storage.read(uid);
    final layouts = [
      BookStorageLayout.legacy,
      if (userBookStorage) BookStorageLayout.user,
    ];
    for (final selected in layouts) {
      for (final name in ['books', 'book_deletions']) {
        while (true) {
          final page = await storage
              .collection(uid, name, selected)
              .where('uid', isEqualTo: uid)
              .limit(100)
              .get(const GetOptions(source: Source.server));
          if (page.docs.isEmpty) break;
          final batch = _db.batch();
          for (final doc in page.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      }
    }
    await job.update({
      'status': 'data-cleared',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (userBookStorage) {
      await storage.metadata(uid).delete();
      await _db.collection('users').doc(uid).delete();
    }
    await deleteIdentity();
    // The marker stays after Auth deletion: old ID tokens cannot recreate data.
  }
}
