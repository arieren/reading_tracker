import 'package:cloud_firestore/cloud_firestore.dart';

import 'book.dart';

const bookTypes = ['Novel', 'Manga', 'Manhwa', 'Light Novel'];
String normalizeBookType(String? value) =>
    bookTypes.contains(value) ? value! : 'Novel';
bool validWebUrl(String? value) {
  if (value == null || value.trim().isEmpty) return true;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      ['http', 'https'].contains(uri.scheme) &&
      uri.host.isNotEmpty;
}

Map<String, dynamic> encodeBook(Book b) => {
  'uid': b.uid,
  'title': b.title.trim(),
  'type': normalizeBookType(b.type),
  'chapter': b.chapter,
  'imageUrl': b.imageUrl ?? '',
  'linkURL': b.linkURL ?? '',
  'lastRead': b.lastRead?.toUtc().toIso8601String(),
};

// Hive journals retain primitives; only the Firestore boundary uses Timestamp.
Map<String, dynamic> normalizeCloudBook(Map<String, dynamic> data) => {
  ...data,
  'lastRead': switch (data['lastRead']) {
    final Timestamp value => value.toDate().toUtc().toIso8601String(),
    final String value => DateTime.tryParse(value)?.toUtc().toIso8601String(),
    _ => null,
  },
}..remove('updatedAt');

Map<String, dynamic> cloudBookFields(
  Map<String, dynamic> data, {
  bool legacyLastRead = false,
}) => {
  for (final key in ['uid', 'title', 'type', 'chapter', 'imageUrl', 'linkURL'])
    key: data[key],
  'lastRead': legacyLastRead
      ? data['lastRead']
      : data['lastRead'] is String
      ? Timestamp.fromDate(DateTime.parse(data['lastRead'] as String).toUtc())
      : data['lastRead'],
};
Book decodeBook(String id, Map<String, dynamic> data) {
  final title = data['title'];
  final chapter = data['chapter'];
  final time = data['lastRead'];
  if (title is! String ||
      title.trim().isEmpty ||
      chapter is! num ||
      chapter < 0 ||
      chapter != chapter.roundToDouble() ||
      data['uid'] is! String) {
    throw const FormatException('Invalid book record');
  }
  return Book(
    id: id,
    uid: data['uid'] as String,
    title: title,
    chapter: chapter.toInt(),
    type: normalizeBookType(data['type'] as String?),
    imageUrl: data['imageUrl'] as String?,
    linkURL: data['linkURL'] as String?,
    lastRead: time is Timestamp
        ? time.toDate()
        : time is String
        ? DateTime.tryParse(time)
        : null,
  );
}

void validateBook(Book b, {Book? original}) {
  if (b.title.trim().isEmpty) throw const FormatException('Enter a title.');
  if (b.title.trim().length > 500) {
    throw const FormatException('Titles must be 500 characters or fewer.');
  }
  if (b.chapter < 0 || b.chapter > 2147483647) {
    throw const FormatException('Chapter must be zero or greater.');
  }
  final keptReadingText =
      original != null &&
      original.uid == b.uid &&
      original.id == b.id &&
      original.linkURL == b.linkURL;
  if ((!validWebUrl(b.linkURL) && !keptReadingText) ||
      !validWebUrl(b.imageUrl)) {
    throw const FormatException('Links must be valid http or https URLs.');
  }
  if ((b.linkURL?.length ?? 0) > 4096 || (b.imageUrl?.length ?? 0) > 4096) {
    throw const FormatException('Links must be 4096 characters or fewer.');
  }
}
