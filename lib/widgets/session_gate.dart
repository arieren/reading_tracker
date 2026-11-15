import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

/// The root page owns authentication routing. Pushed account/credential pages
/// must leave with their session instead of remaining above the sign-in page.
class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    required this.changes,
    required this.initialUser,
    required this.signedIn,
    required this.signedOut,
  });
  final Stream<User?> changes;
  final User? initialUser;
  final Widget Function(User user) signedIn;
  final Widget Function(String? notice) signedOut;
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  String? _lastUid;
  String? _notice;
  bool _allowed(User? user) =>
      user != null &&
      (user.emailVerified ||
          user.providerData.any((p) => p.providerId == 'google.com'));
  @override
  void initState() {
    super.initState();
    _lastUid = _allowed(widget.initialUser) ? widget.initialUser!.uid : null;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: widget.changes,
    initialData: widget.initialUser,
    builder: (context, snapshot) {
      final user = snapshot.data;
      final nextUid = _allowed(user) ? user!.uid : null;
      if (_lastUid != null && nextUid != _lastUid) {
        _notice = 'Please sign in again. If you verified a new email, use that address with your existing password. Your library is still saved.';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _lastUid != nextUid) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
      _lastUid = nextUid;
      return nextUid == null
          ? widget.signedOut(_notice)
          : widget.signedIn(user!);
    },
  );
}
