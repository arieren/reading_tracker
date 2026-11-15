import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/book_repository.dart';
import 'services/firebase_environment.dart';
import 'models/book.dart';
import 'screens/main_screen.dart';
import 'screens/app_update_screen.dart';
import 'screens/login_page.dart';
import 'services/theme_provider.dart';
import 'services/app_update_service.dart';
import 'services/cover_cache.dart';
import 'theme/app_theme.dart';
import 'widgets/reset_draft_on_return.dart';
import 'widgets/session_gate.dart';

import 'package:flutter/services.dart';

import 'theme/system_ui.dart';

Future<void> initializeApplication() async {
  await initializeFirebaseEnvironment();
  await initializeCoverCache();
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BookAdapter());
  await Hive.openBox<Book>('books');
  await BookRepository.initialize();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
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
        navigatorObservers: [draftRouteObserver],
        title: 'Reading Tracker',
        theme: readingTheme(Brightness.light),
        darkTheme: readingTheme(Brightness.dark),
        themeMode: theme.themeMode,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: readingSystemUiStyle(Theme.of(context).brightness),
          child: UpdateGate(
            checkUpdate: checkUpdate,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: home ?? const InitialScreen(),
      ),
    ),
  );
}

class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.checkUpdate,
    required this.child,
    this.openStore = openPlayStore,
  });
  final Future<bool> Function() checkUpdate;
  final Widget child;
  final Future<bool> Function() openStore;
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _available = false;
  bool _openingStore = false;
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
      if (mounted) {
        if (available) FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _available = available);
      }
    } on Object catch (_) {
      // Without a valid version requirement, preserve access to local books.
    }
  }

  Future<void> _openStore() async {
    if (_openingStore) return;
    setState(() => _openingStore = true);
    try {
      final opened = await widget.openStore();
      if (!opened) throw StateError('Store unavailable');
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open the store. Please try again later.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: _available,
        child: ExcludeFocus(
          excluding: _available,
          child: TickerMode(enabled: !_available, child: widget.child),
        ),
      ),
      if (_available)
        AppUpdateScreen(onUpdate: _openStore, openingStore: _openingStore),
    ],
  );
}

Future<bool> openPlayStore() => launchUrl(
  Uri.parse(
    'https://play.google.com/store/apps/details?id=edu.cpp.reading_tracker',
  ),
  mode: LaunchMode.externalApplication,
);

class InitialScreen extends StatelessWidget {
  const InitialScreen({super.key});
  @override
  Widget build(BuildContext context) => SessionGate(
    changes: FirebaseAuth.instance.userChanges(),
    initialUser: FirebaseAuth.instance.currentUser,
    signedIn: (user) => MainScreen(key: ValueKey(user.uid)),
    signedOut: (notice) => LoginPage(notice: notice),
  );
}
