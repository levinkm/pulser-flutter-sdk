import '../models/inapp_message.dart';
import '../network/api_client.dart';

class InAppService {
  final ApiClient _api;
  final String _sessionId;
  final String _platform;

  InAppService({required ApiClient api, required String sessionId, required String platform})
      : _api = api,
        _sessionId = sessionId,
        _platform = platform;

  Future<List<InAppMessage>> evaluate({String? screen, String? event}) async {
    final resp = await _api.authenticatedRequest('POST', '/client/inapp/evaluate', body: {
      if (screen != null) 'screen': screen,
      if (event != null) 'event': event,
      'session_id': _sessionId,
      'platform': _platform,
    });
    return (resp['messages'] as List? ?? []).map((j) => InAppMessage.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> recordImpression(String messageId) => _api.authenticatedRequest('POST', '/client/inapp/impression', body: {
        'message_id': messageId,
        'session_id': _sessionId,
      });

  Future<void> recordDismissal(String messageId) => _api.authenticatedRequest('POST', '/client/inapp/dismiss', body: {
        'message_id': messageId,
        'session_id': _sessionId,
      });

  Future<void> recordClick(String messageId, String action) => _api.authenticatedRequest('POST', '/client/inapp/click', body: {
        'message_id': messageId,
        'action': action,
        'session_id': _sessionId,
      });
}
