import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reading_tracker/services/reading_metadata.dart';

void main() {
  test(
    'Atsu supplies cover even when title and type are already known',
    () async {
      final service = ReadingMetadataService(
        request: (uri) async {
          expect(uri, Uri.parse('https://atsu.moe/api/manga/page?id=3nRa'));
          return http.Response(
            jsonEncode({
              'mangaPage': {
                'id': '3nRa',
                'title': 'Break New World',
                'type': 'Manga',
                'poster': {'image': 'posters/break.jpg'},
                'chapters': [
                  {'id': 'latest', 'number': 68},
                  {'id': 'Lavmv', 'number': 35},
                ],
              },
            }),
            200,
          );
        },
      );
      final page = await service.complete(
        'https://atsu.moe/read/3nRa/Lavmv',
        const ReadingPageMetadata(
          title: 'Break New World',
          type: 'Manga',
          chapter: 35,
        ),
      );
      expect(page.title, 'Break New World');
      expect(page.chapter, 35);
      expect(page.image, 'https://cdn.atsu.moe/static/posters/break.jpg');
    },
  );
  test(
    'relative cover metadata is parsed without depending on attribute order',
    () async {
      final service = ReadingMetadataService(
        request: (_) async => http.Response(
          '<html><head><meta content="/covers/book.jpg" property="og:image"></head></html>',
          200,
        ),
      );
      final page = await service.complete(
        'https://reader.example/series/book',
        const ReadingPageMetadata(title: 'Book'),
      );
      expect(page.image, 'https://reader.example/covers/book.jpg');
    },
  );
  test(
    'mismatched series data and offline lookups preserve existing details',
    () async {
      const page = ReadingPageMetadata(title: 'Break New World', chapter: 35);
      final wrong = ReadingMetadataService(
        request: (_) async => http.Response(
          jsonEncode({
            'mangaPage': {
              'id': '3nRa',
              'title': 'Other Story',
              'type': 'Manhwa',
              'poster': {'image': 'posters/other.jpg'},
            },
          }),
          200,
        ),
      );
      expect(
        await wrong.complete('https://atsu.moe/read/3nRa/Lavmv', page),
        same(page),
      );
      final offline = ReadingMetadataService(
        request: (_) async => throw http.ClientException('Offline'),
      );
      expect(
        await offline.complete('https://atsu.moe/read/3nRa/Lavmv', page),
        same(page),
      );
    },
  );
  test(
    'a complete page makes no extra request and keeps the chosen cover',
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
        image: 'https://example.com/chosen.jpg',
      );
      expect(
        await service.complete('https://atsu.moe/read/abc/def', page),
        same(page),
      );
    },
  );
}
