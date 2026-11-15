import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/services/reading_link_service.dart';

Book book({
  String title = 'Solo Leveling',
  String type = 'Manhwa',
  String? link,
}) => Book(title: title, type: type, chapter: 4, linkURL: link);
Map<String, dynamic> row(
  String id,
  String title, {
  String medium = 'Comic',
  List<String> aliases = const [],
}) => {'id': id, 'title': title, 'medium': medium, 'otherNames': aliases};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Atsu is default and the preferred provider persists', () async {
    final prefs = ReadingSourcePreferences();
    expect(await prefs.load(), ReadingSource.atsu);
    await prefs.save(ReadingSource.mangaFire);
    expect(await ReadingSourcePreferences().load(), ReadingSource.mangaFire);
  });
  ReadingLinkService service(
    List<Map<String, dynamic>> rows, {
    List<Map<String, dynamic>>? chapters,
  }) => ReadingLinkService(
    request: (uri) async {
      if (uri.path.contains('/collections/')) {
        return http.Response(
          jsonEncode({
            'hits': rows.map((row) => {'document': row}).toList(),
          }),
          200,
        );
      }
      final selected = rows.firstWhere(
        (row) => row['id'] == uri.queryParameters['id'],
      );
      return http.Response(
        jsonEncode({
          'mangaPage': {
            ...selected,
            'poster': {'image': 'posters/cover.jpg'},
            'chapters': chapters ?? [],
          },
        }),
        200,
      );
    },
  );
  test('exact title gets its current chapter and a cover', () async {
    final result = await service(
      [row('comic', 'Solo Leveling')],
      chapters: [
        {'id': 'ch4', 'number': 4},
      ],
    ).find(book());
    expect(result!.url, 'https://atsu.moe/read/comic/ch4');
    expect(result.image, 'https://cdn.atsu.moe/static/posters/cover.jpg');
  });
  test(
    'listed alternate title qualifies but sequels and fuzzy results do not',
    () async {
      final result = await service([
        row(
          'book',
          'The Stellar Swordmaster',
          aliases: ['Star-Embracing Swordmaster'],
        ),
      ]).find(book(title: 'Star-Embracing Swordmaster'));
      expect(result!.url, 'https://atsu.moe/manga/book');
      expect(
        await service([row('sequel', 'Solo Leveling: Ragnarok')]).find(book()),
        isNull,
      );
    },
  );
  test('ambiguous exact titles remain blank', () async {
    expect(
      await service([row('one', 'Solo Leveling'), row('two', 'Solo Leveling')])
          .find(book()),
      isNull,
    );
  });
  test('novel and comic editions are distinguished', () async {
    final rows = [
      row('comic', 'Solo Leveling'),
      row('novel', 'Solo Leveling', medium: 'Novel'),
    ];
    expect(
      (await service(rows).find(book()))!.url,
      'https://atsu.moe/manga/comic',
    );
    expect(
      (await service(rows).find(book(type: 'Light Novel')))!.url,
      'https://atsu.moe/novel/novel',
    );
  });
  test('regular novels and supplied links do not trigger search', () async {
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
  test(
    'MangaFire rejection is reported and never replaced with an Atsu link',
    () async {
      await ReadingSourcePreferences().save(ReadingSource.mangaFire);
      final lookup = ReadingLinkService(
        request: (uri) async {
          expect(uri.host, 'mangafire.to');
          return http.Response('Forbidden', 403);
        },
      );
      await expectLater(
        lookup.find(book()),
        throwsA(isA<ReadingSourceException>()),
      );
    },
  );
  test(
    'MangaFire requires an exact match and uses its canonical title route',
    () async {
      await ReadingSourcePreferences().save(ReadingSource.mangaFire);
      final lookup = ReadingLinkService(
        request: (_) async => http.Response(
          jsonEncode({
            'items': [
              {
                'hid': 'book1',
                'slug': 'solo-leveling',
                'title': 'Solo Leveling',
                'poster': {'medium': 'https://images.example/cover.jpg'},
              },
            ],
          }),
          200,
        ),
      );
      expect(
        (await lookup.find(book()))!.url,
        'https://mangafire.to/title/book1-solo-leveling',
      );
    },
  );
}
