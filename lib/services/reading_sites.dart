import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'reading_page.dart';

class ReadingSite {
  const ReadingSite({required this.name, required this.url});
  final String name;
  final String url;
}

/// Website shortcuts are device preferences, independent of library/cloud data.
class ReadingSiteStore {
  static const preferredSourceKey = 'preferred_reading_site';
  static const _key = 'reading_sites';

  Future<List<ReadingSite>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sites = <ReadingSite>[];
    for (final raw in prefs.getStringList(_key) ?? <String>[]) {
      try {
        final data = jsonDecode(raw);
        if (data is! Map || data['name'] is! String || data['url'] is! String) {
          continue;
        }
        final name = (data['name'] as String).trim();
        final url = (data['url'] as String).trim();
        if (name.isEmpty || name.length > 80 || !isReadingUrl(url)) continue;
        if (!sites.any((site) => _sameUrl(site.url, url))) {
          sites.add(ReadingSite(name: name, url: url));
        }
      } on FormatException {
        // Ignore an invalid saved shortcut without losing the others.
      }
    }
    return sites;
  }

  Future<void> add(String name, String url) async {
    name = name.trim();
    url = normalizeWebAddress(url);
    if (name.isEmpty || name.length > 80) {
      throw const FormatException(
        'Enter a website name (up to 80 characters).',
      );
    }
    if (!isReadingUrl(url)) {
      throw const FormatException(
        'Enter a valid website address, such as example.com.',
      );
    }
    final sites = await load();
    if (sites.any((site) => _sameUrl(site.url, url))) {
      throw const FormatException('This website is already saved.');
    }
    await _write([...sites, ReadingSite(name: name, url: url)]);
  }

  Future<void> remove(ReadingSite site) async {
    final sites = await load();
    await _write(sites.where((saved) => !_sameUrl(saved.url, site.url)));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferredSourceKey);
    if (raw != null) {
      try {
        final selected = jsonDecode(raw);
        if (selected is Map &&
            selected['url'] is String &&
            _sameUrl(selected['url'] as String, site.url)) {
          await prefs.remove(preferredSourceKey);
        }
      } on FormatException {
        /* Invalid preferences are ignored on load. */
      }
    }
  }

  Future<void> _write(Iterable<ReadingSite> sites) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(_key, [
      for (final site in sites)
        jsonEncode({'name': site.name, 'url': site.url}),
    ]);
    if (!saved) throw StateError('Unable to save website shortcuts.');
  }

  bool _sameUrl(String a, String b) => _canonicalUrl(a) == _canonicalUrl(b);

  String _canonicalUrl(String url) =>
      Uri.parse(url)
          .toString()
          .split('#')
          .first
          .replaceFirst(RegExp(r'/$'), '');
}
