import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/services/reading_sites.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('custom websites survive reopening and can be removed without changing defaults', () async {
    final store = ReadingSiteStore();
    await store.add(' My website ', ' https://example.com/stories ');
    final sites = await ReadingSiteStore().load();
    expect(sites, hasLength(2));
    expect(sites.last.name, 'My website');
    expect(sites.last.url, 'https://example.com/stories');
    await store.remove(sites.first);
    expect(await store.load(), hasLength(2));
    await store.remove(sites.last);
    expect(await store.load(), hasLength(1));
  });

  test(
    'rejects invalid addresses, credentials, blank names and duplicates',
    () async {
      final store = ReadingSiteStore();
      for (final url in [
        '',
        'javascript:alert(1)',
        'https://user:pass@example.com',
        'example.com',
      ]) {
        await expectLater(store.add('Site', url), throwsFormatException);
      }
      await expectLater(
        store.add(' ', 'https://example.com'),
        throwsFormatException,
      );
      await expectLater(
        store.add('Atsu again', 'https://atsu.moe/explore#top'),
        throwsFormatException,
      );
      await store.add('Site', 'https://example.com');
      await expectLater(
        store.add('Site again', 'https://example.com/'),
        throwsFormatException,
      );
    },
  );

  test(
    'corrupt shortcut entries do not prevent valid shortcuts loading',
    () async {
      SharedPreferences.setMockInitialValues({
        'reading_sites': [
          'broken',
          'null',
          '{}',
          jsonEncode({'name': 'Unsafe', 'url': 'file:///private'}),
          jsonEncode({'name': 'Valid', 'url': 'https://example.com'}),
        ],
      });
      expect((await ReadingSiteStore().load()).last.name, 'Valid');
    },
  );
}
