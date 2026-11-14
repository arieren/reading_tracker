import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/reading_page.dart';
import 'package:reading_tracker/services/reading_position.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('read actions reject missing links and encode title search safely', () {
    expect(isReadingUrl(null), isFalse);
    expect(isReadingUrl('  '), isFalse);
    expect(isReadingUrl('javascript:alert(1)'), isFalse);
    expect(isReadingUrl('https://atsu.moe/explore'), isTrue);
    final url = atsuTitleSearch('A&B #1?');
    expect(url.host, 'atsu.moe');
    expect(url.path, '/explore');
    expect(url.queryParameters, {'search': 'A&B #1?'});
  });
  test('account cleanup removes only its own reader checkpoints', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReadingPositionStore();
    for (final uid in ['alice', 'bob']) {
      await store.save(
        uid: uid,
        bookId: 'one',
        url: 'https://reader.example/1',
        offset: 100,
      );
    }
    await store.removeUser('alice');
    expect(
      await store.read(
        uid: 'alice',
        bookId: 'one',
        url: 'https://reader.example/1',
      ),
      isNull,
    );
    expect(
      await store.read(
        uid: 'bob',
        bookId: 'one',
        url: 'https://reader.example/1',
      ),
      100,
    );
  });
  test('chapter labels require whole bounded chapter numbers', () {
    expect(chapterFromPageTitle('Cozy Journey - Chapter 42 | Atsumaru'), 42);
    expect(chapterFromPageTitle('Cozy Journey Ch. 7'), 7);
    expect(chapterFromPageTitle('Episode 0'), 0);
    expect(chapterFromPageTitle('Chapter 12.5'), isNull);
    expect(chapterFromPageTitle('A story from 2026'), isNull);
    expect(chapterFromPageTitle('Chapter 2147483648'), isNull);
  });
  test(
    'automatic bookmarks reject other stories, redirects and navigation pages',
    () {
      bool matches(String url, String title) => pageMatchesBook(
        savedUrl: 'https://reader.example/read/chapter-1',
        currentUrl: url,
        bookTitle: 'Cozy Journey',
        pageTitle: title,
      );
      expect(
        matches(
          'https://reader.example/read/chapter-2',
          'Cozy Journey - Chapter 2 | Atsumaru',
        ),
        isTrue,
      );
      expect(
        matches(
          'https://reader.example/read/chapter-3',
          'Cozy Journey: Another Tale - Chapter 3',
        ),
        isFalse,
      );
      expect(
        matches(
          'https://reader.example/read/chapter-3',
          'Other Story - Chapter 3',
        ),
        isFalse,
      );
      expect(
        matches(
          'https://other.example/read/chapter-2',
          'Cozy Journey - Chapter 2',
        ),
        isFalse,
      );
      expect(
        matches('https://reader.example/', 'Cozy Journey - Chapter 2'),
        isFalse,
      );
      expect(
        matches('https://reader.example/search', 'Cozy Journey - Chapter 2'),
        isFalse,
      );
      expect(
        matches('https://reader.example/read/chapter-2', 'Chapter 2'),
        isFalse,
      );
      expect(
        matches(
          'https://someone:password@reader.example/read/chapter-2',
          'Cozy Journey - Chapter 2',
        ),
        isFalse,
      );
    },
  );
  test('saved page titles remove chapter and known site labels', () {
    expect(
      suggestedStoryTitle('Cozy Journey - Chapter 42 | Atsumaru'),
      'Cozy Journey',
    );
    expect(suggestedStoryTitle('進撃の巨人 - Chapter 7'), '進撃の巨人');
  });
  test('scroll checkpoints survive new instances and stay scoped by account and URL', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingPositionStore().save(
      uid: 'alice',
      bookId: 'one',
      url: 'https://reader.example/1',
      offset: 540,
    );
    final reopened = ReadingPositionStore();
    expect(
      await reopened.read(
        uid: 'alice',
        bookId: 'one',
        url: 'https://reader.example/1',
      ),
      540,
    );
    expect(
      await reopened.read(
        uid: 'bob',
        bookId: 'one',
        url: 'https://reader.example/1',
      ),
      isNull,
    );
    expect(
      await reopened.read(
        uid: 'alice',
        bookId: 'one',
        url: 'https://reader.example/2',
      ),
      isNull,
    );
    await reopened.save(
      uid: 'alice',
      bookId: 'one',
      url: 'https://reader.example/1',
      offset: double.nan,
    );
    expect(
      await reopened.read(
        uid: 'alice',
        bookId: 'one',
        url: 'https://reader.example/1',
      ),
      540,
    );
  });
}
