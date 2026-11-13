import 'package:cloud_firestore/cloud_firestore.dart';

/// Spark-compatible cleanup. The server-side job marker locks future writes;
/// reopening the app resumes the same bounded cleanup after reauthentication.
class AccountDeletionService {
  AccountDeletionService({FirebaseFirestore? firestore})
    : _provided = firestore;
  final FirebaseFirestore? _provided;
  FirebaseFirestore get _db => _provided ?? FirebaseFirestore.instance;

  Future<void> delete(
    String uid, {
    required Future<void> Function() deleteIdentity,
  }) async {
    final job = _db.collection('account_deletions').doc(uid);
    await _db.runTransaction((transaction) async {
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
    for (final name in ['books', 'book_deletions']) {
      while (true) {
        final page = await _db
            .collection(name)
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
    await job.update({
      'status': 'data-cleared',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await deleteIdentity();
    // The marker stays after Auth deletion: old ID tokens cannot recreate data.
  }
}
