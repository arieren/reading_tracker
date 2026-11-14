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
          'Tap a saved story to read. Browse lets you browse reading sites and save a story without copying its link. Matching reading pages save automatically; the bookmark button can save any page you choose. Clear chapter labels can update your chapter automatically. Tap the chapter control to correct it. Fullscreen hides the controls. Your place is saved locally before cloud sync.',
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
