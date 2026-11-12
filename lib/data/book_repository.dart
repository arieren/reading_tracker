import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/book.dart';
import '../models/book_codec.dart';

abstract interface class BookCloud {
  String newId();
  Future<Map<String, Map<String, dynamic>>> fetch(String uid);
  Future<void> write(
    String id,
    Map<String, dynamic> data, {
    Map<String, dynamic>? changes,
  });
  Future<void> delete(String id);
}

class FirestoreBookCloud implements BookCloud {
  CollectionReference<Map<String, dynamic>> get _books =>
      FirebaseFirestore.instance.collection('books');
  @override
  String newId() => _books.doc().id;
  @override
  Future<Map<String, Map<String, dynamic>>> fetch(String uid) async {
    final result = await _books
        .where('uid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    return {for (final doc in result.docs) doc.id: doc.data()};
  }

  @override
  Future<void> write(
    String id,
    Map<String, dynamic> data, {
    Map<String, dynamic>? changes,
  }) {
    // New books and full restoration writes do not need to read a missing
    // document. Owner-only read rules commonly reject that read.
    if (changes == null || data.keys.every(changes.containsKey)) {
      return _books.doc(id).set(data, SetOptions(merge: true));
    }
    return _books.firestore.runTransaction<void>((transaction) async {
      final ref = _books.doc(id);
      final existing = await transaction.get(ref);
      if (existing.exists && existing.data()?['uid'] != data['uid']) {
        throw StateError('This book belongs to another account.');
      }
      transaction.set(
        ref,
        existing.exists ? changes : data,
        SetOptions(merge: true),
      );
    });
  }

  @override
  Future<void> delete(String id) => _books.doc(id).delete();
}

/// Persist intent before changing the local library. Existing Hive fields stay intact.
/// Pending local edits win when uploaded; otherwise confirmed server data wins.
class BookRepository extends ChangeNotifier {
  BookRepository({
    required this.books,
    required this.outbox,
    required this.cloud,
    required this.currentUid,
  });
  static late BookRepository instance;
  final Box<Book> books;
  final Box<dynamic> outbox;
  final BookCloud cloud;
  final String? Function() currentUid;
  Future<void> _tail = Future.value();
  Future<bool>? _syncing;
  String? _syncUid;
  DateTime? _lastSync;
  String? _lastUid;
  int _revision = 0;
  String? lastError;
  bool _deletingAccount = false;
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  int get pendingCount =>
      outbox.values.where((v) => v['uid'] == currentUid()).length;
  List<Book> get userBooks =>
      books.values.where((b) => b.uid == currentUid()).toList();
  void _requireOwner(Book b) {
    if (_deletingAccount) throw StateError('Account deletion is in progress.');
    if (currentUid() == null || b.uid != currentUid()) {
      throw StateError('Please sign in again.');
    }
  }

  Future<void> save(Book b, {Book? original}) => _exclusive(() async {
    _requireOwner(b);
    if (original != null) {
      _requireOwner(original);
      if (!original.isInBox) throw StateError('This book no longer exists.');
    }
    validateBook(b);
    b.id ??= original?.id ?? cloud.newId();
    b.type = normalizeBookType(b.type);
    final data = encodeBook(b);
    final existing =
        original ??
        books.values.where((v) => v.id == b.id && v.uid == b.uid).firstOrNull;
    final previous = existing == null
        ? <String, dynamic>{}
        : encodeBook(existing);
    final pending = outbox.get(b.id);
    final changes = <String, dynamic>{
      if (pending != null && pending['delete'] != true)
        ...Map<String, dynamic>.from(
          (pending['changes'] ?? pending['data']) as Map,
        ),
      for (final entry in data.entries)
        if (existing == null || previous[entry.key] != entry.value)
          entry.key: entry.value,
      'uid': b.uid,
    };
    await outbox.put(b.id, {
      'uid': b.uid,
      'delete': false,
      'data': data,
      'changes': changes,
      'localKey': existing?.key,
      'revision': '${DateTime.now().microsecondsSinceEpoch}-${_revision++}',
    });
    await _apply(b, index: existing == null ? null : {b.id!: existing});
    notifyListeners();
  });
  Future<void> deleteBooks(List<Book> selection) => _exclusive(() async {
    for (final b in selection) {
      _requireOwner(b);
    }
    for (final b in selection) {
      final id = b.id ?? cloud.newId();
      await outbox.put(id, {
        'uid': b.uid,
        'delete': true,
        'localKey': b.key,
        'revision': '${DateTime.now().microsecondsSinceEpoch}-${_revision++}',
      });
      if (b.isInBox) await b.delete();
    }
    notifyListeners();
  });
  Future<void> markRead(Book b, {String? url}) async {
    _requireOwner(b);
    await save(
      Book(
        id: b.id,
        uid: b.uid,
        title: b.title,
        type: b.type,
        chapter: b.chapter,
        imageUrl: b.imageUrl,
        linkURL: url ?? b.linkURL,
        lastRead: DateTime.now(),
      ),
      original: b,
    );
  }

  Future<bool> sync({bool force = false}) {
    if (_deletingAccount) return Future.value(false);
    final uid = currentUid();
    if (uid == null) return Future.value(false);
    if (_syncing != null) {
      if (_syncUid != uid) return _syncing!.then((_) => sync(force: true));
      return _syncing!;
    }
    if (!force &&
        uid == _lastUid &&
        _lastSync != null &&
        pendingCount == 0 &&
        DateTime.now().difference(_lastSync!) < const Duration(seconds: 30)) {
      return Future.value(lastError == null);
    }
    final future = _synchronize(uid);
    _syncUid = uid;
    _syncing = future;
    unawaited(
      future.then((_) {
        _syncing = null;
        _syncUid = null;
        notifyListeners();
      }),
    );
    return future;
  }

  Future<bool> _synchronize(String uid) async {
    try {
      if (currentUid() != uid) return false;
      await recoverLocalChanges(uid: uid);
      await _exclusive(() async {
        for (final b
            in books.values
                .where((b) => b.uid == uid && b.id == null)
                .toList()) {
          final id = cloud.newId();
          await outbox.put(id, {
            'uid': uid,
            'delete': false,
            'data': encodeBook(b),
            'localKey': b.key,
            'revision': 'legacy-${_revision++}',
          });
          b.id = id;
          await b.save();
        }
      });
      final pending = await _exclusive(
        () async =>
            outbox.toMap().entries.where((e) => e.value['uid'] == uid).toList(),
      );
      for (final entry in pending) {
        if (currentUid() != uid) return false;
        final op = Map<String, dynamic>.from(entry.value as Map);
        if (op['delete'] == true) {
          await cloud
              .delete(entry.key as String)
              .timeout(const Duration(seconds: 10));
        } else {
          await cloud
              .write(
                entry.key as String,
                Map<String, dynamic>.from(op['data'] as Map),
                changes: op['changes'] == null
                    ? null
                    : Map<String, dynamic>.from(op['changes'] as Map),
              )
              .timeout(const Duration(seconds: 10));
        }
        await _exclusive(() async {
          final latest = outbox.get(entry.key);
          if (currentUid() != uid ||
              latest == null ||
              latest['revision'] != op['revision']) {
            return;
          }
          if (op['delete'] == true) {
            for (final b
                in books.values
                    .where((b) => b.uid == uid && b.id == entry.key)
                    .toList()) {
              await b.delete();
            }
          } else {
            await _apply(
              decodeBook(
                entry.key as String,
                Map<String, dynamic>.from(op['data'] as Map),
              ),
            );
          }
          await outbox.delete(entry.key);
        });
      }
      final remote = await cloud
          .fetch(uid)
          .timeout(const Duration(seconds: 10));
      if (currentUid() != uid) return false;
      await _exclusive(() async {
        if (currentUid() != uid) return;
        final index = <String, Book>{};
        for (final book in books.values.where((b) => b.uid == uid).toList()) {
          if (book.id != null) {
            if (index.containsKey(book.id)) {
              await book.delete();
            } else {
              index[book.id!] = book;
            }
          }
        }
        for (final entry in remote.entries) {
          if (outbox.containsKey(entry.key)) continue;
          try {
            final b = decodeBook(entry.key, entry.value);
            if (b.uid == uid) await _apply(b, index: index);
          } on Object catch (error) {
            debugPrint('Invalid cloud book: ${error.runtimeType}');
          }
        }
        for (final b in books.values.where((b) => b.uid == uid).toList()) {
          if (b.id != null &&
              !remote.containsKey(b.id) &&
              !outbox.containsKey(b.id)) {
            await b.delete();
          }
        }
      });
      _lastUid = uid;
      _lastSync = DateTime.now();
      lastError = null;
      return true;
    } on Object catch (error) {
      lastError =
          'Cloud sync unavailable. Changes are saved on this device for retry.';
      debugPrint('Book sync failed: ${error.runtimeType}');
      return false;
    }
  }

  Future<void> _apply(Book incoming, {Map<String, Book>? index}) async {
    final matches = index != null
        ? (index[incoming.id] == null ? <Book>[] : [index[incoming.id]!])
        : books.values
              .where((b) => b.uid == incoming.uid && b.id == incoming.id)
              .toList();
    if (matches.isEmpty) {
      await books.add(incoming);
      if (incoming.id != null) index?[incoming.id!] = incoming;
      return;
    }
    final b = matches.first;
    b.id = incoming.id;
    b.title = incoming.title;
    b.type = incoming.type;
    b.chapter = incoming.chapter;
    b.imageUrl = incoming.imageUrl;
    b.linkURL = incoming.linkURL;
    b.lastRead = incoming.lastRead;
    await b.save();
    for (final duplicate in matches.skip(1)) {
      await duplicate.delete();
    }
  }

  /// Replay committed local intent before any network request, including after
  /// interruption between a journal write and a Hive book write.
  Future<void> recoverLocalChanges({String? uid}) => _exclusive(() async {
    for (final entry in outbox.toMap().entries) {
      final op = Map<String, dynamic>.from(entry.value as Map);
      if (uid != null && op['uid'] != uid) continue;
      try {
        if (op['delete'] == true) {
          for (final b
              in books.values
                  .where(
                    (b) =>
                        b.uid == op['uid'] &&
                        (b.id == entry.key ||
                            (op['localKey'] != null &&
                                b.key == op['localKey'])),
                  )
                  .toList()) {
            await b.delete();
          }
        } else {
          final incoming = decodeBook(
            entry.key as String,
            Map<String, dynamic>.from(op['data'] as Map),
          );
          if (incoming.uid != op['uid']) continue;
          if (op['localKey'] != null) {
            final legacy = books.get(op['localKey']);
            if (legacy != null &&
                legacy.uid == incoming.uid &&
                legacy.id == null) {
              legacy.id = incoming.id;
              await legacy.save();
            }
          }
          await _apply(incoming);
        }
      } on Object catch (error) {
        debugPrint('Unable to replay a local change: ${error.runtimeType}');
      }
    }
  });

  /// Journal restoration before deleting remote records. If authentication or
  /// cleanup fails, a later sync restores the retained library instead of losing it.
  Future<void> deleteAccount({
    required Future<void> Function() reauthenticate,
    required Future<void> Function() deleteIdentity,
  }) async {
    if (_deletingAccount) {
      throw StateError('Account deletion is already in progress.');
    }
    final uid = currentUid();
    if (uid == null) throw StateError('Please sign in again.');
    await reauthenticate();
    if (currentUid() != uid) throw StateError('Your account changed.');
    if (!await sync(force: true)) {
      throw StateError('Connect to the cloud before deleting your account.');
    }
    _deletingAccount = true;
    var deletedIdentity = false;
    try {
      if (_syncing != null) await _syncing;
      final backup = await cloud
          .fetch(uid)
          .timeout(const Duration(seconds: 10));
      await _exclusive(() async {
        for (final e in backup.entries) {
          if (e.value['uid'] != uid) throw StateError('Invalid account data.');
          await _apply(decodeBook(e.key, e.value));
          await outbox.put(e.key, {
            'uid': uid,
            'delete': false,
            'data': encodeBook(decodeBook(e.key, e.value)),
            'revision':
                'restore-${DateTime.now().microsecondsSinceEpoch}-${_revision++}',
          });
        }
      });
      for (final id in backup.keys) {
        if (currentUid() != uid) throw StateError('Your account changed.');
        await cloud.delete(id).timeout(const Duration(seconds: 10));
      }
      await deleteIdentity();
      deletedIdentity = true;
      await _exclusive(() async {
        for (final b in books.values.where((b) => b.uid == uid).toList()) {
          await b.delete();
        }
        final keys = outbox
            .toMap()
            .entries
            .where((e) => e.value['uid'] == uid)
            .map((e) => e.key)
            .toList();
        await outbox.deleteAll(keys);
      });
    } finally {
      _deletingAccount = false;
      if (!deletedIdentity && currentUid() == uid) unawaited(sync(force: true));
      notifyListeners();
    }
  }

  static Future<void> initialize() async {
    instance = BookRepository(
      books: Hive.box<Book>('books'),
      outbox: await Hive.openBox<dynamic>('book_outbox_v1'),
      cloud: FirestoreBookCloud(),
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    );
    await instance.recoverLocalChanges();
  }
}
