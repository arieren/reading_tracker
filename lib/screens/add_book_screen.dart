import '../widgets/book_cover.dart';
import '../widgets/reset_draft_on_return.dart';

import 'dart:async';

import '../data/book_repository.dart';
import '../models/book_codec.dart' as validation;
import '../services/catalog_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../models/book.dart';

class AddBookScreen extends StatefulWidget {
  final VoidCallback onBookAdded;

  const AddBookScreen({
    super.key,
    required this.onBookAdded,
    this.repository,
    this.currentUid,
    this.catalog,
    this.isActive = true,
  });
  final BookRepository? repository;
  final String? Function()? currentUid;
  final CatalogService? catalog;
  final bool isActive;

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen>
    with ResetDraftOnReturn<AddBookScreen> {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController chapterController = TextEditingController();
  final TextEditingController imageUrlController = TextEditingController();
  final TextEditingController linkUrlController = TextEditingController();

  Timer? _searchTimer;
  int _searchRevision = 0;
  late final _catalog = widget.catalog ?? CatalogService.instance;
  bool _isSearching = false;
  bool _searched = false;
  String? _searchError;
  BookRepository get _repository =>
      widget.repository ?? BookRepository.instance;

  String selectedType = 'Novel';
  List<dynamic> searchResults = [];
  String? selectedImage;
  String? selectedTitle;
  bool _isManualEntry = false;
  bool _isLoading = false;

  final List<String> bookTypes = ['Novel', 'Manga', 'Manhwa', 'Light Novel'];

  @override
  void initState() {
    super.initState();
    chapterController.text = '1';
  }

  @override
  void didUpdateWidget(covariant AddBookScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      resetDraft();
    }
  }

  @override
  void resetDraft() {
    _isManualEntry = false;
    selectedType = 'Novel';
    _resetForm();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchRevision++;
    titleController.dispose();
    chapterController.dispose();
    imageUrlController.dispose();
    linkUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isManualEntry ? 'Manual Entry' : 'Search & Add'),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                _searchTimer?.cancel();
                _searchRevision++;
                _isManualEntry = !_isManualEntry;
                searchResults = [];
                _isSearching = false;
                _searched = false;
                _searchError = null;
                selectedImage = null;
                if (!_isManualEntry) {
                  imageUrlController.clear();
                  linkUrlController.clear();
                }
              });
            },
            icon: Icon(_isManualEntry ? Icons.search : Icons.edit),
            label: Text(_isManualEntry ? "Use Search" : "Manual Entry"),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) ...[
              LinearProgressIndicator(),
              SizedBox(height: 16),
            ],
            _buildEntryForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitleField(),
        if (!_isManualEntry) ...[
          if (_isSearching) const LinearProgressIndicator(),
          if (_searchError != null)
            Row(
              children: [
                Expanded(child: Text(_searchError!)),
                TextButton(
                  onPressed: () =>
                      _searchManga(titleController.text, ++_searchRevision),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (_searched && !_isSearching && searchResults.isEmpty)
            const Text(
              'No matches found. Try another title or use Manual Entry.',
            ),
        ],
        SizedBox(height: 20),
        if (!_isManualEntry && searchResults.isNotEmpty) _buildSearchResults(),
        if (selectedImage != null || _isManualEntry) _buildImagePreview(),
        SizedBox(height: 20),
        _buildTypeDropdown(),
        SizedBox(height: 20),
        _buildChapterField(),
        SizedBox(height: 20),
        _buildLinkUrlField(),
        if (_isManualEntry) ...[SizedBox(height: 20), _buildImageUrlField()],
        SizedBox(height: 32),
        _buildAddButton(),
      ],
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: titleController,
      decoration: InputDecoration(
        labelText: 'Title',
        hintText: 'Enter book title',
        prefixIcon: Icon(Icons.book),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (value) {
        if (!_isManualEntry) {
          selectedImage = null;
          selectedTitle = null;
          _searchTimer?.cancel();
          final revision = ++_searchRevision;
          setState(() {
            searchResults = [];
            _isSearching = value.trim().isNotEmpty;
            _searched = false;
            _searchError = null;
          });
          if (value.trim().isNotEmpty) {
            _searchTimer = Timer(
              const Duration(milliseconds: 550),
              () => _searchManga(value, revision),
            );
          }
        }
      },
    );
  }

  Widget _buildLinkUrlField() {
    return TextField(
      controller: linkUrlController,
      decoration: InputDecoration(
        labelText: 'Reading Link (optional)',
        hintText: 'Enter URL to continue reading',
        prefixIcon: Icon(Icons.link),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        itemCount: searchResults.length,
        separatorBuilder: (context, index) => Divider(height: 1),
        itemBuilder: (context, index) {
          final manga = searchResults[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: BookCover(
                imageUrl: manga['images']['jpg']['image_url'],
                type: manga['type'] ?? selectedType,
                width: 50,
                height: 70,
              ),
            ),
            title: Text(
              manga['title'] ?? 'Unknown Title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              manga['type'] ?? 'Unknown Type',
              style: TextStyle(fontSize: 12),
            ),
            onTap: () => _onSelectManga(manga),
          );
        },
      ),
    );
  }

  Widget _buildImagePreview() {
    final imageUrl = _isManualEntry
        ? imageUrlController.text.trim()
        : selectedImage;

    return Center(
      child: Column(
        children: [
          BookCover(
            imageUrl: imageUrl,
            type: selectedType,
            width: 150,
            height: 200,
          ),
          const SizedBox(height: 8),
          Text('Cover Image', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Content Type',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedType,
          icon: Icon(Icons.arrow_drop_down),
          isExpanded: true,
          items: bookTypes.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Row(
                children: [_getTypeIcon(type), SizedBox(width: 8), Text(type)],
              ),
            );
          }).toList(),
          onChanged: (value) => setState(() => selectedType = value!),
        ),
      ),
    );
  }

  Widget _getTypeIcon(String type) {
    switch (type) {
      case 'Novel':
        return Icon(Icons.auto_stories, color: Colors.blue);
      case 'Manga':
        return Icon(Icons.photo_album, color: Colors.red);
      case 'Manhwa':
        return Icon(Icons.web_stories, color: Colors.purple);
      case 'Light Novel':
        return Icon(Icons.menu_book, color: Colors.amber.shade800);
      default:
        return Icon(Icons.book);
    }
  }

  Widget _buildChapterField() {
    return TextField(
      controller: chapterController,
      decoration: InputDecoration(
        labelText: 'Current Chapter',
        hintText: 'Enter current chapter number',
        prefixIcon: Icon(Icons.bookmark),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildImageUrlField() {
    return TextField(
      controller: imageUrlController,
      decoration: InputDecoration(
        labelText: 'Image URL (optional)',
        hintText: 'Enter cover image URL',
        prefixIcon: Icon(Icons.image),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (value) {
        setState(() {});
      },
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _addBook,
      icon: Icon(Icons.add),
      label: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text('Add to Library', style: TextStyle(fontSize: 16)),
      ),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _searchManga(String query, int revision) async {
    if (!mounted || revision != _searchRevision || _isManualEntry) return;
    _searchTimer?.cancel();
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await _catalog.search(query);
      if (mounted && revision == _searchRevision && !_isManualEntry) {
        setState(() {
          searchResults = results;
          _searched = true;
        });
      }
    } on Object catch (error) {
      if (mounted && revision == _searchRevision && !_isManualEntry) {
        setState(
          () => _searchError = error is CatalogException
              ? error.message
              : 'Cannot connect to search. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted && revision == _searchRevision && !_isManualEntry) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _onSelectManga(dynamic manga) {
    setState(() {
      _searchRevision++;
      selectedTitle = manga['title'];
      _searchTimer?.cancel();
      _isSearching = false;
      _searched = false;
      _searchError = null;
      selectedImage = manga['images']['jpg']['image_url'];
      titleController.text = selectedTitle!;
      searchResults = [];

      final type = manga['type'];
      if (type != null) {
        if (type == 'Manga') {
          selectedType = 'Manga';
        } else if (type == 'Novel') {
          selectedType = 'Novel';
        } else if (type == 'Light Novel') {
          selectedType = 'Light Novel';
        } else if (type == 'Manhwa') {
          selectedType = 'Manhwa';
        }
      }
    });
  }

  Future<void> _addBook() async {
    if (_isLoading) return;
    final uid = widget.currentUid != null
        ? widget.currentUid!()
        : FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showErrorSnackbar('Please sign in first.');
      return;
    }
    final chapter = int.tryParse(chapterController.text.trim());
    if (chapter == null || chapter < 0) {
      _showErrorSnackbar('Enter a whole chapter number of zero or greater.');
      return;
    }
    final image = _isManualEntry
        ? imageUrlController.text.trim()
        : selectedImage;
    final book = Book(
      title: titleController.text.trim(),
      type: selectedType,
      chapter: chapter,
      imageUrl: image == null || image.isEmpty ? null : image,
      linkURL: linkUrlController.text.trim(),
      uid: uid,
    );
    try {
      validation.validateBook(book);
    } on FormatException catch (e) {
      _showErrorSnackbar(e.message.toString());
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _repository.save(book);
      unawaited(_repository.sync(force: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Book saved on this device. Cloud sync will retry if needed.',
          ),
        ),
      );
      _resetForm();
      widget.onBookAdded();
    } on Object catch (error) {
      debugPrint('Saving book failed: ${error.runtimeType}');
      if (mounted) _showErrorSnackbar('Unable to save. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
    _searchTimer?.cancel();
    _searchRevision++;
    imageUrlController.clear();
    titleController.clear();
    chapterController.text = '1';
    linkUrlController.clear();
    setState(() {
      selectedImage = null;
      selectedTitle = null;
      searchResults = [];
      _isSearching = false;
      _searched = false;
      _searchError = null;
    });
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
