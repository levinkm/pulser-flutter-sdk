import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'event_service.dart';

/// Typed helpers for the Phase 1 analytics event taxonomy.
///
/// All methods enrich events with platform/os_version/app_version automatically.
/// Client-supplied properties always take precedence over auto-enriched ones.
///
/// Usage:
/// ```dart
/// await pulser.analytics.trackLogin(method: 'email', country: 'GH');
/// await pulser.analytics.trackScreenView(screen: 'wallet', previousScreen: 'home');
/// await pulser.analytics.trackFeatureUsed(feature: 'send_money');
/// ```
class AnalyticsService {
  final EventService _events;

  // Completer ensures concurrent calls share one device info fetch instead of
  // each launching their own lookup before the first one completes.
  Completer<Map<String, dynamic>>? _contextCompleter;

  AnalyticsService({required EventService events}) : _events = events;

  // ── Authentication ────────────────────────────────────────────────────────

  Future<void> trackLogin({
    String method = 'email',
    String? country,
    String? city,
    String? timezone,
    Map<String, dynamic>? extra,
  }) async {
    final ctx = await _context();
    await _events.track('login_success', properties: {
      'method': method,
      if (country != null) 'country': country,
      if (city != null) 'city': city,
      'timezone': timezone ?? DateTime.now().timeZoneName,
      ...ctx,
      ...?extra,
    });
  }

  Future<void> trackLoginFailed({required String reason}) async {
    await _events.track('login_failed', properties: {'reason': reason});
  }

  Future<void> trackLogout({int? sessionDurationSeconds}) async {
    await _events.track('logout', properties: {
      if (sessionDurationSeconds != null)
        'session_duration_seconds': sessionDurationSeconds,
    });
  }

  Future<void> trackTokenRefresh() async {
    await _events.track('token_refresh');
  }

  Future<void> trackPasswordResetRequested() async {
    await _events.track('password_reset_requested');
  }

  Future<void> trackPasswordResetCompleted() async {
    await _events.track('password_reset_completed');
  }

  // ── Registration Funnel ───────────────────────────────────────────────────

  Future<void> trackRegisterStart({String referrer = 'organic'}) async {
    await _events.track('register_start', properties: {'referrer': referrer});
  }

  Future<void> trackRegisterStep(
    String step, {
    int? timeOnStepSeconds,
    int? attempts,
  }) async {
    await _events.track('register_step_$step', properties: {
      if (timeOnStepSeconds != null) 'time_on_step_seconds': timeOnStepSeconds,
      if (attempts != null) 'attempts': attempts,
    });
  }

  Future<void> trackRegisterComplete({
    int? timeToCompleteSeconds,
    int? stepsCount,
    String? referrer,
  }) async {
    await _events.track('register_complete', properties: {
      if (timeToCompleteSeconds != null)
        'time_to_complete_seconds': timeToCompleteSeconds,
      if (stepsCount != null) 'steps_count': stepsCount,
      if (referrer != null) 'referrer': referrer,
    });
  }

  Future<void> trackRegisterAbandoned({
    required String lastStep,
    int? timeSpentSeconds,
  }) async {
    await _events.track('register_abandoned', properties: {
      'last_step': lastStep,
      if (timeSpentSeconds != null) 'time_spent_seconds': timeSpentSeconds,
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> trackScreenView({
    required String screen,
    String? previousScreen,
    String? referrer,
  }) async {
    await _events.track('screen_view', properties: {
      'screen': screen,
      if (previousScreen != null) 'previous_screen': previousScreen,
      if (referrer != null) 'referrer': referrer,
    });
  }

  Future<void> trackScreenExit({
    required String screen,
    int? timeOnScreenSeconds,
  }) async {
    await _events.track('screen_exit', properties: {
      'screen': screen,
      if (timeOnScreenSeconds != null)
        'time_on_screen_seconds': timeOnScreenSeconds,
    });
  }

  // ── Engagement ────────────────────────────────────────────────────────────

  Future<void> trackFeatureUsed({required String feature}) async {
    await _events.track('feature_used', properties: {'feature': feature});
  }

  Future<void> trackNotificationTapped({
    required String notificationId,
    String? channel,
    String? screenOpened,
  }) async {
    await _events.track('notification_tapped', properties: {
      'notification_id': notificationId,
      if (channel != null) 'channel': channel,
      if (screenOpened != null) 'screen_opened': screenOpened,
    });
  }

  Future<void> trackNotificationDismissed({
    required String notificationId,
    String? channel,
  }) async {
    await _events.track('notification_dismissed', properties: {
      'notification_id': notificationId,
      if (channel != null) 'channel': channel,
    });
  }

  Future<void> trackSearchPerformed({
    required int queryLength,
    required int resultsCount,
  }) async {
    await _events.track('search_performed', properties: {
      'query_length': queryLength,
      'results_count': resultsCount,
    });
  }

  Future<void> trackAppCrash({String? stackTraceHash}) async {
    await _events.track('app_crash', properties: {
      if (stackTraceHash != null) 'stack_trace_hash': stackTraceHash,
    });
  }

  // ── Device context ────────────────────────────────────────────────────────

  /// Returns cached device context (platform, os_version, app_version).
  /// Uses a Completer so concurrent calls share one fetch instead of racing.
  Future<Map<String, dynamic>> _context() {
    if (_contextCompleter != null) return _contextCompleter!.future;

    _contextCompleter = Completer<Map<String, dynamic>>();

    _fetchContext().then((ctx) {
      _contextCompleter!.complete(ctx);
    }).catchError((e) {
      // Complete with empty map on error so callers are never blocked
      _contextCompleter!.complete(<String, dynamic>{});
    });

    return _contextCompleter!.future;
  }

  Future<Map<String, dynamic>> _fetchContext() async {
    final ctx = <String, dynamic>{
      'platform': Platform.isIOS ? 'ios' : 'android',
    };

    try {
      final pkg = await PackageInfo.fromPlatform();
      ctx['app_version'] = pkg.version;
    } catch (_) {}

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        ctx['os_version'] = ios.systemVersion;
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        ctx['os_version'] = android.version.release;
      }
    } catch (_) {}

    return ctx;
  }
}
