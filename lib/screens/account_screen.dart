import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../data/book_repository.dart';
import '../services/auth_service.dart';
import '../services/import_service.dart';
import '../widgets/book_import_dialog.dart';
import '../services/theme_provider.dart';
import '../services/reading_position.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _auth = AuthService();
  bool _busy = false;
  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _auth.signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on Object catch (_) {
      _message('Unable to sign out. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final entries = await showDialog<List<ImportEntry>>(
      context: context,
      builder: (_) => const BookImportDialog(),
    );
    if (!mounted || entries == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _message('Please sign in again.');
      return;
    }
    setState(() => _busy = true);
    try {
      final added = await BookImportService(BookRepository.instance)
          .import(entries, uid);
      unawaited(BookRepository.instance.sync(force: true));
      _message(
        '$added books saved on this device. Existing titles were skipped.',
      );
    } on Object catch (_) {
      _message(
        'Import stopped. Books already saved are retained; retry skips existing titles.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (_busy || user == null) return;
    final google = user.providerData.any((p) => p.providerId == 'google.com');
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteConfirmation(needsPassword: !google),
    );
    if (!mounted || password == null) return;
    setState(() => _busy = true);
    try {
      await BookRepository.instance.deleteAccount(
        reauthenticate: () => _auth.reauthenticate(password: password),
        requestDeletion: _auth.requestAccountDeletion,
      );
      try {
        await ReadingPositionStore().removeUser(user.uid);
      } on Object {
        debugPrint('Local reader settings cleanup unavailable.');
      }
      await _auth.signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on Object catch (error) {
      _message(
        '${authenticationError(error)} Deletion is paused. Reconnect and resume it from Account Settings.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _listBooks() {
    final books = BookRepository.instance.userBooks
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your Books'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              books.isEmpty
                  ? 'No books yet.'
                  : books
                        .map((b) => '${b.title} (Chapter ${b.chapter})')
                        .join('\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final deletionPending = BookRepository.instance.deletionPending;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Account Settings')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_busy) const LinearProgressIndicator(),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.account_circle_outlined, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    'Your account',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    FirebaseAuth.instance.currentUser?.email ?? 'Signed out',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${BookRepository.instance.userBooks.length} stories on your shelf',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (deletionPending) ...[
              const Text(
                'Account deletion is unfinished. Keep the app open and online while resuming. Your library stays on this device until deletion finishes.',
              ),
              ElevatedButton(
                onPressed: _busy ? null : _deleteAccount,
                child: const Text('Resume account deletion'),
              ),
            ],
            if (!deletionPending) ...[
              SwitchListTile(
                title: const Text('Dark Mode'),
                value: theme.themeMode == ThemeMode.dark,
                onChanged: _busy ? null : (_) => theme.toggleTheme(),
              ),
              ListTile(
                leading: const Icon(Icons.library_books),
                title: const Text('List My Books'),
                enabled: !_busy,
                onTap: _listBooks,
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Import Books'),
                enabled: !_busy,
                onTap: _import,
              ),
            ],
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              enabled: !_busy,
              onTap: _signOut,
            ),
            if (!deletionPending) ...[
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Delete Account'),
                enabled: !_busy,
                onTap: _deleteAccount,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeleteConfirmation extends StatefulWidget {
  const _DeleteConfirmation({required this.needsPassword});
  final bool needsPassword;
  @override
  State<_DeleteConfirmation> createState() => _DeleteConfirmationState();
}

class _DeleteConfirmationState extends State<_DeleteConfirmation> {
  final _password = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete Account'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Delete your account and all books permanently? You must verify your identity and be online.',
        ),
        if (widget.needsPassword)
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _password.text),
        child: const Text('Verify and delete'),
      ),
    ],
  );
}
