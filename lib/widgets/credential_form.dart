import 'package:material_ui/material_ui.dart';

import 'reset_draft_on_return.dart';

enum CredentialAction { addPassword, changePassword, changeEmail, google }

class CredentialInput {
  const CredentialInput({
    this.email = '',
    this.password = '',
    this.newPassword = '',
  });
  final String email;
  final String password;
  final String newPassword;
}

/// Ephemeral inputs only: passwords are never saved in preferences or Hive.
class CredentialForm extends StatefulWidget {
  const CredentialForm({
    super.key,
    required this.action,
    required this.email,
    this.googleEmail,
  });
  final CredentialAction action;
  final String email;

  final String? googleEmail;

  @override
  State<CredentialForm> createState() => _CredentialFormState();
}

class _CredentialFormState extends State<CredentialForm>
    with ResetDraftOnReturn<CredentialForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _visible = false;

  @override
  void resetDraft() {
    _form.currentState?.reset();
    for (final controller in [_email, _current, _new, _confirm]) {
      controller.clear();
    }
    setState(() => _visible = false);
  }

  @override
  void dispose() {
    for (final controller in [_email, _current, _new, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final newPassword =
        action == CredentialAction.addPassword ||
        action == CredentialAction.changePassword;
    final title = switch (action) {
      CredentialAction.addPassword => 'Set up a password',
      CredentialAction.changePassword => 'Change password',
      CredentialAction.changeEmail => 'Change email',
      CredentialAction.google => 'Verify your recovery login',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.email,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(switch (action) {
                  CredentialAction.addPassword => 'Keep a password login as a backup for Google. Save this password before continuing. You will verify your current Google account next.',
                  CredentialAction.changeEmail => 'We will send a verification link to your new inbox. Your sign-in email changes only after you open that link. Your library stays on the same account.',
                  CredentialAction.changePassword => 'Verify your current password, then choose a new one. This changes your Reading Tracker password, not your Google password.',
                  CredentialAction.google =>
                    widget.googleEmail == null
                        ? 'Enter your Reading Tracker password, then choose the Google account to connect. This library stays on the same account.'
                        : 'Enter your Reading Tracker recovery password. Next, select ${widget.googleEmail} to verify your current Google login, then choose its replacement. Your recovery password stays available if switching is interrupted.',
                }),
                const SizedBox(height: 24),
                if (action == CredentialAction.changeEmail &&
                    widget.googleEmail != null) ...[
                  Text(
                    'Google sign-in will still use ${widget.googleEmail}. To use a different Google account, go back and choose Change Google account instead.',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 24),
                ],
                if (action == CredentialAction.changeEmail) ...[
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'New email'),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email address.';
                      }
                      if (email.toLowerCase() == widget.email.toLowerCase()) {
                        return 'Enter a different email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                if (action != CredentialAction.addPassword) ...[
                  _password(
                    _current,
                    'Current password',
                    (value) => value == null || value.isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                ],
                if (newPassword) ...[
                  _password(
                    _new,
                    'New password',
                    (value) => value == null || value.length < 6
                        ? 'Use at least six characters.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  _password(
                    _confirm,
                    'Confirm new password',
                    (value) =>
                        value != _new.text ? 'Passwords do not match.' : null,
                  ),
                  const SizedBox(height: 8),
                ],
                CheckboxListTile(
                  value: _visible,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) =>
                      setState(() => _visible = value ?? false),
                  title: const Text('Show password'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    if (!_form.currentState!.validate()) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(
                      context,
                      CredentialInput(
                        email: _email.text.trim(),
                        password: _current.text,
                        newPassword: _new.text,
                      ),
                    );
                  },
                  child: Text(
                    action == CredentialAction.changeEmail
                        ? 'Send verification link'
                        : 'Continue',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _password(
    TextEditingController controller,
    String label,
    FormFieldValidator<String> validator,
  ) => TextFormField(
    controller: controller,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label),
    validator: validator,
  );
}
