import 'package:material_ui/material_ui.dart';

import '../widgets/auth_form.dart';

class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const AuthForm(mode: AuthFormMode.signup);
}
