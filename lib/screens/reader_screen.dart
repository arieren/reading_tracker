import '../widgets/reading_dialogs.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/book.dart';
import '../data/book_repository.dart';
import '../services/reading_page.dart';
import '../services/reading_metadata.dart';
import '../services/reading_position.dart';

bool get supportsEmbeddedReader =>
    !kIsWeb &&
    [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform);
Future<void> openBookReader(BuildContext context, Book book) async {
  final url = book.linkURL;
  if (url == null || !isReadingUrl(url) || url.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a valid reading link first.')),
    );
    return;
  }
  await _openReader(context, url, book: book);
}

Future<void> openReadingSite(BuildContext context, String url) =>
    _openReader(context, url);
Future<void> _openReader(BuildContext context, String url, {Book? book}) async {
  if (!isReadingUrl(url)) return;
  try {
    if (!supportsEmbeddedReader) {
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Unable to open link');
      }
      if (book != null) {
        await BookRepository.instance.markRead(book);
        unawaited(BookRepository.instance.sync(force: true));
      }
      return;
    }
    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(book: book, initialUrl: url),
        ),
      );
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this reading link.')),
      );
    }
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, this.book, this.initialUrl});
  final Book? book;
  final String? initialUrl;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  late String _url = widget.initialUrl ?? widget.book!.linkURL!;
  late String? _bookId = widget.book?.id;
  bool _loading = true,
      _saving = false,
      _focus = false,
      _allowPop = false,
      _closing = false;
  int _progress = 0;
  bool _adding = false;
  String? _error, _savedUrl;
  Timer? _saveTimer;
  Timer? _positionTimer;
  final _positions = ReadingPositionStore();
  Future<void> _saveTail = Future.value();
  Book? get _book => BookRepository.instance.userBooks
      .where((b) => b.id == _bookId)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => isReadingUrl(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onUrlChange: (change) {
            if (change.url != null && isReadingUrl(change.url)) {
              _url = change.url!;
              _scheduleSave();
            }
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
                _url = url;
              });
            }
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              if (isReadingUrl(url)) _url = url;
            });
            _scheduleSave();
            unawaited(_restorePosition());
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _error =
                    'This page could not load. Your saved library is safe.';
                _loading = false;
              });
            }
          },
        ),
      )
      ..setOnScrollPositionChange((change) {
        _positionTimer?.cancel();
        _positionTimer = Timer(const Duration(milliseconds: 700), () {
          unawaited(_savePosition());
        });
      })
      ..loadRequest(Uri.parse(_url));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveTimer?.cancel();
      unawaited(_captureAndSave());
      unawaited(_savePosition());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _positionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 750), () {
      unawaited(_captureAndSave());
    });
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<ReadingPageMetadata?> _metadata() async {
    final url = _url;
    try {
      final value = await _controller
          .runJavaScriptReturningResult(readingMetadataScript)
          .timeout(const Duration(seconds: 3));
      dynamic data = value;
      for (var i = 0; i < 2 && data is String; i++) {
        data = jsonDecode(data);
      }
      if (data is! Map || !mounted || url != _url) return null;
      return ReadingPageMetadata.fromMap(data);
    } on Object {
      // Missing website metadata must not prevent a manual bookmark.
      return null;
    }
  }

  Future<void> _captureAndSave({bool explicit = false}) async {
    if (_loading || _error != null || !isReadingUrl(_url)) return;
    final candidate = _url;
    final metadata = await _metadata();
    if (!mounted || candidate != _url) return;
    final book = _book;
    if (book == null) {
      if (mounted) setState(() {});
      return;
    }
    final matched = pageMatchesBook(
      savedUrl: book.linkURL ?? '',
      currentUrl: candidate,
      bookTitle: book.title,
      pageTitle: metadata?.matchingPageTitle ?? '',
    );
    if (!explicit && !matched) return;
    final chapter =
        matched &&
            normalizedStoryTitle(metadata?.title ?? '') ==
                normalizedStoryTitle(book.title)
        ? metadata?.chapter
        : null;
    if (_savedUrl == candidate &&
        (chapter == null || chapter == book.chapter)) {
      return;
    }
    setState(() => _saving = true);
    final operation = _saveTail.then((_) async {
      final current = _book;
      if (current == null) throw StateError('Book unavailable');
      await BookRepository.instance.save(
        Book(
          id: current.id,
          uid: current.uid,
          title: current.title,
          type: current.type,
          chapter: chapter ?? current.chapter,
          imageUrl: current.imageUrl,
          linkURL: candidate,
          lastRead: DateTime.now(),
        ),
        original: current,
      );
      _savedUrl = candidate;
      unawaited(BookRepository.instance.sync(force: true));
    });
    _saveTail = operation.catchError((Object error) {});
    try {
      await operation;
      if (explicit) _message('Your place is saved on this device.');
    } on Object {
      _message('Could not save your place. Please try Save place.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exit() async {
    if (_closing) return;
    _closing = true;
    _saveTimer?.cancel();
    await _captureAndSave();
    await _saveTail;
    await _savePosition();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await _exit();
    }
  }

  Future<void> _savePosition() async {
    final book = _book;
    final url = _url;
    if (book?.uid == null ||
        book?.id == null ||
        _loading ||
        book!.linkURL != url) {
      return;
    }
    try {
      final value = await _controller
          .runJavaScriptReturningResult('window.scrollY')
          .timeout(const Duration(seconds: 2));
      final offset = value is num
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (offset == null || !mounted || _url != url) return;
      await _positions.save(
        uid: book.uid!,
        bookId: book.id!,
        url: url,
        offset: offset,
      );
    } on Object {
      /* Reading remains available if local preferences fail. */
    }
  }

  Future<void> _restorePosition() async {
    final book = _book;
    final url = _url;
    if (book?.uid == null || book?.id == null) return;
    try {
      final offset = await _positions.read(
        uid: book!.uid!,
        bookId: book.id!,
        url: url,
      );
      if (offset != null && mounted && _url == url) {
        await _controller.runJavaScript('window.scrollTo(0, $offset)');
      }
    } on Object {
      /* Sites with dynamic layouts may handle their own restoration. */
    }
  }

  Future<void> _editProgress() async {
    final book = _book;
    if (book == null) return;
    final chapter = await showChapterProgressDialog(context, book.chapter);
    if (chapter == null || !mounted) return;
    final current = _book;
    if (current == null) return;
    try {
      await BookRepository.instance.save(
        Book(
          id: current.id,
          uid: current.uid,
          title: current.title,
          type: current.type,
          chapter: chapter,
          imageUrl: current.imageUrl,
          linkURL: current.linkURL,
          lastRead: DateTime.now(),
        ),
        original: current,
      );
      unawaited(BookRepository.instance.sync(force: true));
      if (mounted) setState(() {});
    } on Object {
      _message('Could not update the chapter.');
    }
  }

  Future<void> _addToLibrary() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await _prepareBookmark();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _prepareBookmark() async {
    final bookmarkUrl = _url;
    final detected = await _metadata();
    if (!mounted || bookmarkUrl != _url) return;
    final metadata = await ReadingMetadataService().complete(
      bookmarkUrl,
      detected ?? const ReadingPageMetadata(title: ''),
    );
    if (!mounted || bookmarkUrl != _url) return;
    final result = await showReadingBookmarkDialog(
      context,
      title: metadata.title,
      chapter: metadata.chapter,
      type: metadata.type,
    );
    if (result == null || !mounted) return;
    if (bookmarkUrl != _url) {
      _message('The page changed. Open the story page and save it again.');
      return;
    }
    try {
      final repository = BookRepository.instance;
      final existing = repository.userBooks
          .where(
            (b) =>
                normalizedStoryTitle(b.title) ==
                normalizedStoryTitle(result.title),
          )
          .firstOrNull;
      if (existing != null) {
        await repository.save(
          Book(
            id: existing.id,
            uid: existing.uid,
            title: existing.title,
            type: result.type,
            chapter: result.chapter,
            linkURL: bookmarkUrl,
            imageUrl: existing.imageUrl,
            lastRead: DateTime.now(),
          ),
          original: existing,
        );
        _bookId = existing.id;
        _savedUrl = bookmarkUrl;
        unawaited(repository.sync(force: true));
        if (mounted) setState(() {});
        _message('Updated this story in your library.');
        return;
      }
      final book = Book(
        uid: repository.currentUid(),
        title: result.title,
        type: result.type,
        chapter: result.chapter,
        linkURL: bookmarkUrl,
        imageUrl: metadata.image ?? '',
        lastRead: DateTime.now(),
      );
      await repository.save(book);
      _bookId = book.id;
      _savedUrl = bookmarkUrl;
      unawaited(repository.sync(force: true));
      if (mounted) setState(() {});
      _message('Added to your library. Your place is saved.');
    } on Object {
      _message('Could not add this story. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _back();
      },
      child: Scaffold(
        appBar: _focus
            ? null
            : AppBar(
                leading: IconButton(
                  tooltip: 'Close reader',
                  onPressed: _exit,
                  icon: const Icon(Icons.close_rounded),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book?.title ?? 'Find your next story',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      Uri.tryParse(_url)?.host ?? '',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Hide reader controls',
                    onPressed: () => setState(() => _focus = true),
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'reload') {
                        await _controller.reload();
                      } else if (value == 'save') {
                        await _captureAndSave(explicit: true);
                      } else {
                        try {
                          if (!await launchUrl(
                            Uri.parse(_url),
                            mode: LaunchMode.externalApplication,
                          )) {
                            _message('Unable to open browser.');
                          }
                        } on Object {
                          _message('Unable to open browser.');
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      if (book != null)
                        const PopupMenuItem(
                          value: 'save',
                          child: Text('Save this page'),
                        ),
                      const PopupMenuItem(
                        value: 'reload',
                        child: Text('Reload page'),
                      ),
                      const PopupMenuItem(
                        value: 'browser',
                        child: Text('Open in browser'),
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          top: _focus,
          bottom: _focus,
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_loading)
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress / 100 : null,
                  minHeight: 3,
                ),
              if (_error != null)
                Center(
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 36),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: () => _controller.reload(),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_focus)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'reader-controls',
                    tooltip: 'Show reader controls',
                    onPressed: () => setState(() => _focus = false),
                    child: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _focus
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      if (book == null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _loading || _adding
                                ? null
                                : _addToLibrary,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(
                              _adding ? 'Reading page…' : 'Save to library',
                            ),
                          ),
                        )
                      else ...[
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _editProgress,
                            icon: const Icon(Icons.menu_book_rounded),
                            label: Text('Ch. ${book.chapter}'),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: _saving
                              ? null
                              : () => _captureAndSave(explicit: true),
                          icon: Icon(
                            _saving ? Icons.more_horiz : Icons.bookmark_rounded,
                          ),
                          tooltip: _saving
                              ? 'Saving your place'
                              : _savedUrl == _url
                              ? 'Place saved on this device'
                              : 'Save current place',
                        ),
                      ],
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: () async {
                          if (await _controller.canGoForward()) {
                            await _controller.goForward();
                          }
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
