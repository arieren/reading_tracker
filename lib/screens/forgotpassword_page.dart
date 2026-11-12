import 'package:material_ui/material_ui.dart';

import '../widgets/auth_form.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AuthForm(mode: AuthFormMode.reset);
}
