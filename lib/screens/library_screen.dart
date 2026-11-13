import '../widgets/book_metadata.dart';
import '../widgets/library_empty_state.dart';
import '../widgets/book_cover.dart';

import 'dart:async';

import '../data/book_repository.dart';
import '../widgets/book_editor.dart';
import 'reader_screen.dart';

import 'package:material_ui/material_ui.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/book.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/book_sync_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Box<Book> bookBox;
  String _sortOption = 'Title';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isCardView = false;
  static const String _viewPreferenceKey = 'library_view_preference';

  bool _isEditingMode = false;
  final Set<Book> _selectedBooks = {};

  final BookSyncService _syncService = BookSyncService();

  @override
  void initState() {
    super.initState();
    bookBox = Hive.box<Book>('books');
    _loadViewPreference();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isCardView = prefs.getBool(_viewPreferenceKey) ?? true;
    });
  }

  // New method to handle reading a book from the library
  Future<void> _readBook(BuildContext context, Book book) =>
      openBookReader(context, book);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _isEditingMode && _selectedBooks.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _deleteSelectedBooks,
              backgroundColor: Colors.red,
              icon: Icon(Icons.delete),
              label: Text('Delete'),
              heroTag: 'delete',
            )
          : null,
    );
  }

  AppBar _buildAppBar() {
    if (_isEditingMode) {
      return AppBar(
        title: Text(
          _selectedBooks.isEmpty
              ? 'Select items'
              : '${_selectedBooks.length} selected',
        ),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () {
            setState(() {
              _isEditingMode = false;
              _selectedBooks.clear();
            });
          },
        ),
      );
    } else {
      return AppBar(
        title: Text('Library'),
        actions: [
          _buildViewToggle(),
          _buildSortDropdown(),
          IconButton(
            tooltip: 'Select books',
            icon: Icon(Icons.edit),
            onPressed: () {
              setState(() {
                _isEditingMode = true;
              });
            },
          ),
        ],
      );
    }
  }

  Widget _buildViewToggle() {
    return IconButton(
      icon: Icon(_isCardView ? Icons.view_list : Icons.grid_view),
      tooltip: _isCardView ? 'Switch to List View' : 'Switch to Card View',
      onPressed: () async {
        setState(() {
          _isCardView = !_isCardView;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_viewPreferenceKey, _isCardView);
      },
    );
  }

  Widget _buildSortDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: DropdownButton<String>(
        underline: Container(),
        icon: Icon(Icons.sort),
        value: _sortOption,
        onChanged: (newValue) {
          setState(() {
            _sortOption = newValue!;
          });
        },
        items: ['Title', 'Chapter'].map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Row(
              children: [
                Icon(
                  value == 'Title'
                      ? Icons.sort_by_alpha
                      : Icons.format_list_numbered,
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(value),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        if (!_isEditingMode) _buildSearchBar(),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: bookBox.listenable(),
            builder: (context, Box<Book> box, _) {
              return _isCardView ? _buildBookGrid(box) : _buildBookList(box);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search for a book...',
          hintStyle: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium?.color
                ?.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Theme.of(context).iconTheme.color,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          contentPadding: EdgeInsets.symmetric(vertical: 0),
        ),
        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
        onChanged: (query) {
          setState(() {
            _searchQuery = query;
          });
        },
      ),
    );
  }

  List<Book> _getFilteredAndSortedBooks() {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';

    final books = bookBox.values
        .where(
          (book) =>
              book.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
              book.uid == userId,
        )
        .toList();

    if (_sortOption == 'Title') {
      books.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    } else if (_sortOption == 'Chapter') {
      books.sort((a, b) => a.chapter.compareTo(b.chapter));
    }

    return books;
  }

  Widget _buildBookGrid(Box<Book> box) {
    final books = _getFilteredAndSortedBooks();

    if (books.isEmpty) {
      return _buildEmptyState();
    }

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 16.0,
            childAspectRatio: 0.65,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            return _buildBookCard(book);
          },
        ),
      ),
    );
  }

  Widget _buildBookList(Box<Book> box) {
    final books = _getFilteredAndSortedBooks();

    if (books.isEmpty) {
      return _buildEmptyState();
    }

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
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(vertical: 8.0),
        itemCount: books.length,
        separatorBuilder: (context, index) => Divider(height: 1),
        itemBuilder: (context, index) {
          final book = books[index];
          return _buildBookListItem(book);
        },
      ),
    );
  }

  Widget _buildEmptyState() => LibraryEmptyState(
    title: 'No books found',
    message: _searchQuery.isEmpty
        ? 'Add books to your library.'
        : 'Try a different search term.',
    refresh: () => _syncService.syncBooksFromFirestore(forceSync: true),
  );

  Widget _buildBookCard(Book book) {
    bool isSelected = _selectedBooks.contains(book);

    return GestureDetector(
      onTap: () {
        if (_isEditingMode) {
          setState(() {
            if (isSelected) {
              _selectedBooks.remove(book);
            } else {
              _selectedBooks.add(book);
            }
          });
        } else {
          _showEditDialog(book);
        }
      },
      onLongPress: () {
        if (!_isEditingMode) {
          setState(() {
            _isEditingMode = true;
            _selectedBooks.add(book);
          });
        }
      },
      child: Card(
        elevation: isSelected ? 6.0 : 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected
              ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
              : BorderSide.none,
        ),
        color: Theme.of(context).cardColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(imageUrl: book.imageUrl, type: book.type),
                  if (isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          color: Theme.of(context).primaryColor,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  SizedBox(height: 4),
                  BookMetadata(type: book.type, chapter: book.chapter),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookListItem(Book book) {
    bool isSelected = _selectedBooks.contains(book);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      onTap: () {
        if (_isEditingMode) {
          setState(() {
            if (isSelected) {
              _selectedBooks.remove(book);
            } else {
              _selectedBooks.add(book);
            }
          });
        } else {
          _showEditDialog(book);
        }
      },
      onLongPress: () {
        if (!_isEditingMode) {
          setState(() {
            _isEditingMode = true;
            _selectedBooks.add(book);
          });
        }
      },
      tileColor: isSelected
          ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
          : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected
            ? BorderSide(color: Theme.of(context).primaryColor, width: 1)
            : BorderSide.none,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bookTypeColor(book.type).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            book.title.isNotEmpty ? book.title[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: bookTypeColor(book.type),
              fontSize: 18,
            ),
          ),
        ),
      ),
      title: Text(
        book.title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        book.type,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Ch. ${book.chapter}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(
                Icons.check_circle,
                color: Theme.of(context).primaryColor,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(Book book) async {
    final action = await showBookEditor(context, book, allowRead: true);
    if (action == null) return;
    unawaited(BookRepository.instance.sync(force: true));
    if (action == BookEditorAction.read && mounted) {
      final updated = BookRepository.instance.userBooks.firstWhere(
        (b) => b.id == book.id,
      );
      await _readBook(context, updated);
    }
  }

  void _deleteSelectedBooks() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Books'),
        content: Text(
          'Are you sure you want to delete ${_selectedBooks.length} ${_selectedBooks.length == 1 ? 'book' : 'books'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performDelete();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  bool _deleting = false;
  Future<void> _performDelete() async {
    if (_deleting) return;
    _deleting = true;
    try {
      await BookRepository.instance.deleteBooks(_selectedBooks.toList());
      unawaited(BookRepository.instance.sync(force: true));
      if (!mounted) return;
      setState(() {
        _selectedBooks.clear();
        _isEditingMode = false;
      });
      _showSyncSnackbar(
        'Deleted on this device. Cloud deletion will retry if needed.',
      );
    } on Object catch (_) {
      if (mounted) _showErrorSnackbar('Unable to delete. Please try again.');
    } finally {
      _deleting = false;
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSyncSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 1)),
    );
  }
}

// WebViewScreen class (same as in your home screen)
