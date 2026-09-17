import '../network/api_client.dart';
import '../storage/secure_store.dart';
import 'event_service.dart';

typedef ForegroundMessageHandler = void Function(String title, String body, String? notificationId);

/// Tracks push notification delivery and open interactions back to the server.
///
/// ## Usage
///
/// ```dart
/// // 1. Wire foreground messages
/// FirebaseMessaging.onMessage.listen((message) {
///   final title = message.data['title'] ?? message.notification?.title ?? '';
///   final body  = message.data['body']  ?? message.notification?.body  ?? '';
///   pulser.notifications.handleForegroundMessage(title, body, message.data);
/// });
///
/// // 2. Background handler — persist delivery ID for flush on next launch
/// @pragma('vm:entry-point')
/// Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
///   await PulserNotificationTracker.persistBackgroundDelivery(message.data);
/// }
///
/// // 3. After identify() — SDK flushes automatically
/// ```
class NotificationTracker {
  final ApiClient _api;
  final SecureStore _store;
  final EventService? _events;

  final _queue = <_QueuedCall>[];
  bool _ready = false;

  ForegroundMessageHandler? onForegroundMessage;

  NotificationTracker({required ApiClient api, EventService? events})
      : _api = api,
        _store = SecureStore(),
        _events = events;

  /// Called internally by Pulser after identify() succeeds.
  Future<void> onIdentified() async {
    _ready = true;
    await _flushQueue();
    await _flushBackgroundPending();
  }

  /// Call from FirebaseMessaging.onMessage.
  void handleForegroundMessage(String title, String body, Map<String, dynamic> data) {
    final id = data['notification_id'] as String?;
    if (id != null) markDelivered(id);
    onForegroundMessage?.call(title, body, id);
  }

  /// Persist a background delivery ID. Call from your @pragma('vm:entry-point') handler.
  static Future<void> persistBackgroundDelivery(Map<String, dynamic> data) async {
    final id = data['notification_id'] as String?;
    if (id == null) return;
    await SecureStore().addPendingDelivery(id);
  }

  /// Mark a notification as delivered.
  Future<void> markDelivered(String notificationId) async {
    if (!_ready) {
      _queue.add(_QueuedCall(type: _CallType.delivered, id: notificationId));
      return;
    }
    await _sendTracking('delivered', notificationId);
  }

  /// Mark a notification as opened (CTR).
  Future<void> markOpened(String notificationId) async {
    if (!_ready) {
      _queue.add(_QueuedCall(type: _CallType.opened, id: notificationId));
      return;
    }
    await _sendTracking('opened', notificationId);
  }

  /// Mark a notification as dismissed.
  /// Routes through the event system (notification_dismissed) rather than a
  /// dedicated tracking endpoint, which does not exist on the server.
  Future<void> markDismissed(String notificationId, {String? channel}) async {
    if (!_ready) {
      _queue.add(_QueuedCall(type: _CallType.dismissed, id: notificationId, channel: channel));
      return;
    }
    await _sendDismissed(notificationId, channel: channel);
  }

  Future<void> _sendTracking(String event, String id) async {
    try {
      await _api.authenticatedRequest(
        'POST', '/client/notifications/$event',
        body: {'notification_id': id},
      );
    } catch (_) {}
  }

  Future<void> _sendDismissed(String notificationId, {String? channel}) async {
    if (_events == null) return;
    try {
      await _events!.track('notification_dismissed', properties: {
        'notification_id': notificationId,
        if (channel != null) 'channel': channel,
      });
    } catch (_) {}
  }

  Future<void> _flushQueue() async {
    if (_queue.isEmpty) return;
    final items = List<_QueuedCall>.from(_queue);
    _queue.clear();
    for (final call in items) {
      switch (call.type) {
        case _CallType.delivered:
          await _sendTracking('delivered', call.id);
        case _CallType.opened:
          await _sendTracking('opened', call.id);
        case _CallType.dismissed:
          await _sendDismissed(call.id, channel: call.channel);
      }
    }
  }

  Future<void> _flushBackgroundPending() async {
    try {
      final pending = await _store.pendingDeliveries;
      if (pending.isEmpty) return;
      for (final id in pending) {
        await _sendTracking('delivered', id);
      }
      await _store.clearPendingDeliveries();
    } catch (_) {}
  }
}

enum _CallType { delivered, opened, dismissed }

class _QueuedCall {
  final _CallType type;
  final String id;
  final String? channel;
  const _QueuedCall({required this.type, required this.id, this.channel});
}
