import 'package:material_ui/material_ui.dart';

import '../screens/account_screen.dart';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Account',
    icon: const Icon(Icons.account_circle),
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
          'Continue opens the saved reading link. Use the save button in the reader to keep the current URL. Chapter progress can be changed in Edit Book. Changes are saved locally before cloud sync.',
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
