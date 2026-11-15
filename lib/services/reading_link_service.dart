import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import 'reading_page.dart';
import 'reading_sites.dart';
import 'page_document.dart';

import 'package:html/parser.dart' as html;

class ReadingSource {
  const ReadingSource(this.label, this.url);
  static const atsu = ReadingSource('Atsu', 'https://atsu.moe/explore');
  // Kept for preference migration and the optional provider adapter, not as a
  // fixed settings menu. The menu is populated from the user's saved websites.
  static const mangaFire = ReadingSource('MangaFire', 'https://mangafire.to/');
  final String label, url;
  String get host => Uri.parse(url).host.toLowerCase();
  String get _identity =>
      Uri.parse(url)
          .toString()
          .split('#')
          .first
          .replaceFirst(RegExp(r'/$'), '');
  @override
  bool operator ==(Object other) =>
      other is ReadingSource && other._identity == _identity;
  @override
  int get hashCode => _identity.hashCode;
}

class ReadingSourcePreferences {
  ReadingSourcePreferences({ReadingSiteStore? sites})
    : sites = sites ?? ReadingSiteStore();
  final ReadingSiteStore sites;
  static const _key = 'preferred_reading_site';
  Future<List<ReadingSource>> available() async => [
    for (final site in await sites.load()) ReadingSource(site.name, site.url),
  ];
  Future<ReadingSource> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        if (data is Map &&
            data['name'] is String &&
            data['url'] is String &&
            isReadingUrl(data['url'] as String)) {
          final source = ReadingSource(
            data['name'] as String,
            data['url'] as String,
          );
          final choices = await available();
          return choices.where((choice) => choice == source).firstOrNull ??
              ReadingSource.atsu;
        }
      } on FormatException {
        /* A broken preference must not block adding books. */
      }
      return ReadingSource.atsu;
    }
    if (prefs.getString('preferred_reading_source') == 'mangaFire') {
      await save(ReadingSource.mangaFire);
      return ReadingSource.mangaFire;
    }
    return ReadingSource.atsu;
  }

  Future<void> save(ReadingSource source) async {
    if (source.label.trim().isEmpty ||
        source.label.length > 80 ||
        !isReadingUrl(source.url)) {
      throw const FormatException('Enter a website name and full web address.');
    }
    if (!(await available()).contains(source)) {
      await sites.add(source.label, source.url);
    }
    if (!await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({'name': source.label, 'url': source.url}),
    )) {
      throw StateError('Could not save your preferred reading site.');
    }
  }
}

String? atsuPosterUrl(dynamic poster) {
  if (poster is! Map) return null;
  final value =
      poster['image'] ?? poster['mediumImage'] ?? poster['largeImage'];
  if (value is! String || value.trim().isEmpty) return null;
  if (isReadingUrl(value)) return value;
  final path = value
      .replaceFirst(RegExp(r'^/?static/'), '')
      .replaceFirst(RegExp(r'^/'), '');
  if (!path.startsWith('posters/') || path.contains('..')) return null;
  return Uri.parse('https://cdn.atsu.moe/static/').resolve(path).toString();
}

class ReadingLinkMatch {
  const ReadingLinkMatch(this.url, {this.image});
  final String url;
  final String? image;
}

class ReadingSourceException implements Exception {
  const ReadingSourceException(this.message);
  final String message;
}

class ReadingLinkService {
  ReadingLinkService({
    this.request = http.get,
    ReadingSourcePreferences? preferences,
  }) : preferences = preferences ?? ReadingSourcePreferences();
  static final instance = ReadingLinkService();
  final Future<http.Response> Function(Uri) request;
  final ReadingSourcePreferences preferences;
  static bool supports(String type) =>
      ['Manga', 'Manhwa', 'Light Novel'].contains(type);

  Future<ReadingLinkMatch?> find(Book book) async {
    if (!supports(book.type) || (book.linkURL ?? '').trim().isNotEmpty) {
      return null;
    }
    final source = await preferences.load();
    try {
      return await (source.host == 'atsu.moe' ||
                  source.host.endsWith('.atsu.moe')
              ? _atsu(book)
              : source.host == 'mangafire.to' ||
                    source.host.endsWith('.mangafire.to')
              ? _mangaFire(book)
              : _generic(book, source))
          .timeout(const Duration(seconds: 6));
    } on ReadingSourceException {
      rethrow;
    } on Object {
      throw ReadingSourceException('${source.label} lookup is unavailable.');
    }
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await request(uri).timeout(const Duration(seconds: 3));
    if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
      throw const ReadingSourceException(
        'The reading site did not allow this lookup.',
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const ReadingSourceException('Invalid reading-site response.');
    }
    return data;
  }

  bool _exact(String title, Iterable<dynamic> names) {
    final wanted = normalizedStoryTitle(title);
    return wanted.isNotEmpty &&
        names.whereType<String>().any(
          (name) => normalizedStoryTitle(name) == wanted,
        );
  }

  Future<ReadingLinkMatch?> _atsu(Book book) async {
    final novel = book.type == 'Light Novel';
    final data = await _json(
      Uri.https('atsu.moe', '/collections/manga/documents/search', {
        'q': book.title,
        'query_by': 'title,englishTitle,otherNames',
        'num_typos': '0',
        'prefix': 'false',
        'filter_by': 'hidden:!=true && medium:=${novel ? 'Novel' : 'Comic'}',
        'per_page': '20',
        'page': '1',
      }),
    );
    final matches = <String, Map>{};
    for (final hit
        in data['hits'] is List ? data['hits'] as List : <dynamic>[]) {
      final row = hit is Map ? hit['document'] : null;
      if (row is! Map || row['medium'] != (novel ? 'Novel' : 'Comic')) continue;
      if (!_exact(book.title, [
        row['title'],
        row['englishTitle'],
        ...(row['otherNames'] is List
            ? row['otherNames'] as List
            : <dynamic>[]),
      ])) {
        continue;
      }
      final id = row['id'];
      if (id is String && RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
        matches[id] = row;
      }
    }
    final canonical = Map<String, Map>.fromEntries(
      matches.entries.where(
        (entry) => _exact(book.title, [entry.value['title']]),
      ),
    );
    final candidates = canonical.isNotEmpty ? canonical : matches;
    if (candidates.length != 1) return null;
    final id = candidates.keys.single;
    final detail = await _json(
      Uri.https('atsu.moe', '/api/manga/page', {'id': id}),
    );
    final page = detail['mangaPage'];
    if (page is! Map ||
        page['id'] != id ||
        page['medium'] != (novel ? 'Novel' : 'Comic') ||
        !_exact(book.title, [
          page['title'],
          page['englishTitle'],
          ...(page['otherNames'] is List
              ? page['otherNames'] as List
              : <dynamic>[]),
        ])) {
      return null;
    }
    var path = '/${novel ? 'novel' : 'manga'}/$id';
    final chapters = page['chapters'];
    if (chapters is List) {
      final exact = chapters.whereType<Map>().where(
        (chapter) =>
            chapter['number'] == book.chapter &&
            chapter['id'] is String &&
            RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(chapter['id'] as String),
      );
      if (exact.isNotEmpty) {
        path = '/${novel ? 'read-novel' : 'read'}/$id/${exact.first['id']}';
      }
    }
    // Novel chapter routes differ between sites; the verified series page is a
    // safe destination for novels and for chapters absent from the page listing.
    if (novel) path = '/novel/$id';
    return ReadingLinkMatch(
      Uri.https('atsu.moe', path).toString(),
      image: atsuPosterUrl(page['poster']),
    );
  }

  Future<ReadingLinkMatch?> _mangaFire(Book book) async {
    if (book.type == 'Light Novel') {
      return null; // MangaFire's title API is comics-only.
    }
    final data = await _json(
      Uri.https('mangafire.to', '/api/titles', {
        'keyword': book.title,
        'limit': '20',
      }),
    );
    final matches = <String, Map>{};
    for (final row
        in data['items'] is List ? data['items'] as List : <dynamic>[]) {
      if (row is! Map ||
          !_exact(book.title, [
            row['title'],
            ...(row['altTitles'] is List
                ? row['altTitles'] as List
                : <dynamic>[]),
          ])) {
        continue;
      }
      final id = row['hid'];
      if (id is String && RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
        matches[id] = row;
      }
    }
    if (matches.length != 1) return null;
    final row = matches.values.single;
    final slug = row['slug'];
    final path = slug is String && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(slug)
        ? '${matches.keys.single}-$slug'
        : matches.keys.single;
    final poster = row['poster'];
    final image = poster is Map ? poster['medium'] : poster;
    return ReadingLinkMatch(
      Uri.https('mangafire.to', '/title/$path').toString(),
      image: image is String && isReadingUrl(image) ? image : null,
    );
  }

  Future<ReadingLinkMatch?> _generic(Book book, ReadingSource source) async {
    final base = Uri.parse(source.url);
    Future<String> read(Uri url) async {
      final response = await request(url).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
        throw const ReadingSourceException(
          'The reading site did not allow this lookup.',
        );
      }
      return utf8.decode(response.bodyBytes);
    }

    var pageUrl = base;
    var markup = await read(base);
    var document = html.parse(markup);
    // Follow only an explicitly declared same-origin GET search form. Do not
    // invent /search routes, replay hidden tokens, or submit login forms.
    for (final form in document.querySelectorAll('form')) {
      final method = (form.attributes['method'] ?? 'get').toLowerCase();
      final input = form.querySelector(
        'input[type="search"],input[name="q"],input[name="s"],input[name="search"],input[name="keyword"],input[name="query"]',
      );
      final name = input?.attributes['name'];
      if (method != 'get' ||
          name == null ||
          form.querySelector('input[type="password"]') != null) {
        continue;
      }
      final action = base.resolve(form.attributes['action'] ?? '');
      if (!isReadingUrl(action.toString()) || action.origin != base.origin) {
        continue;
      }
      pageUrl = action.replace(
        queryParameters: {...action.queryParameters, name: book.title},
      );
      markup = await read(pageUrl);
      document = html.parse(markup);
      break;
    }
    final candidates = <String, Uri>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final label = anchor.attributes['title']?.trim().isNotEmpty == true
          ? anchor.attributes['title']!
          : anchor.text.trim();
      if (!_exact(book.title, [label])) continue;
      final url = pageUrl.resolve(anchor.attributes['href']!);
      if (!isReadingUrl(url.toString()) || url.origin != base.origin) continue;
      final canonical = url.replace(fragment: '').toString().split('#').first;
      candidates[canonical] = Uri.parse(canonical);
    }
    if (candidates.length != 1) return null;
    final destination = candidates.values.single;
    final detail = extractPageDocument(
      await read(destination),
      destination.toString(),
    );
    final name = detail['title']?.toString().isNotEmpty == true
        ? detail['title'].toString()
        : detail['series']?.toString().isNotEmpty == true
        ? detail['series'].toString()
        : detail['heading']?.toString().isNotEmpty == true
        ? detail['heading'].toString()
        : detail['documentTitle']?.toString() ?? '';
    final title = suggestedStoryTitle(
      stripReadingSiteName(name, detail['siteName']?.toString() ?? ''),
    );
    if (!_exact(book.title, [title])) return null;
    final type = detail['type'];
    if (type is String &&
        type.isNotEmpty &&
        ((book.type == 'Light Novel') !=
            ['Novel', 'Light Novel'].contains(type))) {
      return null;
    }
    return ReadingLinkMatch(
      destination.toString(),
      image:
          detail['image'] is String && isReadingUrl(detail['image'] as String)
          ? detail['image'] as String
          : null,
    );
  }
}
