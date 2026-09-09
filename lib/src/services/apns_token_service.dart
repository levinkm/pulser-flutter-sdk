import 'dart:io';
import 'package:flutter/services.dart';

/// Manages native APNs token registration on iOS via a platform channel.
/// On Android this is a no-op.
class ApnsTokenService {
  static const _channel = MethodChannel('pulser_sdk/apns');

  final void Function(String token) onToken;
  final void Function(String notifId)? onDelivery;

  ApnsTokenService({required this.onToken, this.onDelivery});

  Future<void> init() async {
    if (!Platform.isIOS) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onToken':
          final token = call.arguments as String?;
          if (token != null && token.isNotEmpty) onToken(token);
        case 'onDelivery':
          final notifId = call.arguments as String?;
          if (notifId != null && notifId.isNotEmpty) onDelivery?.call(notifId);
      }
    });

    await _channel.invokeMethod('register');
  }
}
