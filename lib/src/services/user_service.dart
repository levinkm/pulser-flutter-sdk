import '../network/api_client.dart';
import 'consent_service.dart';

/// Represents optional personalisation fields passed by the backend at login.
class UserProfile {
  final String? name;
  final String? dob;
  final String? nationality;
  final String? gender;
  final String? phone;
  final Map<String, String>? extra;

  const UserProfile({
    this.name,
    this.dob,
    this.nationality,
    this.gender,
    this.phone,
    this.extra,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (dob != null) 'dob': dob,
        if (nationality != null) 'nationality': nationality,
        if (gender != null) 'gender': gender,
        if (phone != null) 'phone': phone,
        if (extra != null) 'extra': extra,
      };
}

/// Manages user tags and profile fields.
class UserService {
  final ApiClient _api;

  UserService({required ApiClient api}) : _api = api;

  /// Send identify call with optional tags, profile, and consent decisions.
  /// Consent submitted here is recorded server-side as source: 'identify'.
  Future<void> identify({
    required String userId,
    List<String>? tags,
    UserProfile? profile,
    String? email,
    List<ConsentInput>? consent,
  }) async {
    await _api.apiKeyRequest('POST', '/api/v1/users/identify', body: {
      'user_id': userId,
      if (email != null) 'email': email,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (profile != null) 'profile': profile.toJson(),
      if (consent != null && consent.isNotEmpty)
        'consent': consent.map((c) => c.toJson()).toList(),
    });
  }

  /// Add tags to the current user.
  Future<void> addTags(String userId, List<String> tags) async {
    await _api.apiKeyRequest('POST', '/api/v1/users/$userId/tags', body: {'tags': tags});
  }

  /// Remove tags from the current user.
  Future<void> removeTags(String userId, List<String> tags) async {
    await _api.apiKeyRequest('DELETE', '/api/v1/users/$userId/tags', body: {'tags': tags});
  }

  /// Link an anonymous ID to an identified user.
  Future<void> alias({required String anonymousId, required String userId}) async {
    await _api.apiKeyRequest('POST', '/api/v1/users/alias', body: {
      'anonymous_id': anonymousId,
      'user_id': userId,
    });
  }
}
