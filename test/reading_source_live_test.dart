import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reading_tracker/models/book.dart';
import 'package:reading_tracker/services/reading_link_service.dart';

void main() {
  test('live Atsu exact title resolves separate comic and novel editions with covers', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ReadingLinkService();
    final comic = await service.find(
      Book(title: 'Solo Leveling', type: 'Manhwa', chapter: 4),
    );
    final novel = await service.find(
      Book(title: 'Solo Leveling', type: 'Light Novel', chapter: 4),
    );
    expect(comic, isNotNull);
    expect(novel, isNotNull);
    expect(comic!.image, startsWith('https://cdn.atsu.moe/static/posters/'));
    expect(comic.url, isNot(novel!.url));
  }, skip: !const bool.fromEnvironment('LIVE_READING_SOURCE_TEST'));
}
