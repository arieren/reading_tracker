import '../data/book_repository.dart';

class BookSyncService {
  Future<bool> syncBooksFromFirestore({bool forceSync = false}) =>
      BookRepository.instance.sync(force: forceSync);
}
