import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/services/reading_link_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Book book({String type = 'Manhwa', String? link}) =>
      Book(title: 'Moon Garden', type: type, chapter: 4, linkURL: link);
  Future<void> select() => ReadingSourcePreferences().save(
    const ReadingSource('My reader', 'https://reader.example/'),
  );
  ReadingLinkService fixture({
    String results = '<a href="/work/moon">Moon Garden</a>',
    String details = '<h1>Moon Garden</h1><meta property="book:type" content="Manhwa"><meta property="og:image" content="/cover.jpg">',
  }) => ReadingLinkService(
    request: (uri) async {
      if (uri.path == '/') {
        return http.Response(
          '<form action="/find" method="get"><input type="search" name="query"></form>',
          200,
        );
      }
      if (uri.path == '/find') {
        expect(uri.queryParameters['query'], 'Moon Garden');
        return http.Response(results, 200);
      }
      return http.Response(details, 200);
    },
  );
  test('lookup is off until a user explicitly configures a site', () async {
    expect(await ReadingSourcePreferences().load(), isNull);
    final lookup = ReadingLinkService(
      request: (_) async {
        fail('No default network requests');
      },
    );
    expect(await lookup.find(book()), isNull);
  });
  test('user selection persists and can be disabled', () async {
    await select();
    expect(
      (await ReadingSourcePreferences().load())!.url,
      'https://reader.example/',
    );
    await ReadingSourcePreferences().save(null);
    expect(await ReadingSourcePreferences().load(), isNull);
  });
  test(
    'exact destination metadata supplies a reading link and cover',
    () async {
      await select();
      final match = await fixture().find(book());
      expect(match!.url, 'https://reader.example/work/moon');
      expect(match.image, 'https://reader.example/cover.jpg');
    },
  );
  test('ambiguous titles do not choose a result', () async {
    await select();
    expect(
      await fixture(
        results: '<a href="/one">Moon Garden</a><a href="/two">Moon Garden</a>',
      ).find(book()),
      isNull,
    );
  });
  test(
    'fuzzy results and conflicting destination titles remain blank',
    () async {
      await select();
      expect(
        await fixture(results: '<a href="/one">Moon Garden 2</a>').find(book()),
        isNull,
      );
      expect(
        await fixture(details: '<h1>Different Story</h1>').find(book()),
        isNull,
      );
    },
  );
  test('novel and comic metadata are kept separate', () async {
    await select();
    expect(await fixture().find(book(type: 'Light Novel')), isNull);
    expect(
      (await fixture(
        details: '<h1>Moon Garden</h1><meta property="book:type" content="Light Novel">',
      ).find(book(type: 'Light Novel')))!.url,
      'https://reader.example/work/moon',
    );
  });
  test('regular novels and supplied links do not trigger search', () async {
    await select();
    final lookup = ReadingLinkService(
      request: (_) async {
        fail('Unexpected request');
      },
    );
    expect(await lookup.find(book(type: 'Novel')), isNull);
    expect(
      await lookup.find(book(link: 'https://chosen.example/story')),
      isNull,
    );
  });
  test('access rejection never falls back to another website', () async {
    await select();
    final lookup = ReadingLinkService(
      request: (uri) async {
        expect(uri.host, 'reader.example');
        return http.Response('Forbidden', 403);
      },
    );
    await expectLater(
      lookup.find(book()),
      throwsA(isA<ReadingSourceException>()),
    );
  });
  test('POST and password forms are not submitted', () async {
    await select();
    var requests = 0;
    final lookup = ReadingLinkService(
      request: (_) async {
        requests++;
        return http.Response(
          '<form method="post" action="/private"><input name="q"></form><form action="/login"><input name="q"><input type="password"></form>',
          200,
        );
      },
    );
    expect(await lookup.find(book()), isNull);
    expect(requests, 1);
  });
}
