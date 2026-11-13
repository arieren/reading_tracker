import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/book_codec.dart';
import 'book_storage.dart';
export 'book_storage.dart' show StorageMigrationInProgress;

class DeletedBookException implements Exception {}

class AccountDeletionPendingException implements Exception {}

class BookConflictException implements Exception {
  BookConflictException(this.remote, this.fields);
  final Map<String, dynamic> remote;
  final List<String> fields;
}

abstract interface class BookCloud {
  String newId();
  Future<Map<String, Map<String, dynamic>>> fetch(String uid);
  Future<Map<String, dynamic>> write(
    String id,
    Map<String, dynamic> data, {
    Map<String, dynamic>? changes,
    Map<String, dynamic>? base,
    String? operationId,
    bool allowCreate = true,
  });
  Future<void> delete(String id, {required String uid});
}

/// Server transactions are used for every mutation. Hive is the durable offline
/// queue; there are no independently queued Firestore set/delete operations.
class FirestoreBookCloud implements BookCloud {
  FirestoreBookCloud({
    FirebaseFirestore? firestore,
    this.legacyCompatibility = false,
    this.userBookStorage = const bool.fromEnvironment('USER_BOOK_STORAGE'),
  }) : _provided = firestore;
  final bool legacyCompatibility;
  final bool userBookStorage;
  final FirebaseFirestore? _provided;
  FirebaseFirestore get _db => _provided ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _books =>
      _db.collection('books');
  BookStorage get _storage => BookStorage(_db, enabled: userBookStorage);
  BookStorageLayout? _cachedLayout;
  String? _cachedUid;
  final _snapshot = <String, Map<String, dynamic>>{};
  Timestamp? _bookCursor, _deletionCursor;
  DateTime? _lastFullRead;
  int _cacheRevision = 0;

  @override
  String newId() => _books.doc().id;

  @override
  Future<Map<String, Map<String, dynamic>>> fetch(String uid) async {
    final deletion = await _db
        .collection('account_deletions')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (deletion.exists) throw AccountDeletionPendingException();
    final layout = await _storage.read(uid);
    final requestedRevision = _cacheRevision;
    final full =
        legacyCompatibility ||
        _cachedLayout != layout ||
        _cachedUid != uid ||
        _lastFullRead == null ||
        DateTime.now().difference(_lastFullRead!) > const Duration(minutes: 10);
    if (_cachedUid != uid || _cachedLayout != layout) {
      _snapshot.clear();
      _bookCursor = null;
      _deletionCursor = null;
    }
    Query<Map<String, dynamic>> books = _storage
        .collection(uid, 'books', layout)
        .where('uid', isEqualTo: uid);
    Query<Map<String, dynamic>> deletions = _storage
        .collection(uid, 'book_deletions', layout)
        .where('uid', isEqualTo: uid);
    if (!full && _bookCursor != null) {
      books = books.where('updatedAt', isGreaterThanOrEqualTo: _bookCursor);
    }
    if (!full && _deletionCursor != null) {
      deletions = deletions.where(
        'deletedAt',
        isGreaterThanOrEqualTo: _deletionCursor,
      );
    }
    // Separate cursors prevent a later deletion query from advancing past a
    // concurrent book update. Equal timestamps are deliberately re-read.
    final results = await Future.wait([
      books.get(const GetOptions(source: Source.server)),
      deletions.get(const GetOptions(source: Source.server)),
    ]);
    if (requestedRevision != _cacheRevision ||
        layout != await _storage.read(uid)) {
      _lastFullRead = null;
      return fetch(uid);
    }
    final next = full ? <String, Map<String, dynamic>>{} : Map.of(_snapshot);
    for (final doc in results[0].docs) {
      next[doc.id] = normalizeCloudBook(doc.data());
      final time = doc.data()['updatedAt'];
      if (time is Timestamp &&
          (_bookCursor == null || time.compareTo(_bookCursor!) > 0)) {
        _bookCursor = time;
      }
    }
    for (final doc in results[1].docs) {
      next.remove(doc.id);
      final time = doc.data()['deletedAt'];
      if (time is Timestamp &&
          (_deletionCursor == null || time.compareTo(_deletionCursor!) > 0)) {
        _deletionCursor = time;
      }
    }
    _snapshot
      ..clear()
      ..addAll(next);
    _cachedUid = uid;
    _cachedLayout = layout;
    if (full) _lastFullRead = DateTime.now();
    return {for (final e in next.entries) e.key: Map.of(e.value)};
  }

  @override
  Future<Map<String, dynamic>> write(
    String id,
    Map<String, dynamic> data, {
    Map<String, dynamic>? changes,
    Map<String, dynamic>? base,
    String? operationId,
    bool allowCreate = true,
  }) async {
    final patch = changes ?? data;
    final result = await _db.runTransaction<Map<String, dynamic>>((
      transaction,
    ) async {
      final accountDeletion = await transaction.get(
        _db.collection('account_deletions').doc(data['uid'] as String),
      );
      if (accountDeletion.exists) throw AccountDeletionPendingException();
      final uid = data['uid'] as String;
      final layout = await _storage.readInTransaction(transaction, uid);
      final ref = _storage.collection(uid, 'books', layout).doc(id);
      final deleted = await transaction.get(
        _storage.collection(uid, 'book_deletions', layout).doc(id),
      );
      final snapshot = await transaction.get(ref);
      if (deleted.exists || (!snapshot.exists && !allowCreate)) {
        throw DeletedBookException();
      }
      final remote = snapshot.exists
          ? normalizeCloudBook(snapshot.data()!)
          : null;
      if (remote != null && remote['uid'] != data['uid']) {
        throw StateError('This book belongs to another account.');
      }
      if (remote != null &&
          operationId != null &&
          remote['lastOperationId'] == operationId) {
        return remote;
      }
      if (remote != null && base != null) {
        final conflicts = [
          for (final key in patch.keys)
            if (key != 'uid' &&
                remote[key] != base[key] &&
                remote[key] != patch[key])
              key,
        ];
        if (conflicts.isNotEmpty) {
          throw BookConflictException(remote, conflicts);
        }
      }
      final updated = <String, dynamic>{
        ...?remote,
        ...(remote == null ? data : patch),
        'revision': ((remote?['revision'] as num?)?.toInt() ?? 0) + 1,
        'lastOperationId': operationId ?? newId(),
      };
      transaction.set(ref, {
        ...cloudBookFields(updated, legacyLastRead: legacyCompatibility),
        'revision': updated['revision'],
        'lastOperationId': updated['lastOperationId'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return updated;
    });
    // Include our own writes even if an inclusive incremental query returns no
    // new rows. A subsequent fetch obtains the authoritative server timestamp.
    _cacheRevision++;
    if (_cachedUid == data['uid']) _snapshot[id] = result;
    return result;
  }

  @override
  Future<void> delete(String id, {required String uid}) async {
    await _db.runTransaction((transaction) async {
      final accountDeletion = await transaction.get(
        _db.collection('account_deletions').doc(uid),
      );
      if (accountDeletion.exists) throw AccountDeletionPendingException();
      final layout = await _storage.readInTransaction(transaction, uid);
      final ref = _storage.collection(uid, 'books', layout).doc(id);
      final marker = _storage.collection(uid, 'book_deletions', layout).doc(id);
      final existing = await transaction.get(ref);
      final deleted = await transaction.get(marker);
      if (deleted.exists) {
        if (deleted.data()?['uid'] != uid) throw StateError('Invalid owner.');
        return;
      }
      if (existing.exists && existing.data()?['uid'] != uid) {
        throw StateError('Invalid owner.');
      }
      transaction.set(marker, {
        'uid': uid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      if (existing.exists) transaction.delete(ref);
    });
    _cacheRevision++;
    if (_cachedUid == uid) _snapshot.remove(id);
  }
}
