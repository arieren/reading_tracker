import 'package:material_ui/material_ui.dart';

import '../data/book_repository.dart';
import '../models/book.dart';
import '../services/reading_page.dart';
import '../widgets/brand_header.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_editor.dart';
import '../widgets/book_metadata.dart';
import 'reader_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onExplore});
  final VoidCallback? onExplore;

  Future<void> _edit(BuildContext context, Book book) async {
    final action = await showBookEditor(context, book, allowRead: true);
    if (action == BookEditorAction.read && context.mounted) {
      final current = BookRepository.instance.userBooks
          .where((b) => b.id == book.id)
          .firstOrNull;
      if (current != null) await openBookReader(context, current);
    }
  }

  Future<void> _read(BuildContext context, Book book) async {
    if (!isReadingUrl(book.linkURL)) {
      await _edit(context, book);
    } else {
      await openBookReader(context, book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = BookRepository.instance;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final books = repository.userBooks
            ..sort(
              (a, b) => (b.lastRead ?? DateTime(1900)).compareTo(
                a.lastRead ?? DateTime(1900),
              ),
            );
          return RefreshIndicator(
            onRefresh: () async {
              await repository.sync(force: true);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (books.isEmpty) ...[
                  const SizedBox(height: 24),
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 48,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your library starts here',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Browse a reading website or add a title you already love.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (onExplore != null)
                    Center(
                      child: FilledButton.icon(
                        onPressed: onExplore,
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Browse websites'),
                      ),
                    ),
                ] else ...[
                  Text(
                    'Continue reading',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  FadeIn(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _continueCard(context, books.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recently read',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (onExplore != null)
                        TextButton(
                          onPressed: onExplore,
                          child: const Text('Browse'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final book in books.take(10))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _read(context, book),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              BookCover(
                                imageUrl: book.imageUrl,
                                type: book.type,
                                width: 52,
                                height: 76,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      book.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    BookMetadata(
                                      type: book.type,
                                      chapter: book.chapter,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit ${book.title}',
                                onPressed: () => _edit(context, book),
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _continueCard(BuildContext context, Book book) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BookCover(
        imageUrl: book.imageUrl,
        type: book.type,
        width: 82,
        height: 124,
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              book.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Chapter ${book.chapter}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _read(context, book),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Read now'),
            ),
          ],
        ),
      ),
    ],
  );
}
