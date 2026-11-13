import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/book_repository.dart';
import 'services/firebase_environment.dart';
import 'models/book.dart';
import 'screens/main_screen.dart';
import 'screens/login_page.dart';
import 'services/theme_provider.dart';
import 'services/app_update_service.dart';
import 'services/cover_cache.dart';

Future<void> initializeApplication() async {
  await initializeFirebaseEnvironment();
  await initializeCoverCache();
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
  await Hive.openBox<Book>('books');
  await BookRepository.initialize();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApplicationBootstrap());
}

class ApplicationBootstrap extends StatefulWidget {
  const ApplicationBootstrap({
    super.key,
    this.initialize = initializeApplication,
  });
  final Future<void> Function() initialize;
  @override
  State<ApplicationBootstrap> createState() => _ApplicationBootstrapState();
}

class _ApplicationBootstrapState extends State<ApplicationBootstrap> {
  late Future<void> _initialization;
  @override
  void initState() {
    super.initState();
    _initialization = widget.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.done && !state.hasError) {
        return const MyApp();
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: state.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Unable to start Reading Tracker.'),
                      ElevatedButton(
                        onPressed: () => setState(() {
                          _initialization = widget.initialize();
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.home, this.checkUpdate = checkForAppUpdate});
  final Widget? home;
  final Future<bool> Function() checkUpdate;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: Consumer<ThemeProvider>(
      builder: (context, theme, _) => MaterialApp(
        title: 'Reading Tracker',
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark,
        ),
        themeMode: theme.themeMode,
        home: UpdateGate(
          checkUpdate: checkUpdate,
          child: home ?? const InitialScreen(),
        ),
      ),
    ),
  );
}

class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.checkUpdate, required this.child});
  final Future<bool> Function() checkUpdate;
  final Widget child;
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _available = false;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final available = await widget.checkUpdate().timeout(
        const Duration(seconds: 6),
      );
      if (mounted) setState(() => _available = available);
    } on Object catch (_) {
      /* An optional update check must not block local use. */
    }
  }

  Future<void> _openStore() async {
    try {
      final opened = await launchUrl(
        Uri.parse(
          'https://play.google.com/store/apps/details?id=edu.cpp.reading_tracker',
        ),
      );
      if (!opened) throw StateError('Store unavailable');
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open the store. Please try again later.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => !_available
      ? widget.child
      : Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 56),
                  const Text('New Update Available!'),
                  Wrap(
                    spacing: 16,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _available = false),
                        child: const Text('Update Later'),
                      ),
                      ElevatedButton(
                        onPressed: _openStore,
                        child: const Text('Update Now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
}

class InitialScreen extends StatelessWidget {
  const InitialScreen({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.userChanges(),
    initialData: FirebaseAuth.instance.currentUser,
    builder: (context, snapshot) {
      final user = snapshot.data;
      final allowed =
          user != null &&
          (user.emailVerified ||
              user.providerData.any((p) => p.providerId == 'google.com'));
      return allowed ? MainScreen(key: ValueKey(user.uid)) : LoginPage();
    },
  );
}
