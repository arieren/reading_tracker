import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html/parser.dart' as html;

import '../models/book.dart';
import 'reading_page.dart';
import 'reading_sites.dart';
import 'page_document.dart';

class ReadingSource {
  const ReadingSource(this.label, this.url);
  final String label, url;
  String get _identity =>
      Uri.parse(url)
          .replace(fragment: '')
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
  static const _key = ReadingSiteStore.preferredSourceKey;
  Future<List<ReadingSource>> available() async => [
    for (final site in await sites.load()) ReadingSource(site.name, site.url),
  ];
  Future<ReadingSource?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is Map &&
          data['name'] is String &&
          data['url'] is String &&
          isReadingUrl(data['url'] as String)) {
        final selected = ReadingSource(
          data['name'] as String,
          data['url'] as String,
        );
        return (await available())
            .where((choice) => choice == selected)
            .firstOrNull;
      }
    } on FormatException {
      /* Invalid or removed preferences leave lookup off. */
    }
    return null;
  }

  Future<void> save(ReadingSource? source) async {
    final prefs = await SharedPreferences.getInstance();
    if (source == null) {
      if (!await prefs.remove(_key)) {
        throw StateError('Could not disable automatic lookup.');
      }
      return;
    }
    if (source.label.trim().isEmpty ||
        source.label.length > 80 ||
        !isReadingUrl(source.url)) {
      throw const FormatException('Enter a website name and full web address.');
    }
    if (!(await available()).contains(source)) {
      await sites.add(source.label, source.url);
    }
    if (!await prefs.setString(
      _key,
      jsonEncode({'name': source.label, 'url': source.url}),
    )) {
      throw StateError('Could not save your preferred reading site.');
    }
  }
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
    if (source == null) return null;
    try {
      return await _generic(book, source).timeout(const Duration(seconds: 6));
    } on ReadingSourceException {
      rethrow;
    } on Object {
      throw ReadingSourceException('${source.label} lookup is unavailable.');
    }
  }

  bool _exact(String title, Iterable<dynamic> names) {
    final wanted = normalizedStoryTitle(title);
    return wanted.isNotEmpty &&
        names.whereType<String>().any(
          (name) => normalizedStoryTitle(name) == wanted,
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
