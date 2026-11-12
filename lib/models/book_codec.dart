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
  'lastRead': b.lastRead?.toIso8601String(),
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

void validateBook(Book b) {
  if (b.title.trim().isEmpty) throw const FormatException('Enter a title.');
  if (b.chapter < 0) {
    throw const FormatException('Chapter must be zero or greater.');
  }
  if (!validWebUrl(b.linkURL) || !validWebUrl(b.imageUrl)) {
    throw const FormatException('Links must be valid http or https URLs.');
  }
}
