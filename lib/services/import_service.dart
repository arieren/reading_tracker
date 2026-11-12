import '../models/book.dart';
import '../data/book_repository.dart';

class ImportEntry {
  const ImportEntry(
    this.title,
    this.chapter, {
    this.type = 'Novel',
    this.imageUrl,
  });
  final String title;
  final int chapter;
  final String type;
  final String? imageUrl;

  ImportEntry withCatalogMatch(Map<String, dynamic> match) => ImportEntry(
    match['title'] as String,
    chapter,
    type: match['type'] as String,
    imageUrl: match['images']['jpg']['image_url'] as String,
  );
}

List<ImportEntry> parseBookImport(String text) {
  final entries = <ImportEntry>[];
  for (final raw in text.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    line = line.replaceFirst(RegExp(r'^[-*]\s+'), '');
    if (RegExp(r'\bfinished\b', caseSensitive: false).hasMatch(line) &&
        !RegExp(r'\d').hasMatch(line)) {
      throw const FormatException(
        'Completed entries need an explicit chapter number.',
      );
    }
    line = line
        .replaceAll(RegExp(r'\bnot started\b', caseSensitive: false), '0')
        .replaceAll(
          RegExp(r'\bfinished\b|\bchapter\b', caseSensitive: false),
          '',
        )
        .trim();
    final match = RegExp(r'^(.*?)\s+(-?\d+)$').firstMatch(line);
    final title = match == null ? line : match[1]!.trim();
    final chapter = match == null ? 0 : int.parse(match[2]!);
    if (title.isEmpty || chapter < 0) {
      throw FormatException('Invalid import entry: $raw');
    }
    entries.add(ImportEntry(title, chapter));
  }
  if (entries.isEmpty) throw const FormatException('Paste at least one book.');
  return entries;
}

class BookImportService {
  BookImportService(this.repository);
  final BookRepository repository;
  Future<int> import(List<ImportEntry> entries, String uid) async {
    final titles = repository.userBooks
        .map((b) => b.title.trim().toLowerCase())
        .toSet();
    var added = 0;
    for (final entry in entries) {
      if (repository.currentUid() != uid) {
        throw StateError('Your account changed. Import stopped.');
      }
      if (!titles.add(entry.title.toLowerCase())) continue;
      await repository.save(
        Book(
          title: entry.title,
          type: entry.type,
          imageUrl: entry.imageUrl,
          chapter: entry.chapter,
          uid: uid,
        ),
      );
      added++;
    }
    return added;
  }
}
