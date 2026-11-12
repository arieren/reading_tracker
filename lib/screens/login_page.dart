import 'package:material_ui/material_ui.dart';

import '../widgets/auth_form.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AuthForm(mode: AuthFormMode.login);
}
