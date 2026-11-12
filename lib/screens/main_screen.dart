import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'home_screen.dart';
import 'library_screen.dart';
import 'add_book_screen.dart';
import '../data/book_repository.dart';

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
      AddBookScreen(onBookAdded: _onBookAdded),
    ];
  }

  void _onBookAdded() {
    setState(() {
      _selectedIndex = 1;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  trailing: IconButton(
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
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
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
