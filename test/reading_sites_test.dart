import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/services/reading_sites.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'only user added websites survive reopening and every site can be removed',
    () async {
      final store = ReadingSiteStore();
      expect(await store.load(), isEmpty);
      await store.add(' My website ', ' https://example.com/stories ');
      final sites = await ReadingSiteStore().load();
      expect(sites, hasLength(1));
      expect(sites.single.name, 'My website');
      expect(sites.single.url, 'https://example.com/stories');
      await store.remove(sites.single);
      expect(await store.load(), isEmpty);
    },
  );
  test(
    'rejects invalid addresses, credentials, blank names and duplicates',
    () async {
      final store = ReadingSiteStore();
      for (final url in [
        '',
        'javascript:alert(1)',
        'https://user:pass@example.com',
        'not a website',
      ]) {
        await expectLater(store.add('Site', url), throwsFormatException);
      }
      await expectLater(
        store.add(' ', 'https://example.com'),
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
