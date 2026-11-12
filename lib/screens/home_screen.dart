import '../widgets/book_metadata.dart';
import '../widgets/library_empty_state.dart';
import '../widgets/book_cover.dart';
import '../widgets/account_button.dart';

import 'dart:async';

import '../data/book_repository.dart';
import '../widgets/book_editor.dart';
import 'reader_screen.dart';

import 'package:material_ui/material_ui.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/book.dart';

import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/book_sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Box<Book> bookBox;
  User? _currentUser;
  final BookSyncService _syncService = BookSyncService();

  @override
  void initState() {
    super.initState();
    bookBox = Hive.box<Book>('books');
    _currentUser = FirebaseAuth.instance.currentUser;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _continueReading(BuildContext context, Book book) =>
      openBookReader(context, book);

  void _showSyncSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _showEditDialog(Book book) async {
    final action = await showBookEditor(context, book);
    if (action != null) {
      unawaited(BookRepository.instance.sync(force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: const [ReaderHelpButton(), AccountButton()],
        title: Text(
          'Recently Read',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        centerTitle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        ),
      ),
      body: ValueListenableBuilder<Box<Book>>(
        valueListenable: bookBox.listenable(),
        builder: (context, box, _) {
          if (_currentUser == null) {
            return _buildNotLoggedIn();
          }

          final allBooks = box.values
              .where((book) => book.uid == _currentUser!.uid)
              .toList();

          allBooks.sort((a, b) {
            final aTime = a.lastRead ?? DateTime(1900);
            final bTime = b.lastRead ?? DateTime(1900);
            return bTime.compareTo(aTime);
          });

          final recentBooks = allBooks.take(10).toList();

          if (recentBooks.isEmpty) {
            return _buildNoBooksAdded();
          }

          return _buildRecentBooksList(recentBooks);
        },
      ),
    );
  }

  Widget _buildNotLoggedIn() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            "Please log in to view your recently read.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildNoBooksAdded() => LibraryEmptyState(
    title: 'Add some books!',
    message: 'Your recently read books will appear here.',
    refresh: () => _syncService.syncBooksFromFirestore(forceSync: true),
  );

  Widget _buildRecentBooksList(List<Book> books) {
    return RefreshIndicator(
      onRefresh: () async {
        final ok = await _syncService.syncBooksFromFirestore(forceSync: true);
        if (mounted) {
          _showSyncSnackbar(
            ok
                ? 'Cloud sync complete'
                : 'Cloud unavailable; showing saved books.',
          );
        }
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return _buildBookCard(book);
        },
      ),
    );
  }

  Widget _buildBookCard(Book book) {
    String lastReadText = 'Never read';
    if (book.lastRead != null) {
      final now = DateTime.now();
      final difference = now.difference(book.lastRead!);

      if (difference.inMinutes < 1) {
        lastReadText = 'Just now';
      } else if (difference.inHours < 1) {
        lastReadText = '${difference.inMinutes} min ago';
      } else if (difference.inDays < 1) {
        lastReadText = '${difference.inHours} hours ago';
      } else if (difference.inDays < 7) {
        lastReadText = '${difference.inDays} days ago';
      } else {
        lastReadText = DateFormat('MMM d, y').format(book.lastRead!);
      }
    }

    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditDialog(book),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCover(
                imageUrl: book.imageUrl,
                type: book.type,
                width: 80,
                height: 120,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    BookMetadata(type: book.type, chapter: book.chapter),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          lastReadText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _continueReading(context, book),
                          icon: Icon(Icons.play_arrow, size: 16),
                          label: Text('Continue'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: Size(100, 32),
                            textStyle: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
