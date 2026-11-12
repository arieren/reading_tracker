import 'package:hive/hive.dart';

part 'book.g.dart';

@HiveType(typeId: 0)
class Book extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  String type; // Novel, Manga, Manhwa, Light Novel

  @HiveField(2)
  int chapter;

  @HiveField(3)
  String? imageUrl; // Image URL

  @HiveField(4)
  String? linkURL;

  @HiveField(5)
  String? id; // Firestore Doc ID

  @HiveField(6)
  String? uid; // UID of user who added the book

  @HiveField(7)
  DateTime? lastRead; // Timestamp of when the book was last read

  Book({
    required this.title,
    required this.type,
    required this.chapter,
    this.imageUrl,
    this.linkURL,
    this.id,
    this.uid,
    this.lastRead,
  });
}
