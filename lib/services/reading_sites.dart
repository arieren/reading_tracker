import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'reading_page.dart';

class ReadingSite {
  const ReadingSite({
    required this.name,
    required this.url,
    this.builtIn = false,
  });
  final String name;
  final String url;
  final bool builtIn;
}

/// Website shortcuts are device preferences, independent of library/cloud data.
class ReadingSiteStore {
  static const _key = 'reading_sites';
  static const defaults = [
    ReadingSite(name: 'Atsu', url: 'https://atsu.moe/explore', builtIn: true),
  ];

  Future<List<ReadingSite>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sites = <ReadingSite>[...defaults];
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
    url = url.trim();
    if (name.isEmpty || name.length > 80) {
      throw const FormatException(
        'Enter a website name (up to 80 characters).',
      );
    }
    if (!isReadingUrl(url)) {
      throw const FormatException(
        'Enter a full http:// or https:// address without login details.',
      );
    }
    final sites = await load();
    if (sites.any((site) => _sameUrl(site.url, url))) {
      throw const FormatException('This website is already saved.');
    }
    await _write([...sites, ReadingSite(name: name, url: url)]);
  }

  Future<void> remove(ReadingSite site) async {
    if (site.builtIn) return;
    final sites = await load();
    await _write(
      sites.where((saved) => saved.builtIn || saved.url != site.url),
    );
  }

  Future<void> _write(Iterable<ReadingSite> sites) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(_key, [
      for (final site in sites.where((site) => !site.builtIn))
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
