import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:hive/hive.dart';

import '../models/book.dart';
import '../models/book_codec.dart';
import 'book_cloud.dart';

export 'book_cloud.dart';

/// Persist intent before changing the local library. Existing Hive fields stay intact.
/// Pending local edits win when uploaded; otherwise confirmed server data wins.
class BookRepository extends ChangeNotifier {
  BookRepository({
    required this.books,
    required this.outbox,
    required this.cloud,
    required this.currentUid,
    this.deletionState,
    this.uploadTimeout = const Duration(seconds: 10),
  });
  static late BookRepository instance;
  final Box<Book> books;
  final Box<dynamic> outbox;
  final BookCloud cloud;
  final String? Function() currentUid;
  final Box<dynamic>? deletionState;
  final Duration uploadTimeout;
  final _pendingDeletions = <String>{};
  bool get deletionPending =>
      currentUid() != null &&
      (_pendingDeletions.contains(currentUid()) ||
          deletionState?.get(currentUid()) == true);
  Future<void> _rememberDeletion(String uid) async {
    _pendingDeletions.add(uid);
    await deletionState?.put(uid, true);
    notifyListeners();
  }

  Future<void> _tail = Future.value();
  Future<bool>? _syncing;
  String? _syncUid;
  DateTime? _lastSync;
  String? _lastUid;
  int _revision = 0;
  String? lastError;
  bool _deletingAccount = false;
  final _uploads = <String, Future<void>>{};
  final _writeTails = <String, Future<void>>{};

  List<MapEntry<String, Map<String, dynamic>>> get conflicts => [
    for (final e in outbox.toMap().entries)
      if (e.value['uid'] == currentUid() && e.value['conflict'] != null)
        MapEntry(e.key as String, Map<String, dynamic>.from(e.value as Map)),
  ];

  Future<void> resolveConflict(String id, {required bool keepLocal}) =>
      _exclusive(() async {
        final value = outbox.get(id);
        if (value == null ||
            value['uid'] != currentUid() ||
            value['conflict'] == null) {
          return;
        }
        final op = Map<String, dynamic>.from(value as Map);
        final remote = Map<String, dynamic>.from(
          op['conflict']['remote'] as Map,
        );
        if (keepLocal) {
          op['base'] = remote;
          op['revision'] = cloud.newId();
          op.remove('conflict');
          await outbox.put(id, op);
        } else {
          final remaining = Map<String, dynamic>.from(
            (op['changes'] ?? op['data']) as Map,
          );
          for (final field in op['conflict']['fields'] as List) {
            remaining.remove(field);
          }
          if (remaining.keys.every((key) => key == 'uid')) {
            await _apply(decodeBook(id, remote));
            await outbox.delete(id);
          } else {
            op['base'] = remote;
            op['changes'] = remaining;
            op['data'] = {...remote, ...remaining};
            op['create'] = false;
            op['revision'] = cloud.newId();
            op.remove('conflict');
            await outbox.put(id, op);
            await _apply(
              decodeBook(id, Map<String, dynamic>.from(op['data'] as Map)),
            );
          }
        }
        lastError = null;
        notifyListeners();
      });
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
    if (_deletingAccount || deletionPending) {
      throw StateError('Resume account deletion before making changes.');
    }
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
      'base': pending?['base'] ?? previous,
      'create': pending?['create'] ?? (existing == null || existing.id == null),
      if (pending?['conflict'] != null) 'conflict': pending['conflict'],
      'localKey': existing?.key,
      'revision': cloud.newId(),
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
        'revision': cloud.newId(),
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
    if (_deletingAccount || deletionPending) return Future.value(false);
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
        if (op['conflict'] != null) continue;
        final id = entry.key as String;
        final operation = '$id/${op['revision']}';
        var upload = _uploads[operation];
        if (upload == null) {
          // A timed-out Future keeps ownership of its acknowledgment. Reusing
          // it prevents duplicate writes; later edits wait for the old write.
          final previous = _writeTails[id] ?? Future<void>.value();
          upload = previous.then((_) async {
            final latest = await _exclusive(() async {
              final value = outbox.get(id);
              return value == null
                  ? null
                  : Map<String, dynamic>.from(value as Map);
            });
            if (latest == null ||
                latest['uid'] != uid ||
                latest['revision'] != op['revision']) {
              return;
            }
            await _upload(id, latest, uid);
          });
          _uploads[operation] = upload;
          _writeTails[id] = upload.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          unawaited(
            upload.then(
              (_) => _uploads.remove(operation),
              onError: (Object _, StackTrace _) {
                _uploads.remove(operation);
              },
            ),
          );
        }
        await upload.timeout(uploadTimeout);
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
              outbox.get(b.id)?['conflict'] != null) {
            await outbox.delete(b.id);
          }
          if (b.id != null &&
              !remote.containsKey(b.id) &&
              !outbox.containsKey(b.id)) {
            await b.delete();
          }
        }
      });
      _lastUid = uid;
      _lastSync = DateTime.now();
      lastError = conflicts.isEmpty ? null : 'Some books changed on another device. Review conflicts to finish syncing.';
      return true;
    } on StorageMigrationInProgress {
      lastError = 'Cloud storage is being upgraded. Changes are saved on this device and will sync when it finishes.';
      return false;
    } on AccountDeletionPendingException {
      await _rememberDeletion(uid);
      lastError = 'Account deletion is paused. Reconnect and resume deletion.';
      return false;
    } on Object catch (error) {
      lastError =
          'Cloud sync unavailable. Changes are saved on this device for retry.';
      debugPrint('Book sync failed: ${error.runtimeType}');
      return false;
    }
  }

  Future<void> _upload(String id, Map<String, dynamic> op, String uid) async {
    Map<String, dynamic>? acknowledged;
    try {
      if (op['delete'] == true) {
        await cloud.delete(id, uid: uid);
      } else {
        acknowledged = await cloud.write(
          id,
          Map<String, dynamic>.from(op['data'] as Map),
          changes: op['changes'] == null
              ? null
              : Map<String, dynamic>.from(op['changes'] as Map),
          base: op['base'] == null
              ? null
              : Map<String, dynamic>.from(op['base'] as Map),
          operationId: op['revision'] as String,
          allowCreate: op['create'] != false,
        );
      }
    } on DeletedBookException {
      await _exclusive(() async {
        for (final book
            in books.values.where((b) => b.uid == uid && b.id == id).toList()) {
          await book.delete();
        }
        final latest = outbox.get(id);
        if (latest?['uid'] == uid) await outbox.delete(id);
        notifyListeners();
      });
      return;
    } on BookConflictException catch (error) {
      await _exclusive(() async {
        final latest = outbox.get(id);
        if (latest == null ||
            latest['uid'] != uid ||
            latest['delete'] == true) {
          return;
        }
        await outbox.put(id, {
          ...Map<String, dynamic>.from(latest as Map),
          'conflict': {'remote': error.remote, 'fields': error.fields},
        });
        notifyListeners();
      });
      return;
    }
    await _exclusive(() async {
      final value = outbox.get(id);
      if (value == null || value['uid'] != uid) return;
      final latest = Map<String, dynamic>.from(value as Map);
      if (latest['revision'] != op['revision']) {
        if (latest['delete'] != true && acknowledged != null) {
          final remaining = Map<String, dynamic>.from(
            (latest['changes'] ?? latest['data']) as Map,
          );
          for (final key in remaining.keys.toList()) {
            if (key != 'uid' && remaining[key] == acknowledged[key]) {
              remaining.remove(key);
            }
          }
          latest['base'] = acknowledged;
          latest['changes'] = remaining;
          latest['create'] = false;
          latest['data'] = {...acknowledged, ...remaining};
          // Only journal primitive fields; acknowledgments never contain SDK sentinels.
          await outbox.put(id, latest);
        }
        return;
      }
      if (op['delete'] == true) {
        for (final book
            in books.values.where((b) => b.uid == uid && b.id == id).toList()) {
          await book.delete();
        }
      } else {
        await _apply(decodeBook(id, acknowledged!));
      }
      await outbox.delete(id);
      notifyListeners();
    });
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

  /// Intent survives restarts. Spark cleanup resumes in the client; it never
  /// claims completion before Auth confirms deletion.
  Future<void> deleteAccount({
    required Future<void> Function() reauthenticate,
    required Future<void> Function() requestDeletion,
  }) async {
    if (_deletingAccount) {
      throw StateError('Account deletion is already in progress.');
    }
    final uid = currentUid();
    if (uid == null) throw StateError('Please sign in again.');
    await reauthenticate();
    if (currentUid() != uid) throw StateError('Your account changed.');
    if (!deletionPending &&
        (!await sync(force: true) || conflicts.isNotEmpty)) {
      throw StateError(
        'Finish syncing and resolve conflicts before deleting your account.',
      );
    }
    _deletingAccount = true;
    try {
      await _rememberDeletion(uid);
      await requestDeletion();
      await _exclusive(() async {
        for (final b in books.values.where((b) => b.uid == uid).toList()) {
          await b.delete();
        }
        await outbox.deleteAll(
          outbox
              .toMap()
              .entries
              .where((e) => e.value['uid'] == uid)
              .map((e) => e.key)
              .toList(),
        );
        _pendingDeletions.remove(uid);
        await deletionState?.delete(uid);
      });
    } finally {
      _deletingAccount = false;
      notifyListeners();
    }
  }

  static Future<void> initialize() async {
    instance = BookRepository(
      books: Hive.box<Book>('books'),
      outbox: await Hive.openBox<dynamic>('book_outbox_v1'),
      cloud: FirestoreBookCloud(
        legacyCompatibility: const bool.fromEnvironment(
          'LEGACY_DATABASE_COMPATIBILITY',
          defaultValue: appFlavor != 'staging',
        ),
      ),
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      deletionState: await Hive.openBox<dynamic>('account_deletion_v1'),
    );
    await instance.recoverLocalChanges();
  }
}
