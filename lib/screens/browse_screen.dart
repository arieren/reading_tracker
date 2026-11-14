import '../widgets/reset_draft_on_return.dart';

import 'package:material_ui/material_ui.dart';

import '../services/reading_page.dart';
import '../services/reading_sites.dart';
import 'reader_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    this.store,
    this.onOpen,
    this.isActive = true,
  });
  final bool isActive;
  final ReadingSiteStore? store;
  final Future<void> Function(String url)? onOpen;
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with ResetDraftOnReturn<BrowseScreen> {
  final _address = TextEditingController();
  late final _store = widget.store ?? ReadingSiteStore();
  List<ReadingSite> _sites = ReadingSiteStore.defaults;
  String? _error;
  bool _opening = false;

  @override
  void resetDraft() {
    setState(() {
      _address.clear();
      _error = null;
    });
  }

  @override
  void didUpdateWidget(covariant BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) resetDraft();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sites = await _store.load();
      if (mounted) setState(() => _sites = sites);
    } on Object {
      if (mounted) setState(() => _error = 'Could not load saved websites.');
    }
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _open(String address) async {
    if (_opening) return;
    final url = address.trim();
    if (!isReadingUrl(url)) {
      setState(() => _error = 'Enter a full http:// or https:// address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _opening = true;
    });
    try {
      if (widget.onOpen != null) {
        await widget.onOpen!(url);
      } else {
        await openReadingSite(context, url);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _addSite() async {
    final site = await showDialog<ReadingSite>(
      context: context,
      builder: (_) => _SiteDialog(store: _store),
    );
    if (site != null) await _load();
  }

  Future<void> _remove(ReadingSite site) async {
    try {
      await _store.remove(site);
      await _load();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not remove this website. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Website or reading link',
              hintText: 'https://',
              prefixIcon: const Icon(Icons.language_outlined),
              suffixIcon: IconButton(
                tooltip: 'Open website',
                onPressed: _opening ? null : () => _open(_address.text),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
            onSubmitted: _opening ? null : _open,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Websites',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _addSite,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add website'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final site in _sites) ...[
            Material(
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  child: Text(site.name.substring(0, 1).toUpperCase()),
                ),
                title: Text(site.name),
                subtitle: Text(
                  Uri.parse(site.url).host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _opening ? null : () => _open(site.url),
                trailing: site.builtIn
                    ? const Icon(Icons.chevron_right_rounded)
                    : PopupMenuButton<String>(
                        tooltip: 'Options for ${site.name}',
                        onSelected: (_) => _remove(site),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove website'),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.bookmark_add_outlined,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  supportsEmbeddedReader
                      ? 'Open a story, then tap Save to library in the reader. Its link and available details are filled in for you.'
                      : 'Websites open in your browser on this device. Use Add to save a title and its reading link.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({required this.store});
  final ReadingSiteStore store;
  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  final _name = TextEditingController(), _url = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.add(_name.text, _url.text);
      if (mounted) {
        Navigator.pop(
          context,
          ReadingSite(name: _name.text.trim(), url: _url.text.trim()),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : 'Could not save this website. Please try again.',
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
      title: const Text('Add website'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Website address',
                hintText: 'https://',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
