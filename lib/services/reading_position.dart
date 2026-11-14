import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReadingPositionStore {
  Future<void> removeUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'reading_position:${Uri.encodeComponent(uid)}:';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }

  String _key(String uid, String bookId) =>
      'reading_position:${Uri.encodeComponent(uid)}:${Uri.encodeComponent(bookId)}';
  Future<void> save({
    required String uid,
    required String bookId,
    required String url,
    required double offset,
  }) async {
    if (!offset.isFinite || offset < 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(uid, bookId),
      jsonEncode({'url': url, 'offset': offset.clamp(0, 10000000)}),
    );
  }

  Future<double?> read({
    required String uid,
    required String bookId,
    required String url,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key(uid, bookId));
    if (saved == null) return null;
    try {
      final value = jsonDecode(saved);
      if (value is Map && value['url'] == url && value['offset'] is num) {
        final offset = (value['offset'] as num).toDouble();
        if (offset.isFinite && offset >= 0 && offset <= 10000000) return offset;
      }
    } on FormatException {
      /* An invalid local checkpoint can be safely ignored. */
    }
    return null;
  }
}
