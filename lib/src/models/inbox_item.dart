class InboxItem {
  final String id;
  final int seq;
  final String title;
  final String body;
  final String? imageUrl;
  final String? category;
  final bool isRead;
  final List<InboxAction> actions;
  final DateTime createdAt;

  const InboxItem({
    required this.id,
    required this.seq,
    required this.title,
    required this.body,
    this.imageUrl,
    this.category,
    required this.isRead,
    this.actions = const [],
    required this.createdAt,
  });

  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
        id: json['id'] ?? '',
        seq: json['seq'] ?? 0,
        title: json['title'] ?? '',
        body: json['body'] ?? '',
        imageUrl: json['image_url'],
        category: json['category'],
        isRead: json['is_read'] ?? false,
        actions: (json['actions'] as List?)?.map((a) => InboxAction.fromJson(a)).toList() ?? [],
        createdAt: _parseDate(json['created_at']),
      );

  static DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    final s = raw.toString();
    // Append Z if no timezone info so Dart treats it as UTC
    final normalized = (s.contains('Z') || s.contains('+') || s.contains('-', 10))
        ? s
        : '${s}Z';
    return DateTime.tryParse(normalized)?.toLocal() ?? DateTime.now();
  }
}

class InboxAction {
  final String label;
  final String url;
  final String? action;

  const InboxAction({required this.label, required this.url, this.action});

  factory InboxAction.fromJson(Map<String, dynamic> json) => InboxAction(
        label: json['label'] ?? '',
        url: json['url'] ?? '',
        action: json['action'],
      );
}
