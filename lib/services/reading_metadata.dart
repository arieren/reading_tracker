import 'dart:convert';

import 'package:http/http.dart' as http;

import 'page_document.dart';

import 'reading_page.dart';

/// Reads public page metadata and the active reader's controls. It deliberately
/// excludes chapter lists, recommendations and previous/next navigation labels.
const readingMetadataScript = r'''
(() => {
  const text = el => (el?.innerText ?? el?.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 1000);
  const meta = selector => (document.querySelector(selector)?.content || '').slice(0, 1000);
  const data = {
    documentTitle: (document.title || '').slice(0, 1000),
    series: meta('meta[property="og:title"],meta[name="twitter:title"]'),
    image: '',
    title: '', chapter: '', type: ''
  };
  data.heading = text(document.querySelector('[data-series-title],[itemprop="name"][data-series],h1'));
  const generic = value => /^(?:home|reader|read|details|chapters?|chapter list|all chapters|table of contents|contents|menu|search|library|bookmarks?|settings|next|previous|back|type|format|chapter\s*\d*)$/i.test(value);
  const identity = value => value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
  const siteName = meta('meta[property="og:site_name"]');
  const visible = el => {
    const box = el.getBoundingClientRect();
    const style = getComputedStyle(el);
    return box.width > 0 && box.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
  };
  if (!data.chapter) {
    const active = document.querySelector('[aria-current="page"],[data-current-chapter]');
    const value = active?.getAttribute('data-current-chapter');
    const label = text(active);
    if (value && /^\d+(?:\.\d+)?$/.test(value)) data.chapter = 'Chapter ' + value;
    else if (/^(?:chapter|ch\.?|episode|ep\.?)\s*[:#\-]?\s*\d+(?:\.\d+)?(?:\s*\/\s*\d+(?:\.\d+)?)?$/i.test(label)) data.chapter = label;
    if (!data.chapter) {
      const labels = [...document.querySelectorAll('button,[role="status"]')].map(text).filter(label =>
        /^(?:chapter|episode)\s+\d+(?:\.\d+)?\s*\/\s*\d+(?:\.\d+)?$/i.test(label));
      if (new Set(labels).size === 1) data.chapter = labels[0];
    }
  }
  if (!data.type) data.type = meta('meta[property="book:type"],meta[name="media-type"]') ||
    document.querySelector('[data-media-type]')?.getAttribute('data-media-type') || '';
  // A unique, visible title link near the top is useful on chapter readers whose
  // browser title is only "Chapters". Do not use arbitrary body text or menus.
  if ((!data.series || generic(data.series) || identity(data.series) === identity(siteName)) &&
      (!data.documentTitle || generic(data.documentTitle) || identity(data.documentTitle) === identity(siteName)) &&
      (!data.heading || generic(data.heading)) && data.chapter) {
    const controls = [...document.querySelectorAll('a,button,[role="button"]')].slice(0,300).filter(el => {
      const label = text(el);
      const box = el.getBoundingClientRect();
      return visible(el) && box.top >= 0 && box.top < Math.min(220, innerHeight * .35) &&
        !el.closest('nav,footer,aside,[role="menu"],[role="navigation"]') &&
        label.length >= 4 && label.length <= 120 && /\p{L}/u.test(label) &&
        !generic(label) && identity(label) !== identity(siteName) &&
        !/^(?:chapter|episode|next |previous |sign |log |add |save |start |continue |report |join |share |go |read |show |hide |open |close |upload |download |support )/i.test(label);
    }).map(text);
    const unique = [...new Set(controls)];
    if (unique.length === 1) data.title = unique[0];
  }
  if (!data.type) {
    for (const label of [...document.querySelectorAll('dt,th,span,p,div,strong,b')].slice(0,1500)) {
      if (!visible(label) || !/^(?:type|format|media type)\s*:?$/i.test(text(label))) continue;
      const value = text(label.nextElementSibling);
      if (/^(?:manga|manhua|manhwa|manwha|light[ _-]?novel|web[ _-]?novel|novel)$/i.test(value)) {
        data.type = value; break;
      }
    }
  }
  const story = [data.title, data.series, data.documentTitle, data.heading].find(value =>
    value && !generic(value) && identity(value) !== identity(siteName)) || '';
  const covers = [...document.querySelectorAll('img')].slice(0,300).filter(el => {
    const label = el.getAttribute('alt') || '';
    const hint = [el.id, el.className, label].join(' ');
    const width = el.naturalWidth || Number(el.getAttribute('width'));
    const height = el.naturalHeight || Number(el.getAttribute('height'));
    return !el.closest('nav,header,footer,aside') && !/logo|banner|avatar|icon|sprite/i.test(hint) &&
      story && (identity(label) === identity(story) || /\b(?:cover|poster)\b/i.test(hint)) &&
      (!width || !height || (width >= 60 && height >= width * 1.1 && height < width * 2.8));
  });
  const coverSources = [...new Set(covers.map(el => el.currentSrc || el.getAttribute('src') || el.getAttribute('data-src')).filter(Boolean))];
  // Prefer a story-specific cover over a site-wide Open Graph banner.
  if (coverSources.length === 1) data.image = coverSources[0];
  if (/logo|banner|favicon|sprite/i.test(data.image)) data.image = '';
  const snippets = [];
  let size = 0;
  const selectors = 'title,meta[property^="og:"],meta[name^="twitter:"],meta[property="book:type"],meta[name="media-type"],script[type="application/ld+json"],h1,[data-series-title],[data-media-type],dl,table,.post-content_item,.info-row,[itemprop="genre"],img[itemprop="image"],link[rel="image_src"]';
  for (const node of [...document.querySelectorAll(selectors)].slice(0,100)) {
    const fragment = node.outerHTML;
    if (fragment.length > 100000 || size + fragment.length > 250000) continue;
    snippets.push(fragment); size += fragment.length;
  }
  data.markup = snippets.join('\n');
  if (data.image) { try { data.image = new URL(data.image, document.baseURI).href; } catch (_) { data.image = ''; } }
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

  factory ReadingPageMetadata.fromWebViewResult(dynamic value, String url) {
    dynamic data = value;
    for (var i = 0; i < 2 && data is String; i++) {
      data = jsonDecode(data);
    }
    if (data is! Map) throw const FormatException('Invalid page metadata.');
    final fields = data['markup'] is String
        ? extractPageDocument(data['markup'] as String, url)
        : <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.key == 'markup' ||
          entry.value is! String ||
          (entry.value as String).isEmpty) {
        continue;
      }
      if (entry.key == 'image' && !isLikelyCoverUrl(entry.value as String)) {
        continue;
      }
      if (entry.key == 'type') {
        final type = readingTypeFromText(entry.value as String);
        if (type != null) fields['type'] = type;
        continue;
      }
      fields[entry.key.toString()] = entry.value;
    }
    return ReadingPageMetadata.fromMap(fields);
  }

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
      final cleaned = suggestedStoryTitle(
        stripReadingSiteName(candidate, field('siteName')),
      );
      if (cleaned.isEmpty ||
          (field('siteName').isNotEmpty &&
              normalizedStoryTitle(cleaned) ==
                  normalizedStoryTitle(field('siteName'))) ||
          isGenericPageTitle(cleaned)) {
        continue;
      }
      title = cleaned;
      break;
    }
    final type = field('medium').toLowerCase() == 'novel'
        ? 'Light Novel'
        : switch (field('type')
              .toLowerCase()
              .replaceAll(RegExp(r'[\s_-]+'), ' ')) {
            'manhwa' || 'manwha' => 'Manhwa',
            'manga' || 'manhua' => 'Manga',
            'light novel' || 'web novel' => 'Light Novel',
            'novel' => 'Novel',
            _ => null,
          };
    final image = field('image');
    return ReadingPageMetadata(
      title: title,
      chapter: chapter,
      type: type,
      image: isLikelyCoverUrl(image) ? image : null,
    );
  }
}

/// Completes new bookmarks and retries a missing cover once per reader opening.
/// Lookup failure preserves manual saving and locally stored progress.
class ReadingMetadataService {
  ReadingMetadataService({this.request = http.get});
  final Future<http.Response> Function(Uri) request;

  Future<ReadingPageMetadata> complete(
    String url,
    ReadingPageMetadata page,
  ) async {
    if ((page.image != null && page.title.isNotEmpty && page.type != null) ||
        !isReadingUrl(url)) {
      return page;
    }
    try {
      final response = await request(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
        return page;
      }
      final details = ReadingPageMetadata.fromMap(
        extractPageDocument(utf8.decode(response.bodyBytes), url),
      );
      if (page.title.isNotEmpty &&
          normalizedStoryTitle(details.title) !=
              normalizedStoryTitle(page.title)) {
        return page;
      }
      return ReadingPageMetadata(
        title: page.title.isEmpty ? details.title : page.title,
        chapter: page.chapter ?? details.chapter,
        type: page.type ?? details.type,
        image: page.image ?? details.image,
      );
    } on Object {
      return page;
    }
  }
}
