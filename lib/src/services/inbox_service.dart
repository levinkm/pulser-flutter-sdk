import '../models/inbox_item.dart';
import '../network/api_client.dart';
import '../storage/secure_store.dart';

class InboxService {
  final ApiClient _api;
  final SecureStore _store;

  InboxService({required ApiClient api, required SecureStore store})
      : _api = api,
        _store = store;

  /// Fetch notification history for the current user.
  ///
  /// [limit] — number of items per page (default 20).
  /// [cursor] — opaque cursor for next page (from previous response).
  /// [unread] — filter to unread only.
  /// [category] — filter by category slug.
  Future<InboxResponse> fetch({
    int limit = 20,
    String? cursor,
    bool? unread,
    String? category,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (cursor != null) params['cursor'] = cursor;
    if (unread != null) params['unread'] = '$unread';
    if (category != null) params['category'] = category;

    final resp = await _api.authenticatedRequest('GET', '/client/inbox', queryParams: params);
    final latestSeq = resp['latest_seq'] as int? ?? 0;
    await _store.setLastSeq(latestSeq);

    return InboxResponse(
      items: _parseItems(resp['items']),
      latestSeq: latestSeq,
      unreadCount: resp['unread_count'] as int? ?? 0,
      hasMore: resp['has_more'] as bool? ?? false,
      nextCursor: resp['next_cursor'] as String?,
    );
  }

  /// Sync only new items since last known sequence. Gap-free delivery guarantee.
  Future<InboxResponse> sync() async {
    final lastSeq = await _store.lastSeq;
    final params = <String, String>{'after_seq': '$lastSeq', 'limit': '100'};
    final resp = await _api.authenticatedRequest('GET', '/client/inbox', queryParams: params);

    final latestSeq = resp['latest_seq'] as int? ?? lastSeq;
    if (latestSeq > lastSeq) await _store.setLastSeq(latestSeq);

    return InboxResponse(
      items: _parseItems(resp['items']),
      latestSeq: latestSeq,
      unreadCount: resp['unread_count'] as int? ?? 0,
      hasMore: resp['has_more'] as bool? ?? false,
    );
  }

  /// Get the current unread badge count.
  Future<int> unreadCount() async {
    final resp = await _api.authenticatedRequest('GET', '/client/inbox/count');
    return resp['unread_count'] as int? ?? 0;
  }

  /// Mark specific notifications as read by their IDs.
  Future<void> markRead(List<String> ids) =>
      _api.authenticatedRequest('POST', '/client/inbox/read', body: {'ids': ids});

  /// Mark all notifications as read.
  Future<void> markAllRead() =>
      _api.authenticatedRequest('POST', '/client/inbox/read-all');

  /// Process a WS inbox:new message. Returns true if sequential, false if gap detected.
  Future<bool> handleNewItem(Map<String, dynamic> itemJson) async {
    final seq = itemJson['seq'] as int? ?? 0;
    final lastSeq = await _store.lastSeq;
    if (seq == lastSeq + 1) {
      await _store.setLastSeq(seq);
      return true;
    }
    return false;
  }

  List<InboxItem> _parseItems(dynamic items) =>
      (items as List? ?? []).map((j) => InboxItem.fromJson(j as Map<String, dynamic>)).toList();
}

class InboxResponse {
  final List<InboxItem> items;
  final int latestSeq;
  final int unreadCount;
  final bool hasMore;
  final String? nextCursor;

  const InboxResponse({
    required this.items,
    required this.latestSeq,
    required this.unreadCount,
    this.hasMore = false,
    this.nextCursor,
  });
}
