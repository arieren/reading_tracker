import 'package:material_ui/material_ui.dart';

import '../models/book.dart';
import '../models/book_codec.dart';
import '../data/book_repository.dart';

enum BookEditorAction { saved, read }

Future<BookEditorAction?> showBookEditor(
  BuildContext context,
  Book book, {
  bool allowRead = false,
}) => showDialog<BookEditorAction>(
  context: context,
  builder: (_) => _BookEditor(book: book, allowRead: allowRead),
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
    if (chapter == null) {
      setState(() => _error = 'Enter a whole chapter number.');
      return;
    }
    setState(() => _busy = true);
    try {
      final original = widget.book;
      final edited = Book(
        id: original.id,
        uid: original.uid,
        title: _title.text.trim(),
        type: _type,
        chapter: chapter,
        linkURL: _link.text.trim(),
        imageUrl: _image.text.trim(),
        lastRead: original.lastRead,
      );
      await BookRepository.instance.save(edited, original: original);
      if (mounted) Navigator.pop(context, action);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
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
    child: AlertDialog(
      title: const Text('Edit Book'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _chapter,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chapter'),
            ),
            TextField(
              controller: _link,
              decoration: const InputDecoration(
                labelText: 'Reading link (optional)',
              ),
            ),
            TextField(
              controller: _image,
              decoration: const InputDecoration(
                labelText: 'Image link (optional)',
              ),
            ),
            DropdownButton<String>(
              value: _type,
              isExpanded: true,
              items: bookTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _type = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.allowRead)
          TextButton(
            onPressed: _busy ? null : () => _save(BookEditorAction.read),
            child: const Text('Read'),
          ),
        ElevatedButton(
          onPressed: _busy ? null : () => _save(BookEditorAction.saved),
          child: Text(_busy ? 'Saving...' : 'Save'),
        ),
      ],
    ),
  );
}
