import 'package:material_ui/material_ui.dart';

import '../services/catalog_service.dart';
import '../services/import_service.dart';

class BookImportScreen extends StatefulWidget {
  const BookImportScreen({super.key, this.catalog});
  final CatalogService? catalog;
  @override
  State<BookImportScreen> createState() => _BookImportScreenState();
}

class _BookImportScreenState extends State<BookImportScreen> {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import books'),
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _preview == null
                              ? 'Paste your reading list'
                              : 'Review your books',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _preview == null
                              ? 'One title per line. Add a chapter number at the end if you know it.'
                              : '${_preview!.length} books ready to import. Tap a title’s search button to change its match.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        if (_preview == null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Tokyo Ghoul 7\nSolo Leveling 35\nShadow Slave 120',
                              style: TextStyle(height: 1.7),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _text,
                            enabled: !_matching,
                            minLines: 8,
                            maxLines: 14,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: 'Book list',
                              alignLabelWithHint: true,
                              hintText: 'Paste titles here…',
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Titles and covers are matched automatically. Review is optional; unmatched titles keep your entered details. Existing books are skipped.',
                          ),
                        ] else ...[
                          for (final entry in _preview!)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.title),
                              subtitle: Text(
                                '${entry.type} · Chapter ${entry.chapter}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Choose catalog match',
                                icon: const Icon(Icons.search),
                                onPressed: _matching
                                    ? null
                                    : () => _chooseMatch(entry),
                              ),
                            ),
                        ],
                        if (_loadingResults)
                          const Padding(
                            padding: EdgeInsets.only(top: 20),
                            child: LinearProgressIndicator(),
                          ),
                        if (_progress != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_progress!),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _matching
                              ? null
                              : _preview == null
                              ? () => _prepare(importImmediately: false)
                              : () => setState(() => _preview = null),
                          child: Text(
                            _preview == null ? 'Review matches' : 'Edit list',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _matching
                              ? null
                              : () {
                                  if (_preview != null) {
                                    Navigator.pop(context, _preview);
                                  } else {
                                    _prepare(importImmediately: true);
                                  }
                                },
                          child: Text(_matching ? 'Matching…' : 'Import'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
