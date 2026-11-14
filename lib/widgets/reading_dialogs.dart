import 'package:material_ui/material_ui.dart';

import '../models/book_codec.dart' show bookTypes;

typedef ReadingBookmarkInput = ({String title, int chapter, String type});
Future<int?> showChapterProgressDialog(BuildContext context, int chapter) =>
    showDialog<int>(
      context: context,
      builder: (_) => _ChapterDialog(initial: chapter),
    );
Future<ReadingBookmarkInput?> showReadingBookmarkDialog(
  BuildContext context, {
  required String title,
  required int? chapter,
  String? type,
}) => showDialog<ReadingBookmarkInput>(
  context: context,
  builder: (_) =>
      _SaveReadingDialog(title: title, chapter: chapter, type: type),
);

class _SaveReadingDialog extends StatefulWidget {
  const _SaveReadingDialog({
    required this.title,
    required this.chapter,
    this.type,
  });
  final String title;
  final int? chapter;
  final String? type;
  @override
  State<_SaveReadingDialog> createState() => _SaveReadingDialogState();
}

class _SaveReadingDialogState extends State<_SaveReadingDialog> {
  late final _title = TextEditingController(text: widget.title),
      _chapter = TextEditingController(text: '${widget.chapter ?? 0}');
  late String _type = widget.type ?? 'Manga';
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _chapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save to library'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The current page becomes your reading link. No copying needed.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _chapter,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Chapter',
              helperText: widget.chapter == null
                  ? 'Not detected. Set your current chapter.'
                  : null,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: bookTypes
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: (value) => setState(() => _type = value!),
            decoration: InputDecoration(
              labelText: 'Type',
              helperText: widget.type == null
                  ? 'Not detected. Please check the type.'
                  : null,
              helperMaxLines: 2,
            ),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final chapter = int.tryParse(_chapter.text);
          if (_title.text.trim().isEmpty ||
              chapter == null ||
              chapter < 0 ||
              chapter > 2147483647) {
            setState(
              () => _error = 'Enter a title and a whole chapter number.',
            );
            return;
          }
          Navigator.pop(context, (
            title: _title.text.trim(),
            chapter: chapter,
            type: _type,
          ));
        },
        child: const Text('Add to library'),
      ),
    ],
  );
}

class _ChapterDialog extends StatefulWidget {
  const _ChapterDialog({required this.initial});
  final int initial;
  @override
  State<_ChapterDialog> createState() => _ChapterDialogState();
}

class _ChapterDialogState extends State<_ChapterDialog> {
  late final _input = TextEditingController(text: '${widget.initial}');
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your chapter'),
    content: TextField(
      controller: _input,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: 'Chapter', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(_input.text);
          if (value == null || value < 0 || value > 2147483647) {
            setState(() => _error = 'Enter a whole chapter number.');
            return;
          }
          Navigator.pop(context, value);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
