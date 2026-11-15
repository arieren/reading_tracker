import 'package:material_ui/material_ui.dart';

import '../screens/account_screen.dart';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Account',
    icon: CircleAvatar(
      radius: 17,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        Icons.person_outline_rounded,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        size: 22,
      ),
    ),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
    ),
  );
}

class ReaderHelpButton extends StatelessWidget {
  const ReaderHelpButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Reading help',
    icon: const Icon(Icons.info_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recently Read'),
        content: const Text(
          'Tap an entry to open its saved link. Use the bookmark button to save your place, or the chapter control to correct your progress. Website fullscreen keeps the app controls available. Your place is saved locally before cloud sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
