import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/catalog_service.dart';

void main() {
  test(
    'live catalog returns manga and light novel matches with covers',
    () async {
      final catalog = CatalogService();
      for (final title in ['Naruto', 'Sword Art Online']) {
        final rows = await catalog.search(title);
        expect(rows, isNotEmpty, reason: title);
        expect(
          rows.any(
            (r) => (r['title'] as String).toLowerCase().contains(
              title.toLowerCase(),
            ),
          ),
          isTrue,
        );
        expect(
          rows.any(
            (r) => (r['images']['jpg']['image_url'] as String).startsWith(
              'https://',
            ),
          ),
          isTrue,
        );
      }
    },
    skip: !const bool.fromEnvironment('LIVE_CATALOG_TEST'),
  );
}
