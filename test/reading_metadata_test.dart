import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/reading_metadata.dart';

void main() {
  test('navigation headings and obvious logos are not book metadata', () {
    for (final label in ['Chapters', 'Chapter list', 'All chapters', 'Menu']) {
      expect(
        ReadingPageMetadata.fromMap({'documentTitle': label}).title,
        isEmpty,
      );
    }
    expect(
      ReadingPageMetadata.fromMap({
        'title': 'Moon Garden',
        'image': 'https://reader.example/assets/site-logo.png',
      }).image,
      isNull,
    );
  });
  test('generic headings cannot mask a changed story title', () {
    final data = ReadingPageMetadata.fromMap({
      'documentTitle': 'Different Story - Chapter 99',
      'heading': 'Old Story',
    });
    expect(data.title, 'Different Story');
    expect(data.chapter, 99);
  });
  test('heading supplies a title when the site title is generic', () {
    final data = ReadingPageMetadata.fromMap({
      'documentTitle': 'Reader',
      'heading': 'New Adventure',
      'chapter': 'Chapter 5',
    });
    expect(data.title, 'New Adventure');
    expect(data.chapter, 5);
  });
  test('reader controls supply title, current chapter and media type', () {
    final data = ReadingPageMetadata.fromMap({
      'documentTitle': 'Reader',
      'title': 'The Stellar Swordmaster',
      'chapter': 'Chapter 145 / 146',
      'type': 'Manhwa',
    });
    expect(data.title, 'The Stellar Swordmaster');
    expect(data.chapter, 145);
    expect(data.type, 'Manhwa');
    expect(data.matchingPageTitle, 'The Stellar Swordmaster - Chapter 145');
  });
  test('metadata title can be combined with a chapter-only browser title', () {
    final data = ReadingPageMetadata.fromMap({
      'documentTitle': 'Chapter 8',
      'series': 'A Story | Reader',
      'siteName': 'Reader',
      'type': 'Light Novel',
    });
    expect(data.title, 'A Story');
    expect(data.chapter, 8);
    expect(data.type, 'Light Novel');
  });
  test(
    'unknown site names, types, and fractional chapters are not guessed',
    () {
      final data = ReadingPageMetadata.fromMap({
        'documentTitle': 'Reader',
        'chapter': 'Chapter 12.5 / 100',
        'type': 'Comic',
      });
      expect(data.title, isEmpty);
      expect(data.chapter, isNull);
      expect(data.type, isNull);
    },
  );
  test(
    'known type aliases normalize and unsafe cover addresses are rejected',
    () {
      for (final entry in {
        'manwha': 'Manhwa',
        'web novel': 'Light Novel',
        'light_novel': 'Light Novel',
      }.entries) {
        expect(
          ReadingPageMetadata.fromMap({'type': entry.key}).type,
          entry.value,
        );
      }
      expect(
        ReadingPageMetadata.fromMap({'image': 'javascript:alert(1)'}).image,
        isNull,
      );
    },
  );
}
