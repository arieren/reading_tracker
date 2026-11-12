import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/book.dart';
import '../models/book_codec.dart';
import '../data/book_repository.dart';

Future<void> openBookReader(BuildContext context, Book book) async {
  final url = book.linkURL;
  if (url == null || url.isEmpty || !validWebUrl(url)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a valid reading link first.')),
    );
    return;
  }
  try {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform)) {
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Unable to open link');
      }
      await BookRepository.instance.markRead(book);
      unawaited(BookRepository.instance.sync(force: true));
      return;
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(book: book)),
    );
  } on Object catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this reading link.')),
      );
    }
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});
  final Book book;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final WebViewController _controller;
  late String _url = widget.book.linkURL!;
  bool _loading = true, _saving = false, _markedRead = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => validWebUrl(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              if (validWebUrl(url)) _url = url;
            });
            if (!_markedRead && _error == null) {
              _markedRead = true;
              _markRead();
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame != false) {
              setState(() {
                _error = 'Unable to load this page.';
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_url));
  }

  Future<void> _markRead() async {
    try {
      await BookRepository.instance.markRead(widget.book);
      unawaited(BookRepository.instance.sync(force: true));
    } on Object catch (_) {
      if (mounted) _message('Unable to save reading time.');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final book = BookRepository.instance.userBooks.firstWhere(
        (b) => b.id == widget.book.id,
      );
      await BookRepository.instance.markRead(book, url: _url);
      unawaited(BookRepository.instance.sync(force: true));
      if (mounted) {
        _message(
          'Reading link saved on this device. Cloud sync will retry if needed.',
        );
      }
    } on Object catch (_) {
      if (mounted) _message('Unable to save this reading link.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) {
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Currently Reading'),
        leading: BackButton(onPressed: _back),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            tooltip: 'Save current reading link',
          ),
          IconButton(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
          IconButton(
            onPressed: () async {
              try {
                await launchUrl(
                  Uri.parse(_url),
                  mode: LaunchMode.externalApplication,
                );
              } on Object catch (_) {
                if (mounted) _message('Unable to open browser.');
              }
            },
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open browser',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: () => _controller.reload(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
