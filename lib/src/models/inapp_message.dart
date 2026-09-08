class InAppMessage {
  final String id;
  final InAppDisplay display;
  final InAppContent content;
  final int priority;

  const InAppMessage({required this.id, required this.display, required this.content, required this.priority});

  factory InAppMessage.fromJson(Map<String, dynamic> json) => InAppMessage(
        id: json['id'] ?? '',
        display: InAppDisplay.fromJson(Map<String, dynamic>.from(json['display'] ?? {})),
        content: InAppContent.fromJson(Map<String, dynamic>.from(json['content'] ?? {})),
        priority: json['priority'] ?? 0,
      );
}

class InAppDisplay {
  final String type;
  final String? position;
  final bool dismissible;
  final int autoDismissSeconds;
  final bool backdrop;

  const InAppDisplay({required this.type, this.position, this.dismissible = true, this.autoDismissSeconds = 0, this.backdrop = false});

  factory InAppDisplay.fromJson(Map<String, dynamic> json) => InAppDisplay(
        type: json['type'] ?? 'banner',
        position: json['position'],
        dismissible: json['dismissible'] ?? true,
        autoDismissSeconds: json['auto_dismiss'] ?? 0,
        backdrop: json['backdrop'] ?? false,
      );
}

class InAppContent {
  final String? title;
  final String? body;
  final String? imageUrl;
  final List<InAppAction> actions;
  final Map<String, String> data;

  const InAppContent({this.title, this.body, this.imageUrl, this.actions = const [], this.data = const {}});

  factory InAppContent.fromJson(Map<String, dynamic> json) => InAppContent(
        title: json['title'],
        body: json['body'],
        imageUrl: json['image_url'],
        actions: (json['actions'] as List?)?.map((a) => InAppAction.fromJson(a)).toList() ?? [],
        data: Map<String, String>.from(json['data'] ?? {}),
      );
}

class InAppAction {
  final String label;
  final String action;
  final String? url;
  final String? style;

  const InAppAction({required this.label, required this.action, this.url, this.style});

  factory InAppAction.fromJson(Map<String, dynamic> json) => InAppAction(
        label: json['label'] ?? '',
        action: json['action'] ?? '',
        url: json['url'],
        style: json['style'],
      );
}
