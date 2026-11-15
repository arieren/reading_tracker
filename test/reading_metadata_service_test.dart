import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reading_tracker/services/reading_metadata.dart';

void main() {
  test('reads only the user supplied page using standard metadata', () async {
    final service = ReadingMetadataService(
      request: (uri) async {
        expect(uri.toString(), 'https://reader.example/chapter/35');
        return http.Response(
          '<title>Moon Garden - Chapter 35</title><meta property="book:type" content="Manhwa"><meta property="og:image" content="/covers/moon.jpg">',
          200,
        );
      },
    );
    final page = await service.complete(
      'https://reader.example/chapter/35',
      const ReadingPageMetadata(title: 'Moon Garden', chapter: 35),
    );
    expect(page.title, 'Moon Garden');
    expect(page.chapter, 35);
    expect(page.type, 'Manhwa');
    expect(page.image, 'https://reader.example/covers/moon.jpg');
  });
  test('relative cover metadata does not depend on attribute order', () async {
    final service = ReadingMetadataService(
      request: (_) async => http.Response(
        '<h1>Book</h1><meta content="/covers/book.jpg" property="og:image">',
        200,
      ),
    );
    final page = await service.complete(
      'https://reader.example/series/book',
      const ReadingPageMetadata(title: 'Book'),
    );
    expect(page.image, 'https://reader.example/covers/book.jpg');
  });
  test(
    'mismatched data and offline lookups preserve existing details',
    () async {
      const page = ReadingPageMetadata(title: 'Moon Garden', chapter: 35);
      final wrong = ReadingMetadataService(
        request: (_) async => http.Response(
          '<h1>Other Story</h1><meta property="og:image" content="/other.jpg">',
          200,
        ),
      );
      expect(
        await wrong.complete('https://reader.example/chapter/35', page),
        same(page),
      );
      final offline = ReadingMetadataService(
        request: (_) async => throw http.ClientException('Offline'),
      );
      expect(
        await offline.complete('https://reader.example/chapter/35', page),
        same(page),
      );
    },
  );
  test(
    'complete pages make no extra request and keep the chosen cover',
    () async {
      final service = ReadingMetadataService(
        request: (_) async {
          fail('Unexpected request');
        },
      );
      const page = ReadingPageMetadata(
        title: 'Story',
        type: 'Manhwa',
        chapter: 1,
        image: 'https://reader.example/chosen.jpg',
      );
      expect(
        await service.complete('https://reader.example/story', page),
        same(page),
      );
    },
  );
  test(
    'missing metadata remains unknown rather than calling a catalog API',
    () async {
      var requests = 0;
      final service = ReadingMetadataService(
        request: (uri) async {
          requests++;
          expect(uri.path, '/story');
          return http.Response('<html></html>', 200);
        },
      );
      final page = await service.complete(
        'https://reader.example/story',
        const ReadingPageMetadata(title: 'Story'),
      );
      expect(page.image, isNull);
      expect(page.type, isNull);
      expect(requests, 1);
    },
  );
}
