import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reading_tracker/services/catalog_service.dart';

void main() {
  test(
    'catalog encodes punctuation without altering query parameters',
    () async {
      Uri? requested;
      final service = CatalogService(
        request: (uri) async {
          requested = uri;
          return http.Response('{"data":[]}', 200);
        },
      );
      await service.search('A&B #1?');
      expect(requested!.host, 'api.tenrai.org');
      expect(requested!.path, '/v1/manga');
      expect(requested!.queryParameters['q'], 'A&B #1?');
      expect(requested!.queryParameters.length, 2);
    },
  );
  test(
    'catalog sanitizes malformed nested data before displaying results',
    () async {
      final service = CatalogService(
        request: (_) async => http.Response(
          '{"data":[{"title":"Story","type":"Unknown","images":null},{"type":"Manga"}]}',
          200,
        ),
      );
      final result = await service.search('Story');
      expect(result.length, 1);
      expect(result.single['type'], 'Novel');
      expect(result.single['images']['jpg']['image_url'], '');
    },
  );
  test('catalog rate limits surface a retryable failure', () async {
    final service = CatalogService(
      request: (_) async => http.Response('', 429),
    );
    await expectLater(
      service.search('Story'),
      throwsA(isA<CatalogException>()),
    );
  });

  test('blank titles do not contact the catalog', () async {
    final service = CatalogService(
      request: (_) => throw StateError('Unexpected request'),
    );
    expect(await service.search('  '), isEmpty);
  });

  test('successful empty results differ from invalid response data', () async {
    expect(
      await CatalogService(
        request: (_) async => http.Response('{"data":[]}', 200),
      ).search('Missing'),
      isEmpty,
    );
    for (final body in ['<html>offline</html>', '{"data":null}', '[]']) {
      await expectLater(
        CatalogService(request: (_) async => http.Response(body, 200))
            .search('Story'),
        throwsA(isA<CatalogException>()),
      );
    }
  });

  test('unicode titles and catalog types survive decoding', () async {
    final service = CatalogService(
      request: (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'data': [
              {'title': '進撃の巨人', 'type': 'Manga'},
              {'title': 'A novel', 'type': 'Light Novel'},
              {'title': 'A comic', 'type': 'Manhwa'},
              {'title': 'A one-shot', 'type': 'One-shot'},
            ],
          }),
        ),
        200,
      ),
    );
    final rows = await service.search('進撃');
    expect(rows.first['title'], '進撃の巨人');
    expect(rows.map((r) => r['type']), [
      'Manga',
      'Light Novel',
      'Manhwa',
      'Manga',
    ]);
  });

  test(
    'concurrent and repeated searches share requests but not mutable results',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final service = CatalogService(
        request: (_) {
          calls++;
          return response.future;
        },
      );
      final first = service.search('Story');
      final second = service.search(' story ');
      response.complete(
        http.Response(
          '{"data":[{"title":"Story","type":"Manga","images":{"jpg":{"image_url":"https://example.com/cover.jpg"}}}]}',
          200,
        ),
      );
      final rows = await first;
      rows.single['images']['jpg']['image_url'] = 'changed';
      expect(
        (await second).single['images']['jpg']['image_url'],
        'https://example.com/cover.jpg',
      );
      expect(
        (await service.search('STORY')).single['images']['jpg']['image_url'],
        'https://example.com/cover.jpg',
      );
      expect(calls, 1);
    },
  );

  test('rate limit blocks further network calls during Retry-After', () async {
    var calls = 0;
    final service = CatalogService(
      request: (_) async {
        calls++;
        return http.Response('', 429, headers: {'retry-after': '120'});
      },
    );
    await expectLater(
      service.search('Story'),
      throwsA(isA<CatalogException>()),
    );
    await expectLater(
      service.search('Other'),
      throwsA(isA<CatalogException>()),
    );
    expect(calls, 1);
  });

  test(
    'network and server failures do not become cached empty results',
    () async {
      for (final failure in [
        http.ClientException('offline'),
        TimeoutException('timeout'),
      ]) {
        final service = CatalogService(request: (_) async => throw failure);
        await expectLater(
          service.search('Story'),
          throwsA(isA<CatalogException>()),
        );
      }
      var calls = 0;
      final service = CatalogService(
        request: (_) async => ++calls == 1
            ? http.Response('offline', 503)
            : http.Response('{"data":[{"title":"Story"}]}', 200),
      );
      await expectLater(
        service.search('Story'),
        throwsA(isA<CatalogException>()),
      );
      expect((await service.search('Story')).single['title'], 'Story');
      expect(calls, 2);
    },
  );
}
