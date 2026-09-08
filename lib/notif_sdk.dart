/// Pulser SDK — secure multi-channel notification client.
///
/// ```dart
/// final notif = Notif.initialize(
///   config: PulserConfig(
///     baseURL: 'https://api.notif.io',
///     apiKey: 'nk_...',
///     appId: 'app_...',
///   ),
/// );
/// await notif.identify(userId: 'user_123', pushToken: fcmToken);
/// ```
library pulser_sdk;

export 'src/core/notif.dart';
export 'src/core/config.dart';
export 'src/core/fcm_checker.dart';
export 'src/models/inbox_item.dart';
export 'src/models/inapp_message.dart';
export 'src/models/preferences.dart';
export 'src/services/inbox_service.dart';
export 'src/services/event_service.dart';
export 'src/services/preference_service.dart';
export 'src/services/inapp_service.dart';
export 'src/services/notification_tracker.dart';
export 'src/services/user_service.dart';
export 'src/services/consent_service.dart';
export 'src/services/apns_token_service.dart';
