import 'package:material_ui/material_ui.dart';

import '../widgets/auth_form.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.notice});
  final String? notice;
  @override
  Widget build(BuildContext context) =>
      AuthForm(mode: AuthFormMode.login, notice: notice);
}
