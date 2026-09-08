import '../network/api_client.dart';

/// What the user is consenting to receive.
enum ConsentPurpose {
  /// Promotional emails, offers, newsletters, campaigns.
  marketing,

  /// Receipts, OTPs, security alerts, order confirmations.
  /// Transactional notifications are always delivered regardless of consent.
  transactional,

  /// Feature announcements, onboarding tips, product updates.
  product,

  /// Surveys, feedback requests, NPS.
  research,
}

extension ConsentPurposeX on ConsentPurpose {
  String get value => name; // 'marketing', 'transactional', etc.
}

/// A single consent decision — what channel, for what purpose, and whether granted.
class ConsentInput {
  final String channel;       // 'push', 'email', 'in_app', 'sms'
  final ConsentPurpose purpose;
  final bool consented;

  const ConsentInput({
    required this.channel,
    required this.purpose,
    required this.consented,
  });

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'purpose': purpose.value,
        'consented': consented,
      };
}

/// A consent record returned from the server.
class ConsentRecord {
  final String id;
  final String channel;
  final ConsentPurpose purpose;
  final bool consented;
  final String source;
  final DateTime createdAt;

  const ConsentRecord({
    required this.id,
    required this.channel,
    required this.purpose,
    required this.consented,
    required this.source,
    required this.createdAt,
  });

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
        id: json['id'] as String,
        channel: json['channel'] as String,
        purpose: ConsentPurpose.values.firstWhere(
          (p) => p.value == json['purpose'],
          orElse: () => ConsentPurpose.marketing,
        ),
        consented: json['consented'] as bool,
        source: json['source'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Manages consent records for the current user.
///
/// Consent is channel + purpose specific:
/// - `push` + `marketing` — push notifications for offers/campaigns
/// - `email` + `transactional` — receipts, OTPs (always delivered, but good to record)
/// - `push` + `product` — feature update notifications
///
/// Usage:
/// ```dart
/// // At signup — record what the user agreed to
/// await notif.consent.grant(channel: 'email', purpose: ConsentPurpose.marketing);
///
/// // When user opts out in settings
/// await notif.consent.revoke(channel: 'push', purpose: ConsentPurpose.marketing);
///
/// // Check current status
/// final allowed = await notif.consent.check(channel: 'email', purpose: ConsentPurpose.marketing);
/// ```
class ConsentService {
  final ApiClient _api;
  String? _userId;

  ConsentService({required ApiClient api}) : _api = api;

  void setUserId(String userId) => _userId = userId;

  /// Grant consent for a channel + purpose combination.
  Future<void> grant({
    required String channel,
    required ConsentPurpose purpose,
    String source = 'app',
  }) =>
      _record(channel: channel, purpose: purpose, consented: true, source: source);

  /// Revoke consent for a channel + purpose combination.
  Future<void> revoke({
    required String channel,
    required ConsentPurpose purpose,
    String source = 'app',
  }) =>
      _record(channel: channel, purpose: purpose, consented: false, source: source);

  /// Check whether the user has consented to a specific channel + purpose.
  /// Returns true if no record exists (opt-out model).
  Future<bool> check({
    required String channel,
    required ConsentPurpose purpose,
  }) async {
    if (_userId == null) return true;
    try {
      final resp = await _api.apiKeyRequest(
        'GET',
        '/api/v1/users/$_userId/consent/$channel?purpose=${purpose.value}',
      );
      return resp['consented'] as bool? ?? true;
    } catch (_) {
      return true; // fail-open
    }
  }

  /// Returns the full consent history for the current user.
  Future<List<ConsentRecord>> list() async {
    if (_userId == null) return [];
    try {
      final resp = await _api.apiKeyRequest('GET', '/api/v1/users/$_userId/consent');
      final records = resp['consent'] as List? ?? [];
      return records
          .map((r) => ConsentRecord.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _record({
    required String channel,
    required ConsentPurpose purpose,
    required bool consented,
    required String source,
  }) async {
    if (_userId == null) return;
    await _api.apiKeyRequest(
      'POST',
      '/api/v1/users/$_userId/consent',
      body: {
        'channel': channel,
        'purpose': purpose.value,
        'consented': consented,
        'source': source,
      },
    );
  }
}
