import '../models/preferences.dart';
import '../network/api_client.dart';

class PreferenceService {
  final ApiClient _api;

  PreferenceService({required ApiClient api}) : _api = api;

  Future<UserPreferences> get() async {
    final resp = await _api.authenticatedRequest('GET', '/client/preferences');
    return UserPreferences.fromJson(resp);
  }

  Future<void> update(UserPreferences prefs) => _api.authenticatedRequest('PUT', '/client/preferences', body: prefs.toJson());

  Future<void> optOutChannel(String channel) => _api.authenticatedRequest('POST', '/client/preferences/channels/$channel/opt-out');
  Future<void> optInChannel(String channel) => _api.authenticatedRequest('POST', '/client/preferences/channels/$channel/opt-in');
  Future<void> optOutCategory(String category) => _api.authenticatedRequest('POST', '/client/preferences/categories/$category/opt-out');
  Future<void> optInCategory(String category) => _api.authenticatedRequest('POST', '/client/preferences/categories/$category/opt-in');
  Future<void> setQuietHours(String start, String end) => _api.authenticatedRequest('POST', '/client/preferences/quiet-hours', body: {'start': start, 'end': end});
}
