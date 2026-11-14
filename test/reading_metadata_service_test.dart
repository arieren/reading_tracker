import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reading_tracker/services/reading_metadata.dart';

void main() {
  test(
    'compact Atsu reader fills missing type and title from the exact series',
    () async {
      final service = ReadingMetadataService(
        request: (uri) async {
          expect(
            uri,
            Uri.parse('https://atsu.moe/api/manga/info?mangaId=3nRa'),
          );
          return http.Response(
            jsonEncode({
              'id': '3nRa',
              'title': 'Break New World',
              'type': 'Manga',
              'chapters': [
                {'id': 'last', 'number': 68},
                {'id': 'Lavmv', 'number': 35},
              ],
            }),
            200,
          );
        },
      );
      final page = await service.complete(
        'https://atsu.moe/read/3nRa/Lavmv',
        const ReadingPageMetadata(title: ''),
      );
      expect(page.title, 'Break New World');
      expect(page.type, 'Manga');
      expect(page.chapter, 35);
    },
  );
  test(
    'lookup preserves DOM details and rejects mismatched series data',
    () async {
      const page = ReadingPageMetadata(title: 'Break New World', chapter: 35);
      final service = ReadingMetadataService(
        request: (_) async => http.Response(
          jsonEncode({'id': '3nRa', 'title': 'Other Story', 'type': 'Manhwa'}),
          200,
        ),
      );
      expect(
        await service.complete('https://atsu.moe/read/3nRa/Lavmv', page),
        same(page),
      );
    },
  );
  test('optional lookup failure preserves manual saving', () async {
    const page = ReadingPageMetadata(title: 'Break New World', chapter: 35);
    final service = ReadingMetadataService(
      request: (_) async => throw http.ClientException('Offline'),
    );
    expect(
      await service.complete('https://atsu.moe/read/3nRa/Lavmv', page),
      same(page),
    );
  });
  test('complete pages and unrelated websites make no extra request', () async {
    final service = ReadingMetadataService(
      request: (_) async {
        fail('Unexpected network request');
      },
    );
    const page = ReadingPageMetadata(
      title: 'Story',
      type: 'Manhwa',
      chapter: 1,
    );
    expect(
      await service.complete('https://atsu.moe/read/abc/def', page),
      same(page),
    );
    const missing = ReadingPageMetadata(title: '');
    for (final url in [
      'https://example.com/read/abc/def',
      'https://atsu.moe/explore',
      'https://atsu.moe.evil.test/read/abc/def',
    ]) {
      expect(await service.complete(url, missing), same(missing));
    }
  });
}
