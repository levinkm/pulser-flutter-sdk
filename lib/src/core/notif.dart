import 'dart:io';
import 'dart:math';

import '../models/inbox_item.dart';
import '../models/inapp_message.dart';
import '../network/api_client.dart';
import '../network/ws_manager.dart';
import '../services/apns_token_service.dart';
import '../services/consent_service.dart';
import '../services/event_service.dart';
import '../services/inapp_service.dart';
import '../services/inbox_service.dart';
import '../services/notification_tracker.dart';
import '../services/preference_service.dart';
import '../services/user_service.dart';
import '../storage/secure_store.dart';
import 'config.dart';
import 'fcm_checker.dart';

typedef NotificationListener = void Function(InboxItem item);
typedef InAppListener = void Function(List<InAppMessage> messages);
typedef ConnectionListener = void Function(bool connected);

/// Main entry point for the Pulser SDK.
///
/// ```dart
/// final notif = Notif(config: PulserConfig(...));
/// await notif.identify(
///   userId: 'user_123',
///   pushToken: token,
///   tags: ['verified'],
///   profile: UserProfile(name: 'John', nationality: 'GH'),
/// );
/// notif.onNotification = (item) => ...;
/// ```
class Pulser {
  final PulserConfig config;
  final SecureStore _store;
  final ApiClient _api;
  late final InboxService inbox;
  late final EventService events;
  late final PreferenceService preferences;
  late final InAppService inApp;
  late final NotificationTracker notifications;
  late final UserService users;
  late final ConsentService consent;
  WSManager? _ws;

  final String _sessionId;
  bool _identified = false;
  ApnsTokenService? _apnsService;

  /// Whether [identify] has been called in this session.
  bool get isIdentified => _identified;

  /// Whether there is a pending anonymous ID to alias.
  /// Returns false after [alias] has been called (anonymous ID is cleared).
  Future<bool> get hasAnonymousSession async {
    final id = await _store.rawAnonymousId;
    return id != null;
  }

  /// Called when a new inbox notification arrives (real-time or sync).
  NotificationListener? onNotification;

  /// Called when in-app messages should be displayed.
  InAppListener? onInAppMessage;

  /// Called when WebSocket connection state changes.
  ConnectionListener? onConnectionChange;

  /// Called when a foreground FCM message arrives.
  /// Wire this to show a local notification in your app.
  /// The SDK handles delivery tracking automatically.
  set onForegroundMessage(ForegroundMessageHandler? handler) {
    notifications.onForegroundMessage = handler;
  }

  Pulser({required this.config})
      : _store = SecureStore(),
        _api = ApiClient(config: config, store: SecureStore()),
        _sessionId = _generateSessionId() {
    config.validate();

    final platform = _detectPlatform();
    inbox = InboxService(api: _api, store: _store);
    events = EventService(api: _api, sessionId: _sessionId);
    preferences = PreferenceService(api: _api);
    inApp = InAppService(api: _api, sessionId: _sessionId, platform: platform);
    notifications = NotificationTracker(api: _api);
    users = UserService(api: _api);
    consent = ConsentService(api: _api);
  }

  /// Identify the current user. Registers the device and syncs profile/tags.
  /// Call on login or app launch after obtaining the push token.
  ///
  /// [pushToken]  — FCM or APNs token.
  /// [tags]       — Tags to apply immediately (e.g. ["verified", "premium"]).
  /// [profile]    — Optional personalisation fields (name, DOB, nationality, etc.).
  /// [email]      — User email for personalisation and email channel.
  /// [consent]    — Consent decisions to record at login (e.g. from signup checkbox).
  ///
  /// Example with consent:
  /// ```dart
  /// await notif.identify(
  ///   userId: 'user_123',
  ///   pushToken: token,
  ///   consent: [
  ///     ConsentInput(channel: 'email', purpose: ConsentPurpose.marketing, consented: true),
  ///     ConsentInput(channel: 'push', purpose: ConsentPurpose.marketing, consented: true),
  ///   ],
  /// );
  /// ```
  Future<void> identify({
    required String userId,
    String? pushToken,
    String? username,
    String? email,
    List<String>? tags,
    UserProfile? profile,
    List<ConsentInput>? consent,
    Map<String, String>? deviceInfo,
  }) async {
    final storedUserId = await _store.userId;

    if (storedUserId != null && storedUserId != userId) {
      await _store.clear();
    }

    // On iOS, pick up any APNs token that arrived before identify() was called
    String? pendingApns;
    if (Platform.isIOS) {
      pendingApns = await _store.pendingAPNsToken;
      if (pendingApns != null) await _store.clearPendingAPNsToken();
    }

    await _registerDevice(
      userId: userId,
      pushToken: pushToken,
      apnsToken: pendingApns,
      username: username,
      deviceInfo: deviceInfo,
    );
    await _store.setUserId(userId);
    _identified = true;
    await notifications.onIdentified();

    // Wire consent service so standalone calls work after identify
    this.consent.setUserId(userId);

    if (tags != null || profile != null || email != null || (consent != null && consent.isNotEmpty)) {
      users.identify(
        userId: userId,
        tags: tags,
        profile: profile,
        email: email,
        consent: consent,
      ).ignore();
    }

    await _connectWS();
  }

  /// Alias the current anonymous ID to an identified user.
  /// Call this immediately after the user logs in, before or alongside [identify].
  /// The anonymous ID is auto-generated on first app launch and cleared after aliasing.
  Future<void> alias(String userId) async {
    final anonymousId = await _store.anonymousId;
    await users.alias(anonymousId: anonymousId, userId: userId);
    await _store.clearAnonymousId();
  }

  /// Update FCM push token (call when Firebase refreshes it on Android/iOS).
  /// On iOS this only updates the FCM token and leaves the APNs token untouched.
  /// APNs token rotation is handled automatically by [initAPNs].
  Future<void> updatePushToken(String token) async {
    if (!_identified) return;
    final userId = await _store.userId;
    if (userId == null) return;
    // Pass only the FCM token — apnsToken is omitted so the upsert
    // preserves the existing apns_token column value on the backend.
    await _registerDevice(userId: userId, pushToken: token);
  }

  /// Initialise native APNs token handling on iOS.
  /// Call this once after constructing Pulser, before identify().
  /// Handles first registration and all future token rotations automatically.
  ///
  /// On Android this is a no-op — FCM handles tokens.
  ///
  /// ```dart
  /// final pulser = Pulser(config: PulserConfig(...));
  /// await pulser.initAPNs();
  /// await pulser.identify(userId: 'user_123');
  /// ```
  Future<void> initAPNs() async {
    if (!Platform.isIOS) return;
    _apnsService = ApnsTokenService(
      onToken: (apnsToken) async {
        final userId = await _store.userId;
        if (_identified && userId != null) {
          // Rotation: register new token alongside the stored FCM token so the
          // backend always has both and can fall back to FCM if APNs fails.
          final fcmToken = await _store.fcmToken;
          await _registerDevice(userId: userId, pushToken: fcmToken, apnsToken: apnsToken);
        } else {
          // Not yet identified — store for consume on next identify()
          await _store.setPendingAPNsToken(apnsToken);
        }
      },
      onDelivery: (notifId) => notifications.markDelivered(notifId).ignore(),
    );
    await _apnsService!.init();
  }

  /// Logout — deactivates device on server, clears stored credentials, disconnects.
  Future<void> logout() async {
    // Notify server to deactivate this device
    try {
      final deviceId = await _store.deviceId;
      if (deviceId != null) {
        await _api.authenticatedRequest('DELETE', '/api/v1/devices/$deviceId');
      }
    } catch (_) {
      // Best-effort — don't block logout if server is unreachable
    }

    _ws?.disconnect();
    _ws = null;
    _identified = false;
    await _store.clear();
  }

  /// Dispose all resources. Call in app lifecycle dispose.
  void dispose() {
    _ws?.disconnect();
    _api.dispose();
  }

  // --- Private ---

  Future<void> _registerDevice({
    required String userId,
    String? pushToken,
    String? apnsToken,
    String? username,
    Map<String, String>? deviceInfo,
  }) async {
    if ((pushToken == null || pushToken.isEmpty) &&
        (apnsToken == null || apnsToken.isEmpty)) {
      return; // no token yet — will arrive via callback
    }

    // Persist FCM token so APNs rotation can pair both tokens together
    if (pushToken != null && pushToken.isNotEmpty) {
      await _store.setFCMToken(pushToken);
    }

    final fcmAvailable = await checkFCMAvailability();

    final body = <String, dynamic>{
      'user_id': userId,
      'platform': _detectPlatform(),
      if (pushToken != null && pushToken.isNotEmpty) 'token': pushToken,
      if (apnsToken != null && apnsToken.isNotEmpty) 'apns_token': apnsToken,
      if (fcmAvailable != null) 'fcm_available': fcmAvailable,
      if (username != null) 'username': username,
      ...?deviceInfo,
    };

    final resp = await _api.apiKeyRequest('POST', '/api/v1/devices', body: body);

    final deviceToken = resp['device_token'] as String?;
    final deviceId = resp['device']?['id'] as String?;

    if (deviceToken == null) throw Exception('Registration failed: no device_token returned');

    await _store.setDeviceToken(deviceToken);
    if (deviceId != null) await _store.setDeviceId(deviceId);
  }

  Future<void> _connectWS() async {
    if (_ws != null && _ws!.isConnected) return;
    _ws?.disconnect();
    _ws = WSManager(
      api: _api,
      onMessage: _handleWSMessage,
      onConnectionChange: (connected) => onConnectionChange?.call(connected),
    );
    await _ws!.connect();
  }

  void _handleWSMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'connected':
        // Server tells us latest_seq — sync if behind
        _handleConnected(msg);
        break;
      case 'inbox:new':
        _handleNewInboxItem(msg['item'] as Map<String, dynamic>? ?? {});
        break;
      case 'inapp:show':
        final messages = (msg['messages'] as List? ?? [])
            .map((j) => InAppMessage.fromJson(j as Map<String, dynamic>))
            .toList();
        if (messages.isNotEmpty) onInAppMessage?.call(messages);
        break;
    }
  }

  Future<void> _handleConnected(Map<String, dynamic> msg) async {
    final serverSeq = msg['latest_seq'] as int? ?? 0;
    final localSeq = await _store.lastSeq;
    if (serverSeq > localSeq) {
      final resp = await inbox.sync();
      for (final item in resp.items) {
        onNotification?.call(item);
      }
    }
  }

  Future<void> _handleNewInboxItem(Map<String, dynamic> itemJson) async {
    final sequential = await inbox.handleNewItem(itemJson);
    if (sequential) {
      onNotification?.call(InboxItem.fromJson(itemJson));
    } else {
      // Gap detected — full sync
      final resp = await inbox.sync();
      for (final item in resp.items) {
        onNotification?.call(item);
      }
    }
  }

  static String _detectPlatform() {
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {}
    return 'web';
  }

  static String _generateSessionId() =>
      'sess_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
}
