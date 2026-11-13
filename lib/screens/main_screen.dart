import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'home_screen.dart';
import 'account_screen.dart';
import 'library_screen.dart';
import 'add_book_screen.dart';
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
      HomeScreen(),
      LibraryScreen(),
      AddBookScreen(onBookAdded: _onBookAdded, isActive: false),
    ];
  }

  void _onBookAdded() {
    _onItemTapped(1);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _pages[2] = AddBookScreen(
        onBookAdded: _onBookAdded,
        isActive: index == 2,
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

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book_outlined),
            activeIcon: Icon(Icons.book),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'Add',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).unselectedWidgetColor,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
