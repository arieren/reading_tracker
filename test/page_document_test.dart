import 'package:flutter_test/flutter_test.dart';
import 'package:reading_tracker/services/page_document.dart';
import 'package:reading_tracker/services/reading_metadata.dart';

void main() {
  test('structured story cover takes priority over a website banner', () {
    final value = ReadingPageMetadata.fromMap(
      extractPageDocument(
        '<h1>Moon Garden</h1><meta property="og:image" content="/site-banner.jpg">'
            '<script type="application/ld+json">{"@type":"Book","name":"Moon Garden","image":"/moon.jpg"}</script>',
        'https://reader.example/story',
      ),
    );
    expect(value.image, 'https://reader.example/moon.jpg');
  });
  test('site branding is not saved as the book title', () {
    final value = ReadingPageMetadata.fromWebViewResult({
      'documentTitle': 'Custom Reader',
      'markup': '<meta property="og:site_name" content="Custom Reader"><h1>Actual Story</h1>',
    }, 'https://reader.example/story');
    expect(value.title, 'Actual Story');
  });
  test('unrelated structured book does not override the main page', () {
    final fields = extractPageDocument(
      '<meta property="og:title" content="Main Story"><script type="application/ld+json">{"@type":"Book","name":"Recommended Story","image":"/wrong.jpg"}</script>',
      'https://reader.example/main',
    );
    final value = ReadingPageMetadata.fromMap(fields);
    expect(value.title, 'Main Story');
    expect(value.image, isNull);
  });
  test(
    'WebView decoding keeps recognized type and resolves explicit covers',
    () {
      final value = ReadingPageMetadata.fromWebViewResult({
        'documentTitle': 'Chapter 4 | Reader',
        'type': 'Comic',
        'markup': '<meta property="og:title" content="My Story"><meta property="og:image" content="/cover.jpg"><dl><dt>Type</dt><dd>Manhwa</dd></dl>',
      }, 'https://reader.example/chapter/4');
      expect(value.title, 'My Story');
      expect(value.type, 'Manhwa');
      expect(value.chapter, 4);
      expect(value.image, 'https://reader.example/cover.jpg');
    },
  );
  ReadingPageMetadata parse(String html) => ReadingPageMetadata.fromMap(
    extractPageDocument(html, 'https://custom-reader.example/story'),
  );
  test('unfamiliar site uses book JSON-LD and relative cover URLs', () {
    final value = parse(
      '''<title>Chapter 9 | Custom Reader</title><meta property="og:site_name" content="Custom Reader"><script type="application/ld+json">{"@type":"Book","name":"Moon Garden","genre":["Fantasy","Manhwa"],"image":{"url":"/covers/moon.jpg"}}</script>''',
    );
    expect(value.title, 'Moon Garden');
    expect(value.chapter, 9);
    expect(value.type, 'Manhwa');
    expect(value.image, 'https://custom-reader.example/covers/moon.jpg');
  });
  test('standard title/cover tags and labelled type fields work without an adapter', () {
    final value = parse(
      '''<meta property="og:title" content="Silver Road | A New Site"><meta property="og:site_name" content="A New Site"><meta name="twitter:image" content="../cover.jpg"><dl><dt>Type:</dt><dd>Web Novel</dd></dl>''',
    );
    expect(value.title, 'Silver Road');
    expect(value.type, 'Light Novel');
    expect(value.image, 'https://custom-reader.example/cover.jpg');
  });
  test(
    'main-entity graph metadata excludes unrelated logos and recommendations',
    () {
      final value = parse(
        '''<h1>My Book</h1><script type="application/ld+json">{"@graph":[{"@type":"Organization","name":"Publisher","image":"/logo.jpg"},{"@type":"WebPage","mainEntity":{"@type":"ComicSeries","name":"My Book","image":"/book.jpg"},"itemListElement":[{"@type":"Book","name":"Other","image":"/other.jpg"}]}]}</script>''',
      );
      expect(value.title, 'My Book');
      expect(value.image, 'https://custom-reader.example/book.jpg');
      expect(value.type, 'Manga');
    },
  );
  test(
    'ambiguous book metadata and arbitrary reader images are not guessed',
    () {
      final value = parse(
        '''<script type="application/ld+json">[{"@type":"Book","name":"One","image":"/one.jpg"},{"@type":"Book","name":"Two","image":"/two.jpg"}]</script><img src="/chapter-page.jpg"><p>Recommended manhwa</p>''',
      );
      expect(value.title, isEmpty);
      expect(value.type, isNull);
      expect(value.image, isNull);
    },
  );
  test('malformed structured metadata does not break other metadata', () {
    final value = parse(
      '''<script type="application/ld+json">broken</script><meta property="og:title" content="Valid Book"><meta property="og:image" content="javascript:bad()">''',
    );
    expect(value.title, 'Valid Book');
    expect(value.image, isNull);
  });
}
