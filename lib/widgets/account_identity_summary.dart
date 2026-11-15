import 'package:material_ui/material_ui.dart';

import '../services/account_access_service.dart';

class AccountIdentitySummary extends StatelessWidget {
  const AccountIdentitySummary({super.key, required this.account});
  final AccountAccess account;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (account.hasPassword) ...[
        Text(
          'Email & password sign-in',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(account.email),
      ],
      if (account.hasGoogle) ...[
        if (account.hasPassword) const SizedBox(height: 12),
        Text('Google sign-in', style: Theme.of(context).textTheme.labelMedium),
        Text(account.googleEmail ?? account.email),
      ],
      if (!account.hasPassword && !account.hasGoogle) Text(account.email),
    ],
  );
}
