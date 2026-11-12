import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book_codec.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogService {
  CatalogService({this.request = http.get});
  static final instance = CatalogService();
  final Future<http.Response> Function(Uri) request;
  final _pending = <String, Future<List<Map<String, dynamic>>>>{};
  final _cache =
      <String, ({DateTime expires, List<Map<String, dynamic>> rows})>{};
  DateTime? _nextRequest;
  DateTime? _retryAfter;

  Future<List<Map<String, dynamic>>> search(String query) async {
    final title = query.trim();
    if (title.isEmpty) return [];
    final key = title.toLowerCase();
    final cached = _cache[key];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return _copy(cached.rows);
    }
    final pending = _pending[key];
    if (pending != null) return _copy(await pending);
    final operation = _search(title);
    _pending[key] = operation;
    try {
      final rows = await operation;
      if (_cache.length >= 40) _cache.remove(_cache.keys.first);
      _cache[key] = (
        expires: DateTime.now().add(const Duration(minutes: 5)),
        rows: rows,
      );
      return _copy(rows);
    } finally {
      _pending.remove(key);
    }
  }

  // Callers receive their own maps so selecting/editing a result cannot alter
  // a cached result used by the other search screen.
  List<Map<String, dynamic>> _copy(List<Map<String, dynamic>> rows) => rows
      .map(
        (row) => {
          ...row,
          'images': {
            'jpg': {...row['images']['jpg'] as Map},
          },
        },
      )
      .toList();

  Future<List<Map<String, dynamic>>> _search(String title) async {
    final now = DateTime.now();
    if (_retryAfter?.isAfter(now) ?? false) {
      throw const CatalogException(
        'Search is busy. Please wait a minute and retry.',
      );
    }
    // Tenrai public access permits 120 requests/minute and 4/second per IP.
    // Space starts across Add Book and Import, including overlapping requests.
    final start = _nextRequest != null && _nextRequest!.isAfter(now)
        ? _nextRequest!
        : now;
    _nextRequest = start.add(const Duration(milliseconds: 550));
    final wait = start.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (_retryAfter?.isAfter(DateTime.now()) ?? false) {
      throw const CatalogException(
        'Search is busy. Please wait a minute and retry.',
      );
    }
    late http.Response response;
    try {
      response = await request(
        Uri.https('api.tenrai.org', '/v1/manga', {'q': title, 'limit': '5'}),
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const CatalogException('Search timed out. Please retry.');
    } on http.ClientException {
      throw const CatalogException(
        'Cannot connect to search. Check your connection and retry.',
      );
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 429) {
        final value = response.headers['retry-after'];
        final seconds = int.tryParse(value ?? '');
        _retryAfter = seconds != null && seconds > 0
            ? DateTime.now().add(Duration(seconds: seconds))
            : DateTime.tryParse(value ?? '') ??
                  DateTime.now().add(const Duration(minutes: 1));
      }
      throw CatalogException(
        response.statusCode == 429
            ? 'Search is busy. Please wait a minute and retry.'
            : 'Catalog unavailable. Please retry or use manual entry.',
      );
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const CatalogException(
        'Search returned an invalid response. Please retry.',
      );
    }
    if (data is! Map || data['data'] is! List) {
      throw const CatalogException(
        'Search returned an invalid response. Please retry.',
      );
    }
    final results = <Map<String, dynamic>>[];
    for (final row in data['data'] as List) {
      if (row is! Map ||
          row['title'] is! String ||
          (row['title'] as String).trim().isEmpty) {
        continue;
      }
      final images = row['images'];
      final jpg = images is Map ? images['jpg'] : null;
      final image = jpg is Map ? jpg['image_url'] : null;
      results.add({
        'title': row['title'],
        'type': switch (row['type']) {
          'One-shot' || 'Doujinshi' || 'Manhua' || 'OEL' => 'Manga',
          final String type => normalizeBookType(type),
          _ => 'Novel',
        },
        'images': {
          'jpg': {
            'image_url': image is String && validWebUrl(image) ? image : '',
          },
        },
      });
    }
    return results;
  }
}
