import 'package:flutter/widgets.dart';
import 'analytics_service.dart';

/// Tracks route stack depth and fires [AnalyticsService.trackScreenView]
/// with a `session_depth` property.
///
/// Supports plain [Navigator] and GoRouter (via [onGoRouterChange]).
///
/// ## Plain Navigator
/// ```dart
/// MaterialApp(
///   navigatorObservers: [RouteStackObserver(pulser.analytics)],
/// )
/// ```
///
/// ## GoRouter (add alongside Navigator usage if mixed)
/// ```dart
/// final _observer = RouteStackObserver(pulser.analytics);
///
/// final _router = GoRouter(
///   observers: [_observer],           // catches nested Navigator pushes
///   redirect: (ctx, state) { ... },
/// );
///
/// // In initState / build — listen to top-level GoRouter location changes:
/// _router.routerDelegate.addListener(() {
///   _observer.onGoRouterChange(_router.routerDelegate.currentConfiguration);
/// });
/// ```
class RouteStackObserver extends NavigatorObserver {
  final AnalyticsService _analytics;
  int _depth = 0;
  String? _current;

  // Tracks route names seen via GoRouter to avoid double-counting when
  // GoRouter also fires Navigator events for the same transition.
  final Set<String> _goRouterSeen = {};

  RouteStackObserver(this._analytics);

  // ── GoRouter ──────────────────────────────────────────────────────────────

  /// Call this from a GoRouter `routerDelegate` listener.
  /// [configuration] is `routerDelegate.currentConfiguration`
  /// which exposes the current URI as a string via `.uri.toString()`.
  void onGoRouterChange(dynamic configuration) {
    final screen = configuration?.uri?.toString() as String?;
    if (screen == null || screen == _current) return;
    _depth++;
    _goRouterSeen.add(screen);
    _emit(screen: screen, previous: _current);
  }

  // ── Plain Navigator ───────────────────────────────────────────────────────

  @override
  void didPush(Route route, Route? previousRoute) {
    final screen = _name(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (screen != null && _goRouterSeen.remove(screen)) return;
      _depth++;
      _track(route, previousRoute);
    });
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_depth > 0) _depth--;
      _track(previousRoute, route);
    });
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _track(newRoute, oldRoute);
    });
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _track(Route? current, Route? previous) {
    final screen = _name(current);
    if (screen == null) return;
    _emit(screen: screen, previous: _name(previous) ?? _current);
  }

  void _emit({required String screen, String? previous}) {
    _analytics.trackScreenView(
      screen: screen,
      previousScreen: previous,
      extra: {'session_depth': _depth},
    );
    _current = screen;
  }

  String? _name(Route? route) => route?.settings.name;
}
