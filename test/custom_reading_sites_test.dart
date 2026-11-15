import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/services/reading_link_service.dart';
import 'package:reading_tracker/services/reading_sites.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'custom preferred sites persist and lookup turns off after removal',
    () async {
      final prefs = ReadingSourcePreferences();
      const source = ReadingSource('My source', 'https://reader.example/');
      await prefs.save(source);
      expect(await ReadingSourcePreferences().load(), source);
      final sites = await ReadingSiteStore().load();
      expect(sites.last.name, 'My source');
      await ReadingSiteStore().remove(sites.last);
      expect(await prefs.load(), isNull);
    },
  );
  test(
    'retired provider preferences do not create websites or enable lookup',
    () async {
      SharedPreferences.setMockInitialValues({
        'preferred_reading_source': 'retired-provider',
      });
      expect(await ReadingSourcePreferences().load(), isNull);
      expect(await ReadingSourcePreferences().available(), isEmpty);
    },
  );
  test('new installations start with no websites', () async {
    expect(await ReadingSourcePreferences().available(), isEmpty);
  });
  test(
    'a formerly selected default cannot recreate a missing website',
    () async {
      SharedPreferences.setMockInitialValues({
        'preferred_reading_site':
            '{"name":"Former default","url":"https://reader.example/"}',
      });
      expect(await ReadingSourcePreferences().load(), isNull);
      expect(await ReadingSiteStore().load(), isEmpty);
    },
  );
  test(
    'removing and readding a site does not silently reenable automatic lookup',
    () async {
      const source = ReadingSource('My reader', 'https://reader.example/');
      final preferences = ReadingSourcePreferences();
      await preferences.save(source);
      final store = ReadingSiteStore();
      await store.remove((await store.load()).single);
      await store.add(source.label, source.url);
      expect(await preferences.load(), isNull);
    },
  );
  test('unknown site uses its own search form and validates the exact detail title', () async {
    const source = ReadingSource('Custom', 'https://reader.example/');
    await ReadingSourcePreferences().save(source);
    final urls = <Uri>[];
    final service = ReadingLinkService(
      request: (uri) async {
        urls.add(uri);
        if (uri.path == '/') {
          return http.Response(
            '<form method="get" action="/find"><input type="search" name="query"></form>',
            200,
          );
        }
        if (uri.path == '/find') {
          expect(uri.queryParameters, {'query': 'My Story'});
          return http.Response(
            '<a href="/series/story">My Story</a><a href="/series/sequel">My Story 2</a>',
            200,
          );
        }
        return http.Response(
          '<meta property="og:title" content="My Story"><meta property="og:image" content="/cover.jpg"><dl><dt>Type</dt><dd>Manhwa</dd></dl>',
          200,
        );
      },
    );
    final match = await service.find(
      Book(title: 'My Story', type: 'Manhwa', chapter: 4),
    );
    expect(match!.url, 'https://reader.example/series/story');
    expect(match.image, 'https://reader.example/cover.jpg');
    expect(urls, hasLength(3));
  });
  test(
    'unknown site does not follow cross-site matches or guess a search route',
    () async {
      await ReadingSourcePreferences().save(
        const ReadingSource('Custom', 'https://reader.example/'),
      );
      var count = 0;
      final service = ReadingLinkService(
        request: (_) async {
          count++;
          return http.Response(
            '<a href="https://another.example/story">My Story</a>',
            200,
          );
        },
      );
      expect(
        await service.find(Book(title: 'My Story', type: 'Manhwa', chapter: 4)),
        isNull,
      );
      expect(count, 1);
    },
  );
}
