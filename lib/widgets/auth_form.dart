import 'package:material_ui/material_ui.dart';

import '../services/auth_service.dart';

enum AuthFormMode { login, signup, reset }

class AuthForm extends StatefulWidget {
  const AuthForm({super.key, required this.mode, this.auth});
  final AuthService? auth;
  final AuthFormMode mode;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final _auth = widget.auth ?? AuthService();
  bool _busy = false, _hidden = true;
  String? _message;
  bool _failed = false;
  String get _title => switch (widget.mode) {
    AuthFormMode.login => 'Login',
    AuthFormMode.signup => 'Sign Up',
    AuthFormMode.reset => 'Forgot Password',
  };
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({bool google = false}) async {
    if (_busy || (!google && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (google) {
        await _auth.signInGoogle();
      } else {
        switch (widget.mode) {
          case AuthFormMode.login:
            await _auth.signInEmail(_email.text, _password.text);
          case AuthFormMode.signup:
            await _auth.signUp(_email.text, _password.text);
          case AuthFormMode.reset:
            await _auth.resetPassword(_email.text);
        }
      }
      if (!mounted) return;
      if (google || widget.mode == AuthFormMode.login) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        setState(() {
          _failed = false;
          _message = widget.mode == AuthFormMode.signup
              ? 'Check your inbox to verify your email, then return to login.'
              : 'If this email has an account, a password reset link will be sent.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = authenticationError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(AuthFormMode mode) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => AuthForm(mode: mode)),
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            disabledBackgroundColor: colors.surfaceContainerHighest,
            minimumSize: const Size.fromHeight(52),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: widget.mode == AuthFormMode.login
            ? null
            : AppBar(
                backgroundColor: colors.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.auto_stories_outlined,
                              size: 30,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'READING TRACKER',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          switch (widget.mode) {
                            AuthFormMode.login => 'Welcome back',
                            AuthFormMode.signup => 'Start your next chapter',
                            AuthFormMode.reset => 'Reset your password',
                          },
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          switch (widget.mode) {
                            AuthFormMode.login =>
                              'Your stories, right where you left them.',
                            AuthFormMode.signup => 'Create an account to keep your reading together.',
                            AuthFormMode.reset => 'Enter your email and we’ll send you a reset link.',
                          },
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _message!,
                              style: TextStyle(
                                color: _failed
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                          ),
                        TextFormField(
                          controller: _email,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) =>
                              v == null ||
                                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(v.trim())
                              ? 'Enter a valid email.'
                              : null,
                        ),
                        if (widget.mode != AuthFormMode.reset) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _hidden,
                            autofillHints: [
                              widget.mode == AuthFormMode.signup
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _hidden
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () =>
                                    setState(() => _hidden = !_hidden),
                                icon: Icon(
                                  _hidden
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Enter your password.'
                                : null,
                          ),
                        ],
                        if (widget.mode == AuthFormMode.signup) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirm,
                            enabled: !_busy,
                            obscureText: _hidden,
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: (v) => v != _password.text
                                ? 'Passwords do not match.'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _busy ? null : () => _submit(),
                          child: Text(
                            _busy
                                ? 'Please wait...'
                                : widget.mode == AuthFormMode.reset
                                ? 'Send reset link'
                                : _title,
                          ),
                        ),
                        if (widget.mode == AuthFormMode.login) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _open(AuthFormMode.reset),
                              child: const Text('Forgot Password?'),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text('or'),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              side: BorderSide(color: colors.outlineVariant),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              foregroundColor: colors.onSurface,
                            ),
                            onPressed: _busy
                                ? null
                                : () => _submit(google: true),
                            icon: Image.asset(
                              'assets/google_logo.png',
                              width: 24,
                              height: 24,
                            ),
                            label: const Text('Continue with Google'),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _open(AuthFormMode.signup),
                            child: const Text("Don't have an account? Sign Up"),
                          ),
                        ] else
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () =>
                                      Navigator.of(context)
                                          .popUntil((r) => r.isFirst),
                            child: const Text('Back to Login'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
