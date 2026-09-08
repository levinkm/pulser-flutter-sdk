import 'dart:io';
import 'package:flutter_apns_only/flutter_apns_only.dart';

/// Manages native APNs token registration and rotation on iOS.
/// Uses flutter_apns_only — no AppDelegate changes required.
/// On Android this is a no-op.
class ApnsTokenService {
  final void Function(String token) onToken;
  final void Function(String notifId)? onDelivery;

  ApnsTokenService({required this.onToken, this.onDelivery});

  Future<void> init() async {
    if (!Platform.isIOS) return;

    final connector = ApnsPushConnectorOnly();

    // Request permission
    await connector.requestNotificationPermissions(
      const IosNotificationSettings(sound: true, badge: true, alert: true),
    );

    // Token registration + rotation — ValueNotifier fires on first registration
    // and every time Apple rotates the token
    connector.token.addListener(() {
      final token = connector.token.value;
      if (token != null && token.isNotEmpty) onToken(token);
    });

    // Wire message handlers for delivery tracking
    connector.configureApns(
      onMessage: (message) async => _handleMessage(message),
      onLaunch: (message) async => _handleMessage(message),
      onResume: (message) async => _handleMessage(message),
    );
  }

  void _handleMessage(ApnsRemoteMessage message) {
    final notifId = message.payload['notification_id'] as String?;
    if (notifId != null && notifId.isNotEmpty) onDelivery?.call(notifId);
  }
}
