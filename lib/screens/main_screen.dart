import 'dart:async';

import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';

import 'home_screen.dart';
import 'account_screen.dart';
import 'library_screen.dart';
import 'add_book_screen.dart';
import 'browse_screen.dart';
import '../data/book_repository.dart';
import '../widgets/account_button.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  Timer? _retryTimer;
  int _selectedIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _initializePages();
    WidgetsBinding.instance.addObserver(this);
    unawaited(BookRepository.instance.sync());
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final repository = BookRepository.instance;
      if (repository.pendingCount > 0 || repository.lastError != null) {
        unawaited(repository.sync(force: true));
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(BookRepository.instance.sync(force: true));
    }
  }

  void _initializePages() {
    _pages = [
      HomeScreen(onExplore: () => _onItemTapped(1)),
      const BrowseScreen(isActive: false),
      const LibraryScreen(isActive: false),
      AddBookScreen(onBookAdded: _onBookAdded, isActive: false),
    ];
  }

  void _onBookAdded() {
    _onItemTapped(2);
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _selectedIndex = index;
      _pages[1] = BrowseScreen(isActive: index == 1);
      _pages[2] = LibraryScreen(isActive: index == 2);

      _pages[3] = AddBookScreen(
        onBookAdded: _onBookAdded,
        isActive: index == 3,
      );
    });
  }

  Future<void> _resolveConflicts() async {
    final repository = BookRepository.instance;
    for (final entry in repository.conflicts) {
      if (!mounted) return;
      final local = entry.value['data'] as Map;
      final conflict = entry.value['conflict'] as Map;
      final remote = conflict['remote'] as Map;
      final fields = (conflict['fields'] as List).cast<String>();
      final keepLocal = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Resolve ${local['title']}'),
          content: SingleChildScrollView(
            child: Text(
              [
                'These fields changed on both devices:',
                for (final field in fields)
                  '$field\nThis device: ${local[field]}\nCloud: ${remote[field]}',
              ].join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Use cloud'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keep this device'),
            ),
          ],
        ),
      );
      if (keepLocal == null) return;
      await repository.resolveConflict(entry.key, keepLocal: keepLocal);
    }
    await repository.sync(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BookRepository.instance,
      builder: (context, _) => BookRepository.instance.deletionPending
          ? const AccountScreen()
          : Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: _selectedIndex == 0 ? const ReaderHelpButton() : null,
                title: Text(
                  'Reading Tracker',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    letterSpacing: 0,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                actions: const [AccountButton(), SizedBox(width: 8)],
                elevation: 0,
                scrolledUnderElevation: 0,
                shape: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              body: Column(
                children: [
                  AnimatedBuilder(
                    animation: BookRepository.instance,
                    builder: (context, _) {
                      final repository = BookRepository.instance;
                      if (repository.pendingCount == 0 &&
                          repository.lastError == null) {
                        return const SizedBox.shrink();
                      }
                      return SafeArea(
                        bottom: false,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.cloud_off),
                          title: Text(
                            repository.lastError ??
                                '${repository.pendingCount} changes saved locally; waiting for cloud sync.',
                          ),
                          trailing: repository.conflicts.isNotEmpty
                              ? TextButton(
                                  onPressed: _resolveConflicts,
                                  child: const Text('Resolve'),
                                )
                              : IconButton(
                                  tooltip: 'Retry cloud sync',
                                  onPressed: () async {
                                    await repository.sync(force: true);
                                  },
                                  icon: const Icon(Icons.sync),
                                ),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: _pages,
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: _buildBottomNavBar(),
            ),
    );
  }

  Widget _buildBottomNavBar() => Container(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onItemTapped,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.cottage_outlined),
          selectedIcon: Icon(Icons.cottage_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore_rounded),
          label: 'Browse',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_stories_outlined),
          selectedIcon: Icon(Icons.auto_stories_rounded),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle_rounded),
          label: 'Add',
        ),
      ],
    ),
  );
}
