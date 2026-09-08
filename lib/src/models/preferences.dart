class UserPreferences {
  bool optedOut;
  Map<String, bool> channels;
  Map<String, bool> categories;
  String? quietStart;
  String? quietEnd;
  int? maxPerHour;
  int? maxPerDay;

  UserPreferences({
    this.optedOut = false,
    Map<String, bool>? channels,
    Map<String, bool>? categories,
    this.quietStart,
    this.quietEnd,
    this.maxPerHour,
    this.maxPerDay,
  })  : channels = channels ?? {},
        categories = categories ?? {};

  factory UserPreferences.fromJson(Map<String, dynamic> json) => UserPreferences(
        optedOut: json['opted_out'] ?? false,
        channels: Map<String, bool>.from(json['channels'] ?? {}),
        categories: Map<String, bool>.from(json['categories'] ?? {}),
        quietStart: json['quiet_start'],
        quietEnd: json['quiet_end'],
        maxPerHour: json['max_per_hour'],
        maxPerDay: json['max_per_day'],
      );

  Map<String, dynamic> toJson() => {
        'opted_out': optedOut,
        'channels': channels,
        'categories': categories,
        if (quietStart != null) 'quiet_start': quietStart,
        if (quietEnd != null) 'quiet_end': quietEnd,
        if (maxPerHour != null) 'max_per_hour': maxPerHour,
        if (maxPerDay != null) 'max_per_day': maxPerDay,
      };
}
