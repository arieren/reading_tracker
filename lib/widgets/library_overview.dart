import 'package:material_ui/material_ui.dart';

import '../data/book_repository.dart';

class LibraryHeaderButton extends StatelessWidget {
  const LibraryHeaderButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Open library overview',
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(0, 44),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Reading Tracker',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    ),
  );
}

class LibraryOverview extends StatefulWidget {
  const LibraryOverview({
    super.key,
    required this.repository,
    required this.onNavigate,
  });
  final BookRepository repository;
  final ValueChanged<int> onNavigate;
  @override
  State<LibraryOverview> createState() => _LibraryOverviewState();
}

class _LibraryOverviewState extends State<LibraryOverview> {
  bool _syncing = false;
  String? _status;
  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _status = null;
    });
    try {
      final complete = await widget.repository.sync(force: true);
      if (mounted) {
        setState(
          () => _status = complete
              ? 'Cloud sync complete.'
              : 'Changes remain saved on this device. Cloud sync will retry.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _status =
              'Unable to sync now. Your local library is still available.',
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final repository = widget.repository;
      final books = repository.userBooks;
      final types = <String, int>{};
      for (final book in books) {
        types.update(book.type, (count) => count + 1, ifAbsent: () => 1);
      }
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your shelf',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${books.length} ${books.length == 1 ? 'story' : 'stories'} in your library',
              ),
              if (types.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in types.entries)
                      Chip(label: Text('${type.key} · ${type.value}')),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  repository.pendingCount > 0 || repository.lastError != null
                      ? Icons.cloud_off_outlined
                      : Icons.cloud_done_outlined,
                ),
                title: Text(
                  _status ??
                      (repository.pendingCount > 0
                          ? '${repository.pendingCount} changes waiting to sync'
                          : repository.lastError ??
                                'No pending changes on this device'),
                ),
                subtitle: const Text('Books are saved locally first.'),
              ),
              OutlinedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(_syncing ? 'Syncing…' : 'Sync now'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => widget.onNavigate(2),
                icon: const Icon(Icons.auto_stories_outlined),
                label: const Text('Open library'),
              ),
              TextButton(
                onPressed: () => widget.onNavigate(0),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
