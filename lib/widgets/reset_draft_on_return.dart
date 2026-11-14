import 'package:material_ui/material_ui.dart';

final draftRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Drops unsaved input when returning from another page. Popup menus and
/// dialogs do not trigger a reset of the form underneath them.
mixin ResetDraftOnReturn<T extends StatefulWidget> on State<T>
    implements RouteAware {
  PageRoute<dynamic>? _draftRoute;
  void resetDraft();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _draftRoute)) return;
    draftRouteObserver.unsubscribe(this);
    _draftRoute = route is PageRoute<dynamic> ? route : null;
    if (_draftRoute != null) draftRouteObserver.subscribe(this, _draftRoute!);
  }

  @override
  void didPopNext() {
    if (mounted) resetDraft();
  }

  @override
  void didPush() {}
  @override
  void didPop() {}
  @override
  void didPushNext() {}
  @override
  void dispose() {
    draftRouteObserver.unsubscribe(this);
    super.dispose();
  }
}
