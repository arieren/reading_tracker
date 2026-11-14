import 'package:material_ui/material_ui.dart';

import '../models/book.dart';
import '../models/book_codec.dart';
import '../data/book_repository.dart';
import 'book_cover.dart';

enum BookEditorAction { saved, read }

Future<BookEditorAction?> showBookEditor(
  BuildContext context,
  Book book, {
  bool allowRead = false,
}) => Navigator.of(context).push<BookEditorAction>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _BookEditor(book: book, allowRead: allowRead),
  ),
);

class _BookEditor extends StatefulWidget {
  const _BookEditor({required this.book, required this.allowRead});
  final Book book;
  final bool allowRead;
  @override
  State<_BookEditor> createState() => _BookEditorState();
}

class _BookEditorState extends State<_BookEditor> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _chapter = TextEditingController(text: '${widget.book.chapter}');
  late final _link = TextEditingController(text: widget.book.linkURL ?? '');
  late final _image = TextEditingController(text: widget.book.imageUrl ?? '');
  late String _type = normalizeBookType(widget.book.type);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _chapter.dispose();
    _link.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _save(BookEditorAction action) async {
    if (_busy) return;
    final chapter = int.tryParse(_chapter.text);
    if (chapter == null || chapter < 0) {
      setState(() => _error = 'Enter a whole chapter number, zero or higher.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final original = widget.book;
      final edited = Book(
        id: original.id,
        uid: original.uid,
        title: _title.text.trim(),
        type: _type,
        chapter: chapter,
        linkURL: _link.text == original.linkURL
            ? original.linkURL
            : _link.text.trim(),
        imageUrl: _image.text.trim(),
        lastRead: original.lastRead,
      );
      await BookRepository.instance.save(edited, original: original);
      if (mounted) Navigator.pop(context, action);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : 'Unable to save. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: const Text('Edit book'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _save(BookEditorAction.saved),
            child: Text(_busy ? 'Saving…' : 'Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCover(
                      imageUrl: widget.book.imageUrl,
                      type: _type,
                      width: 64,
                      height: 92,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.book.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Update your details and reading progress.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                TextField(
                  controller: _title,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: bookTypes
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _type = value!),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _chapter,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Chapter'),
                ),
                const SizedBox(height: 28),
                Text('Reading', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _link,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Reading link (optional)',
                    helperText: validWebUrl(widget.book.linkURL)
                        ? 'The page to open when you tap Read.'
                        : 'Saved text will be kept. Replace it with a full web address to use it as a link.',
                    helperMaxLines: 4,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _image,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Image link (optional)',
                    helperText: 'Leave blank to use the book placeholder.',
                    helperMaxLines: 2,
                  ),
                ),
                if (widget.allowRead) ...[
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _save(BookEditorAction.read),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Save and read'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
