import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:reading_tracker/data/book_repository.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/models/book_codec.dart';
import 'package:reading_tracker/services/import_service.dart';

class MemoryCloud implements BookCloud {
  final records = <String, Map<String, dynamic>>{};
  bool offline = false;
  int sequence = 0;
  Completer<void>? writing;
  Completer<void>? writeStarted;
  Completer<void>? fetching;
  @override
  String newId() => 'book-${sequence++}';
  void check() {
    if (offline) throw StateError('offline');
  }

  @override
  Future<void> write(
    String id,
    Map<String, dynamic> data, {
    Map<String, dynamic>? changes,
  }) async {
    check();
    final copy = Map<String, dynamic>.from(
      records.containsKey(id) ? (changes ?? data) : data,
    );
    if (writeStarted != null && !writeStarted!.isCompleted) {
      writeStarted!.complete();
    }
    if (writing != null) await writing!.future;
    records[id] = {...?records[id], ...copy};
  }

  @override
  Future<void> delete(String id) async {
    check();
    records.remove(id);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> fetch(String uid) async {
    check();
    if (fetching != null) await fetching!.future;
    return {
      for (final e in records.entries)
        if (e.value['uid'] == uid) e.key: Map.of(e.value),
    };
  }
}

void main() {
  late Directory directory;
  late Box<Book> books;
  late Box<dynamic> outbox;
  late MemoryCloud cloud;
  late BookRepository repository;
  String? uid;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reading_tracker_test_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
    books = await Hive.openBox<Book>('books');
    outbox = await Hive.openBox<dynamic>('outbox');
    uid = 'alice';
    cloud = MemoryCloud();
    repository = BookRepository(
      books: books,
      outbox: outbox,
      cloud: cloud,
      currentUid: () => uid,
    );
  });
  tearDown(() async {
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Book draft({String title = 'Story', int chapter = 1}) =>
      Book(title: title, chapter: chapter, type: 'Manga', uid: uid);

  test('offline save survives restart and retries with the same ID', () async {
    cloud.offline = true;
    final book = draft();
    await repository.save(book);
    expect(await repository.sync(force: true), isFalse);
    final id = book.id;
    await books.close();
    await outbox.close();
    books = await Hive.openBox<Book>('books');
    outbox = await Hive.openBox<dynamic>('outbox');
    repository = BookRepository(
      books: books,
      outbox: outbox,
      cloud: cloud,
      currentUid: () => uid,
    );
    cloud.offline = false;
    expect(await repository.sync(force: true), isTrue);
    expect(cloud.records.keys, [id]);
    expect(books.length, 1);
    expect(outbox.isEmpty, isTrue);
  });
  test(
    'detached editor updates existing record instead of duplicating it',
    () async {
      final book = draft();
      await repository.save(book);
      final edited = draft(title: 'Edited')..id = book.id;
      await repository.save(edited);
      expect(books.length, 1);
      expect(books.values.single.title, 'Edited');
    },
  );
  test(
    'offline deletion remains deleted until its cloud deletion succeeds',
    () async {
      final book = draft();
      await repository.save(book);
      await repository.sync(force: true);
      cloud.offline = true;
      await repository.deleteBooks([books.values.single]);
      expect(await repository.sync(force: true), isFalse);
      expect(books.isEmpty, isTrue);
      expect(repository.pendingCount, 1);
      cloud.offline = false;
      await repository.sync(force: true);
      expect(cloud.records.isEmpty, isTrue);
      expect(books.isEmpty, isTrue);
    },
  );
  test('failed remote query cannot delete local books', () async {
    final book = draft()..id = 'existing';
    await books.add(book);
    cloud.offline = true;
    await repository.sync(force: true);
    expect(books.length, 1);
  });
  test('server-confirmed deletion removes a synced local record', () async {
    await repository.save(draft());
    await repository.sync(force: true);
    cloud.records.clear();
    await repository.sync(force: true);
    expect(books.isEmpty, isTrue);
  });
  test('pending newer edit survives an older write finishing', () async {
    final original = draft();
    await repository.save(original);
    cloud.writing = Completer<void>();
    cloud.writeStarted = Completer<void>();
    final sync = repository.sync(force: true);
    await cloud.writeStarted!.future;
    await repository.save(draft(chapter: 9)..id = original.id);
    cloud.writing!.complete();
    await sync;
    expect(books.values.single.chapter, 9);
    expect(repository.pendingCount, 1);
    cloud.writing = null;
    await repository.sync(force: true);
    expect(cloud.records.values.single['chapter'], 9);
  });
  test('account switch discards old-account query results', () async {
    cloud.records['remote'] = encodeBook(draft());
    cloud.fetching = Completer<void>();
    final sync = repository.sync(force: true);
    await Future<void>.delayed(Duration.zero);
    uid = 'bob';
    cloud.fetching!.complete();
    await sync;
    expect(books.isEmpty, isTrue);
  });
  test('ownership checks reject cross-account writes and deletes', () async {
    final book = draft();
    await repository.save(book);
    uid = 'bob';
    expect(repository.save(book), throwsStateError);
    expect(repository.deleteBooks([book]), throwsStateError);
  });
  test(
    'legacy local-only books upload without inventing reading time',
    () async {
      await books.add(draft());
      await repository.sync(force: true);
      expect(books.values.single.id, isNotNull);
      expect(books.values.single.lastRead, isNull);
    },
  );
  test('failed reauthentication never deletes a book', () async {
    await repository.save(draft());
    await repository.sync(force: true);
    await expectLater(
      repository.deleteAccount(
        reauthenticate: () async => throw StateError('bad password'),
        deleteIdentity: () async {},
      ),
      throwsStateError,
    );
    expect(cloud.records.length, 1);
    expect(books.length, 1);
  });
  test('failed identity deletion retains recoverable local books', () async {
    await repository.save(draft());
    await repository.sync(force: true);
    await expectLater(
      repository.deleteAccount(
        reauthenticate: () async {},
        deleteIdentity: () async => throw StateError('recent login needed'),
      ),
      throwsStateError,
    );
    await repository.sync(force: true);
    expect(books.length, 1);
    expect(cloud.records.length, 1);
  });
  test('successful account deletion clears only that account', () async {
    await repository.save(draft());
    await repository.sync(force: true);
    await books.add(
      Book(title: 'Other', type: 'Novel', chapter: 0, uid: 'bob', id: 'other'),
    );
    await repository.deleteAccount(
      reauthenticate: () async {},
      deleteIdentity: () async {
        uid = null;
      },
    );
    expect(books.values.single.uid, 'bob');
    expect(cloud.records.isEmpty, isTrue);
    expect(outbox.isEmpty, isTrue);
  });
  test('manual cover is retained by codec and local persistence', () async {
    final book = draft()..imageUrl = 'https://example.com/cover.png';
    await repository.save(book);
    await repository.sync(force: true);
    expect(books.values.single.imageUrl, book.imageUrl);
    expect(cloud.records.values.single['imageUrl'], book.imageUrl);
  });
  test(
    'malformed remote records do not block valid records or erase legacy row',
    () async {
      await books.add(draft()..id = 'bad');
      cloud.records['bad'] = {'uid': 'alice', 'chapter': 'invalid'};
      cloud.records['good'] = encodeBook(draft(title: 'Valid'));
      await repository.sync(force: true);
      expect(books.length, 2);
    },
  );
  test(
    'interrupted local add is recovered even while cloud is offline',
    () async {
      final data = encodeBook(draft());
      await outbox.put('interrupted', {
        'uid': 'alice',
        'delete': false,
        'data': data,
        'revision': '1',
      });
      cloud.offline = true;
      await repository.recoverLocalChanges();
      expect(books.values.single.id, 'interrupted');
      expect(await repository.sync(force: true), isFalse);
      expect(books.length, 1);
    },
  );
  test('interrupted local delete is replayed before cloud access', () async {
    await books.add(draft()..id = 'interrupted');
    await outbox.put('interrupted', {
      'uid': 'alice',
      'delete': true,
      'revision': '1',
    });
    cloud.offline = true;
    await repository.recoverLocalChanges();
    expect(books.isEmpty, isTrue);
    expect(repository.pendingCount, 1);
  });
  test(
    'interrupted legacy migration preserves its original Hive row',
    () async {
      final legacy = draft();
      final key = await books.add(legacy);
      await outbox.put('migrated', {
        'uid': 'alice',
        'delete': false,
        'data': encodeBook(legacy),
        'localKey': key,
        'revision': '1',
      });
      await repository.recoverLocalChanges();
      expect(books.length, 1);
      expect(books.get(key)!.id, 'migrated');
      await repository.sync(force: true);
      expect(cloud.records.length, 1);
    },
  );
  test('title-only edit preserves a newer remote chapter', () async {
    final original = draft();
    await repository.save(original);
    await repository.sync(force: true);
    cloud.records[original.id]!['chapter'] = 12;
    await repository.save(draft(title: 'Renamed')..id = original.id);
    await repository.sync(force: true);
    expect(books.values.single.title, 'Renamed');
    expect(books.values.single.chapter, 12);
  });
  test('multiple unsynced edits retain all changed fields', () async {
    final original = draft();
    await repository.save(original);
    await repository.sync(force: true);
    await repository.save(draft(title: 'Renamed')..id = original.id);
    await repository.save(
      draft(title: 'Renamed', chapter: 4)..id = original.id,
    );
    await repository.sync(force: true);
    expect(cloud.records[original.id]!['title'], 'Renamed');
    expect(cloud.records[original.id]!['chapter'], 4);
  });
  test('invalid edit cannot assign an ID to an unsynced legacy row', () async {
    final legacy = draft();
    await books.add(legacy);
    await expectLater(
      repository.save(draft(chapter: -1), original: legacy),
      throwsFormatException,
    );
    expect(legacy.id, isNull);
    expect(books.length, 1);
    expect(outbox.isEmpty, isTrue);
  });
  test('editing a legacy row keeps its original Hive key', () async {
    final legacy = draft();
    final key = await books.add(legacy);
    await repository.save(draft(title: 'Edited legacy'), original: legacy);
    expect(books.length, 1);
    expect(books.get(key)!.title, 'Edited legacy');
    expect(books.get(key)!.id, isNotNull);
  });
  test(
    'interrupted deletion can locate a legacy row by its Hive key',
    () async {
      final legacy = draft();
      final key = await books.add(legacy);
      await outbox.put('deleted-legacy', {
        'uid': 'alice',
        'delete': true,
        'localKey': key,
        'revision': '1',
      });
      await repository.recoverLocalChanges();
      expect(books.isEmpty, isTrue);
      expect(outbox.length, 1);
    },
  );
  test('confirmed import match preserves cover and content type', () async {
    await BookImportService(repository).import([
      const ImportEntry(
        'Matched Story',
        7,
        type: 'Manhwa',
        imageUrl: 'https://example.com/cover.png',
      ),
    ], 'alice');
    expect(books.values.single.type, 'Manhwa');
    expect(books.values.single.imageUrl, 'https://example.com/cover.png');
  });
  test(
    'import preserves case, parses chapters and skips duplicate retry',
    () async {
      final entries = parseBookImport(
        'Tokyo Ghoul finished chapter 7\nDune not started',
      );
      expect(entries.first.title, 'Tokyo Ghoul');
      expect(entries.first.chapter, 7);
      expect(entries.last.chapter, 0);
      final importer = BookImportService(repository);
      expect(await importer.import(entries, 'alice'), 2);
      expect(await importer.import(entries, 'alice'), 0);
      expect(() => parseBookImport('Story -1'), throwsFormatException);
      expect(() => parseBookImport('Story finished'), throwsFormatException);
    },
  );
}
