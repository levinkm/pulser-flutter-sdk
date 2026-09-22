import '../network/api_client.dart';

class EventService {
  final ApiClient _api;
  final String _sessionId;

  // Rolling breadcrumb buffer — last 50 events in this session
  final List<Map<String, dynamic>> _breadcrumbs = [];
  static const _maxBreadcrumbs = 50;

  List<Map<String, dynamic>> get breadcrumbs => List.unmodifiable(_breadcrumbs);

  EventService({required ApiClient api, required String sessionId})
      : _api = api,
        _sessionId = sessionId;

  Future<String> track(String event, {List<String>? tags, Map<String, dynamic>? properties}) async {
    // Record in breadcrumb buffer before sending
    _breadcrumbs.add({
      'event': event,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (properties != null) 'properties': properties,
    });
    if (_breadcrumbs.length > _maxBreadcrumbs) _breadcrumbs.removeAt(0);

    final resp = await _api.authenticatedRequest('POST', '/client/events', body: {
      'event': event,
      if (tags != null) 'tags': tags,
      if (properties != null) 'properties': properties,
      'session_id': _sessionId,
    });
    return resp['event_id'] as String? ?? '';
  }
}
