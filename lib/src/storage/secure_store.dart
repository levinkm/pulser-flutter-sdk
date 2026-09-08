import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted credential storage.
/// iOS: Keychain. Android: EncryptedSharedPreferences. Web: n/a (in-memory).
class SecureStore {
  static const _keyDeviceToken = 'notif_device_token';
  static const _keyDeviceId = 'notif_device_id';
  static const _keyLastSeq = 'notif_last_seq';
  static const _keyUserId = 'notif_user_id';
  static const _keyPendingDeliveries = 'notif_pending_deliveries';
  static const _keyAnonymousId = 'notif_anonymous_id';
  static const _keyPendingAPNsToken = 'notif_pending_apns_token';

  final FlutterSecureStorage _storage;

  SecureStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        );

  Future<String?> get deviceToken => _storage.read(key: _keyDeviceToken);
  Future<void> setDeviceToken(String token) => _storage.write(key: _keyDeviceToken, value: token);

  Future<String?> get deviceId => _storage.read(key: _keyDeviceId);
  Future<void> setDeviceId(String id) => _storage.write(key: _keyDeviceId, value: id);

  Future<String?> get userId => _storage.read(key: _keyUserId);
  Future<void> setUserId(String id) => _storage.write(key: _keyUserId, value: id);

  Future<int> get lastSeq async {
    final v = await _storage.read(key: _keyLastSeq);
    return v != null ? int.tryParse(v) ?? 0 : 0;
  }

  Future<void> setLastSeq(int seq) => _storage.write(key: _keyLastSeq, value: '$seq');

  Future<List<String>> get pendingDeliveries async {
    final v = await _storage.read(key: _keyPendingDeliveries);
    if (v == null || v.isEmpty) return [];
    return v.split(',');
  }

  Future<void> addPendingDelivery(String id) async {
    final current = await pendingDeliveries;
    if (!current.contains(id)) {
      await _storage.write(key: _keyPendingDeliveries, value: [...current, id].join(','));
    }
  }

  Future<void> clearPendingDeliveries() => _storage.delete(key: _keyPendingDeliveries);

  /// Returns the stored anonymous ID, generating and persisting one if absent.
  Future<String> get anonymousId async {
    var id = await _storage.read(key: _keyAnonymousId);
    if (id == null) {
      id = 'anon_${DateTime.now().millisecondsSinceEpoch}';
      await _storage.write(key: _keyAnonymousId, value: id);
    }
    return id;
  }

  /// Returns the stored anonymous ID without generating one if absent.
  Future<String?> get rawAnonymousId => _storage.read(key: _keyAnonymousId);

  Future<void> clearAnonymousId() => _storage.delete(key: _keyAnonymousId);

  /// APNs token received before identify() was called — consumed on next identify().
  Future<String?> get pendingAPNsToken => _storage.read(key: _keyPendingAPNsToken);
  Future<void> setPendingAPNsToken(String token) => _storage.write(key: _keyPendingAPNsToken, value: token);
  Future<void> clearPendingAPNsToken() => _storage.delete(key: _keyPendingAPNsToken);

  /// Wipe all credentials (on logout).
  Future<void> clear() async {
    await _storage.delete(key: _keyDeviceToken);
    await _storage.delete(key: _keyDeviceId);
    await _storage.delete(key: _keyLastSeq);
    await _storage.delete(key: _keyUserId);
  }
}
