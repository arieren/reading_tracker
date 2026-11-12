import 'package:material_ui/material_ui.dart';

import '../services/catalog_service.dart';
import '../services/import_service.dart';

class BookImportDialog extends StatefulWidget {
  const BookImportDialog({super.key, this.catalog});
  final CatalogService? catalog;
  @override
  State<BookImportDialog> createState() => _BookImportDialogState();
}

class _BookImportDialogState extends State<BookImportDialog> {
  final _text = TextEditingController();
  late final _catalog = widget.catalog ?? CatalogService.instance;
  List<ImportEntry>? _preview;
  String? _error;
  bool _matching = false;
  bool _loadingResults = false;
  String? _progress;

  Future<void> _prepare({required bool importImmediately}) async {
    if (_matching) return;
    late List<ImportEntry> entries;
    try {
      entries = parseBookImport(_text.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString());
      return;
    }
    setState(() {
      _matching = true;
      _loadingResults = true;
      _error = null;
    });
    var unmatched = 0;
    String? warning;
    try {
      for (var index = 0; index < entries.length; index++) {
        if (!mounted) return;
        setState(
          () => _progress = 'Finding matches ${index + 1} of ${entries.length}',
        );
        try {
          final matches = await _catalog.search(entries[index].title);
          if (!mounted) return;
          if (matches.isNotEmpty) {
            entries[index] = entries[index].withCatalogMatch(matches.first);
          } else {
            unmatched++;
          }
        } on Object catch (_) {
          // Keep unmatched entries usable offline, without retrying a failed
          // service for every remaining row in a large import.
          warning = 'Catalog lookup stopped. Remaining titles use your entered details.';
          break;
        }
      }
      if (!mounted) return;
      if (importImmediately) {
        Navigator.pop(context, entries);
      } else {
        setState(() {
          _preview = entries;
          _error =
              warning ??
              (unmatched > 0
                  ? '$unmatched titles had no match and use your entered details.'
                  : null);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _matching = false;
          _loadingResults = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _chooseMatch(ImportEntry entry) async {
    if (_matching) return;
    setState(() {
      _matching = true;
      _loadingResults = true;
      _error = null;
    });
    try {
      final results = await _catalog.search(entry.title);
      if (!mounted) return;
      setState(() => _loadingResults = false);
      if (results.isEmpty) {
        setState(
          () => _error =
              'No catalog matches found. You can keep the entered title.',
        );
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose a catalog match'),
          children: results
              .map(
                (r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r),
                  child: Text('${r['title']} (${r['type']})'),
                ),
              )
              .toList(),
        ),
      );
      if (!mounted || selected == null || _preview == null) return;
      final index = _preview!.indexOf(entry);
      if (index < 0) return;
      setState(() => _preview![index] = entry.withCatalogMatch(selected));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CatalogException
              ? '${error.message} You can still import the entered titles.'
              : 'Cannot connect to search. You can still import the entered titles.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _matching = false;
          _loadingResults = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import Books'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'One title and chapter per line, for example: Tokyo Ghoul 7. The top catalog result is selected automatically for its title, type and cover. Review to change matches, or import directly. Titles without a match keep your entered details. Duplicate titles are skipped.',
            ),
            if (_preview == null)
              TextField(
                controller: _text,
                enabled: !_matching,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Book list'),
              )
            else
              ..._preview!.map(
                (e) => ListTile(
                  title: Text(e.title),
                  subtitle: Text('Chapter ${e.chapter}'),
                  trailing: IconButton(
                    tooltip: 'Choose catalog match',
                    icon: const Icon(Icons.search),
                    onPressed: _matching ? null : () => _chooseMatch(e),
                  ),
                ),
              ),
            if (_loadingResults) const LinearProgressIndicator(),
            if (_progress != null) Text(_progress!),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_preview != null)
        TextButton(
          onPressed: _matching ? null : () => setState(() => _preview = null),
          child: const Text('Edit'),
        ),
      if (_preview == null)
        TextButton(
          onPressed: _matching
              ? null
              : () => _prepare(importImmediately: false),
          child: const Text('Review'),
        ),
      ElevatedButton(
        onPressed: _matching
            ? null
            : () {
                if (_preview != null) {
                  Navigator.pop(context, _preview);
                  return;
                }
                _prepare(importImmediately: true);
              },
        child: const Text('Import'),
      ),
    ],
  );
}
