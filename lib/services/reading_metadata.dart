import 'dart:convert';

import 'package:http/http.dart' as http;

import 'reading_page.dart';

/// Reads public page metadata and the active reader's controls. It deliberately
/// excludes chapter lists, recommendations and previous/next navigation labels.
const readingMetadataScript = r'''
(() => {
  const text = el => (el?.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 1000);
  const meta = selector => (document.querySelector(selector)?.content || '').slice(0, 1000);
  const data = {
    documentTitle: (document.title || '').slice(0, 1000),
    series: meta('meta[property="og:title"],meta[name="twitter:title"]'),
    image: meta('meta[property="og:image"],meta[name="twitter:image"]'),
    title: '', chapter: '', type: ''
  };
  // Atsu leaves document.title as "Atsumaru" on some client-rendered pages.
  // The series-info link identifies the active story; the reader counter is
  // "Chapter current / total", even when its floating controls are hidden.
  if (location.hostname === 'atsu.moe' || location.hostname.endsWith('.atsu.moe')) {
    const parts = location.pathname.split('/').filter(Boolean);
    if (parts[0] === 'read' && parts[1]) {
      const info = [...document.querySelectorAll('a[href]')].find(a => {
        try {
          const url = new URL(a.href, location.href);
          return url.origin === location.origin &&
            (url.pathname === '/manga/' + parts[1] || url.pathname === '/novel/' + parts[1]);
        } catch (_) { return false; }
      });
      if (info) {
        const label = [...info.querySelectorAll('span')].find(el =>
          /^.{1,40}\s+info$/i.test(text(el)));
        if (label) {
          data.type = text(label).replace(/\s+info$/i, '');
          data.title = text(label.nextElementSibling);
        }
      }
      if (!data.title) {
        // Atsu's compact reader omits the info-link labels. Its floating
        // title button repeats the same title in a sizing paragraph and span.
        const titles = [...document.querySelectorAll('button[aria-hidden]')].map(button => {
          const sizing = text(button.querySelector('p'));
          const label = text(button.querySelector('span'));
          return sizing && sizing === label ? label : '';
        }).filter(Boolean);
        if (new Set(titles).size === 1) data.title = titles[0];
      }
      const counters = [...document.querySelectorAll('button')].map(text).filter(value =>
        /^(?:chapter|episode)\s+\d+(?:\.\d+)?\s*\/\s*\d+(?:\.\d+)?$/i.test(value));
      if (new Set(counters).size === 1) data.chapter = counters[0];
    }
  }
  data.heading = text(document.querySelector('[data-series-title],[itemprop="name"][data-series],h1'));
  if (!data.chapter) {
    const active = document.querySelector('[aria-current="page"],[data-current-chapter]');
    const value = active?.getAttribute('data-current-chapter');
    const label = text(active);
    if (value && /^\d+(?:\.\d+)?$/.test(value)) data.chapter = 'Chapter ' + value;
    else if (/^(?:chapter|ch\.?|episode|ep\.?)\s*[:#\-]?\s*\d+(?:\.\d+)?(?:\s*\/\s*\d+(?:\.\d+)?)?$/i.test(label)) data.chapter = label;
  }
  if (!data.type) data.type = meta('meta[property="book:type"],meta[name="media-type"]') ||
    document.querySelector('[data-media-type]')?.getAttribute('data-media-type') || '';
  return JSON.stringify(data);
})()
''';

class ReadingPageMetadata {
  const ReadingPageMetadata({
    required this.title,
    this.chapter,
    this.type,
    this.image,
  });
  final String title;
  final int? chapter;
  final String? type, image;

  String get matchingPageTitle =>
      chapter == null ? title : '$title - Chapter $chapter';

  factory ReadingPageMetadata.fromMap(Map<dynamic, dynamic> data) {
    String field(String key) =>
        data[key] is String ? (data[key] as String).trim() : '';
    final documentTitle = field('documentTitle');
    final series = field('series');
    final explicitTitle = field('title');
    final chapterLabel = field('chapter');
    final chapter = chapterLabel.isNotEmpty
        ? chapterFromPageTitle(chapterLabel)
        : chapterFromPageTitle(documentTitle) ?? chapterFromPageTitle(series);
    var title = '';
    for (final candidate in [
      explicitTitle,
      series,
      documentTitle,
      field('heading'),
    ]) {
      final cleaned = suggestedStoryTitle(candidate);
      if (cleaned.isEmpty ||
          RegExp(
            r'^(?:atsumaru|atsu|webtoon|manga plus|home|chapter\s*\d*)$',
            caseSensitive: false,
          ).hasMatch(cleaned)) {
        continue;
      }
      title = cleaned;
      break;
    }
    final type = switch (field('type')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), ' ')) {
      'manhwa' || 'manwha' => 'Manhwa',
      'manga' || 'manhua' => 'Manga',
      'light novel' => 'Light Novel',
      'novel' || 'web novel' => 'Novel',
      _ => null,
    };
    final image = field('image');
    return ReadingPageMetadata(
      title: title,
      chapter: chapter,
      type: type,
      image: isReadingUrl(image) ? image : null,
    );
  }
}

/// Only invoked when saving a new bookmark with incomplete page details.
/// Automatic reading updates never depend on this optional network request.
class ReadingMetadataService {
  ReadingMetadataService({this.request = http.get});
  final Future<http.Response> Function(Uri) request;

  Future<ReadingPageMetadata> complete(
    String url,
    ReadingPageMetadata page,
  ) async {
    final uri = Uri.tryParse(url);
    final parts = uri?.pathSegments ?? <String>[];
    if (uri == null ||
        !isReadingUrl(url) ||
        !(uri.host == 'atsu.moe' || uri.host.endsWith('.atsu.moe')) ||
        parts.length != 3 ||
        parts.first != 'read' ||
        !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(parts[1]) ||
        (page.title.isNotEmpty && page.type != null)) {
      return page;
    }
    try {
      final response = await request(
        Uri.https('atsu.moe', '/api/manga/info', {'mangaId': parts[1]}),
      ).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
        return page;
      }
      final data = jsonDecode(response.body);
      if (data is! Map || data['id'] != parts[1] || data['title'] is! String) {
        return page;
      }
      final details = ReadingPageMetadata.fromMap({
        'title': data['title'],
        'type': data['type'],
      });
      if (page.title.isNotEmpty &&
          normalizedStoryTitle(page.title) !=
              normalizedStoryTitle(details.title)) {
        return page;
      }
      int? chapter;
      if (data['chapters'] is List) {
        for (final entry in data['chapters'] as List) {
          if (entry is Map && entry['id'] == parts[2]) {
            final number = entry['number'];
            if (number is num &&
                number.isFinite &&
                number >= 0 &&
                number <= 2147483647 &&
                number == number.roundToDouble()) {
              chapter = number.toInt();
            }
            break;
          }
        }
      }
      return ReadingPageMetadata(
        title: page.title.isEmpty ? details.title : page.title,
        chapter: page.chapter ?? chapter,
        type: page.type ?? details.type,
        image: page.image,
      );
    } on Object {
      return page;
    }
  }
}
