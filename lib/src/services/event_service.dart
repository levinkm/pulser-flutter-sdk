import '../network/api_client.dart';

class EventService {
  final ApiClient _api;
  final String _sessionId;

  EventService({required ApiClient api, required String sessionId})
      : _api = api,
        _sessionId = sessionId;

  Future<String> track(String event, {List<String>? tags, Map<String, dynamic>? properties}) async {
    final resp = await _api.authenticatedRequest('POST', '/client/events', body: {
      'event': event,
      if (tags != null) 'tags': tags,
      if (properties != null) 'properties': properties,
      'session_id': _sessionId,
    });
    return resp['event_id'] as String? ?? '';
  }
}
