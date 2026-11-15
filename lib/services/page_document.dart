import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'reading_page.dart';

bool isGenericPageTitle(String value) => RegExp(
  r'^(?:home|reader|read|details|chapters?|chapter list|all chapters|table of contents|contents|menu|search|library|bookmark|bookmarks|settings|next|previous|back|type|format|chapter\s*\d*)$',
  caseSensitive: false,
).hasMatch(value.trim());

bool isLikelyCoverUrl(String value) =>
    isReadingUrl(value) &&
    !RegExp(
      r'(?:^|[/_.-])(?:logo|banner|icon|favicon|avatar|sprite)(?:[/_.-]|$)',
      caseSensitive: false,
    ).hasMatch(Uri.parse(value).path);

String? readingTypeFromText(String value) {
  for (final entry in {
    r'\b(?:light[ _-]?novel|web[ _-]?novel)\b': 'Light Novel',
    r'\b(?:manhwa|manwha)\b': 'Manhwa',
    r'\b(?:manga|manhua)\b': 'Manga',
    r'\bnovel\b': 'Novel',
  }.entries) {
    if (RegExp(entry.key, caseSensitive: false).hasMatch(value)) {
      return entry.value;
    }
  }
  return null;
}

String stripReadingSiteName(String value, String siteName) {
  if (siteName.trim().isEmpty) return value.trim();
  return value
      .replaceFirst(
        RegExp(
          r'\s+[-–|:]\s*' + RegExp.escape(siteName.trim()) + r'\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

/// Metadata from the main work only: no arbitrary page images, recommendation
/// lists, publisher logos, or genre guesses from the site's entire body.
Map<String, dynamic> extractPageDocument(String markup, String url) {
  final document = html.parse(markup);
  String text(Element? node) =>
      (node?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  String meta(String selector) =>
      document.querySelector(selector)?.attributes['content']?.trim() ?? '';
  final site = meta('meta[property="og:site_name"]');
  final series = meta('meta[property="og:title"],meta[name="twitter:title"]');
  final heading = text(
    document.querySelector(
      '[data-series-title],[itemprop="name"][data-series],h1',
    ),
  );
  final title = text(document.querySelector('title'));
  final works = <Map>[];
  void visit(dynamic node, int depth) {
    if (depth > 5 || works.length > 40) return;
    if (node is List) {
      for (final item in node.take(40)) {
        visit(item, depth + 1);
      }
      return;
    }
    if (node is! Map) return;
    final types = node['@type'] is List
        ? (node['@type'] as List).whereType<String>().toList()
        : [node['@type']?.toString() ?? ''];
    if (types.any(
      (type) => [
        'Book',
        'ComicSeries',
        'ComicStory',
        'CreativeWorkSeries',
        'Novel',
        'WebNovel',
        'LightNovel',
        'Manga',
        'Manhwa',
      ].contains(type.split('/').last),
    )) {
      works.add(node);
    }
    for (final key in ['@graph', 'mainEntity', 'isPartOf']) {
      if (node[key] != null) visit(node[key], depth + 1);
    }
  }

  for (final script
      in document
          .querySelectorAll('script[type="application/ld+json"]')
          .take(12)) {
    if (script.text.length > 100000) continue;
    try {
      visit(jsonDecode(script.text), 0);
    } on FormatException {
      /* Other metadata remains usable. */
    }
  }
  String identity(dynamic name) => normalizedStoryTitle(
    suggestedStoryTitle(stripReadingSiteName(name is String ? name : '', site)),
  );
  final known = [series, heading, title]
      .map(identity)
      .where(
        (name) =>
            name.isNotEmpty &&
            name != identity(site) &&
            !isGenericPageTitle(name),
      )
      .toSet();
  final matching = works
      .where(
        (work) => known.contains(identity(work['name'] ?? work['headline'])),
      )
      .toList();
  final candidates = matching.isNotEmpty
      ? matching
      : known.isEmpty
      ? works
      : <Map>[];
  final unique = candidates
      .map((work) => identity(work['name'] ?? work['headline']))
      .where((name) => name.isNotEmpty)
      .toSet();
  final work = unique.length == 1
      ? candidates.firstWhere(
          (work) => identity(work['name'] ?? work['headline']).isNotEmpty,
        )
      : <dynamic, dynamic>{};
  String structuredText(dynamic value) => value is List
      ? value.whereType<String>().join(', ')
      : value is String
      ? value
      : '';
  var type = meta('meta[property="book:type"],meta[name="media-type"]');
  type =
      readingTypeFromText(type) ??
      readingTypeFromText(structuredText(work['genre'])) ??
      readingTypeFromText(structuredText(work['@type'])) ??
      '';
  if (type.isEmpty && structuredText(work['@type']).contains('ComicSeries')) {
    type = 'Manga';
  }
  if (type.isEmpty) {
    type =
        readingTypeFromText(
          document
                  .querySelector('[data-media-type]')
                  ?.attributes['data-media-type'] ??
              '',
        ) ??
        '';
  }
  if (type.isEmpty) {
    type =
        readingTypeFromText(
          text(document.querySelector('[itemprop="genre"]')),
        ) ??
        '';
  }
  if (type.isEmpty) {
    for (final label
        in document
            .querySelectorAll(
              'dt,th,.summary-heading,.info-label,span,p,strong,b',
            )
            .take(80)) {
      if (!RegExp(
        r'^(?:type|format|media type)\s*:?$',
        caseSensitive: false,
      ).hasMatch(text(label))) {
        continue;
      }
      final found = readingTypeFromText(text(label.nextElementSibling));
      if (found != null) {
        type = found;
        break;
      }
    }
  }
  dynamic image = work['image'];
  if (image is List) image = image.isEmpty ? null : image.first;
  if (image is Map) image = image['url'] ?? image['contentUrl'];
  bool inPageChrome(Element node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (['nav', 'header', 'footer', 'aside'].contains(parent.localName)) {
        return true;
      }
    }
    return false;
  }

  final matchingImages = document
      .querySelectorAll('img')
      .where(
        (node) =>
            !inPageChrome(node) &&
            known.contains(identity(node.attributes['alt'])) &&
            !RegExp(
              r'logo|banner|avatar|icon|sprite',
              caseSensitive: false,
            ).hasMatch(
              '${node.className} ${node.id} ${node.attributes['alt'] ?? ''}',
            ),
      )
      .toList();
  final explicitCover = document.querySelector(
    'img[itemprop="image"],link[rel="image_src"]',
  );
  final imageCandidates = [
    if (image is String) image,
    if (matchingImages.length == 1)
      matchingImages.single.attributes['src'] ??
          matchingImages.single.attributes['data-src'] ??
          '',
    explicitCover?.attributes['src'] ?? explicitCover?.attributes['href'] ?? '',
    meta(
      'meta[property="og:image:secure_url"],meta[property="og:image"],meta[name="twitter:image"],meta[name="twitter:image:src"]',
    ),
  ];
  String cover = '';
  for (final rawImage in imageCandidates.where((value) => value.isNotEmpty)) {
    final resolved = Uri.tryParse(url)?.resolve(rawImage).toString();
    if (resolved != null && isLikelyCoverUrl(resolved)) {
      cover = resolved;
      break;
    }
  }
  var chapter = '';
  final active = document.querySelector(
    '[data-current-chapter],[aria-current="page"]',
  );
  final number = active?.attributes['data-current-chapter'];
  if (number != null && RegExp(r'^\d+(?:\.\d+)?$').hasMatch(number)) {
    chapter = 'Chapter $number';
  } else if (chapterFromPageTitle(text(active)) != null) {
    chapter = text(active);
  }
  return {
    'title': structuredText(work['name'] ?? work['headline']),
    'documentTitle': title,
    'series': series,
    'heading': heading,
    'siteName': site,
    'type': type,
    'chapter': chapter,
    'image': cover,
  };
}
