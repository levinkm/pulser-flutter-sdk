/// SDK configuration. Immutable after creation.
class PulserConfig {
  /// Base URL of the Notif API server.
  final String baseURL;

  /// App-level API key (used ONLY for device registration, never stored in plain text).
  final String apiKey;

  /// Your application ID.
  final String appId;

  /// Request timeout.
  final Duration timeout;

  /// Enable certificate pinning (provide SHA-256 fingerprints).
  final List<String>? pinnedCertificates;

  /// Enable debug logging.
  final bool debug;

  const PulserConfig({
    required this.baseURL,
    required this.apiKey,
    required this.appId,
    this.timeout = const Duration(seconds: 10),
    this.pinnedCertificates,
    this.debug = false,
  });

  void validate() {
    if (baseURL.isEmpty) throw ArgumentError('baseURL is required');
    if (apiKey.isEmpty) throw ArgumentError('apiKey is required');
    if (appId.isEmpty) throw ArgumentError('appId is required');
    if (!baseURL.startsWith('http')) throw ArgumentError('baseURL must start with http(s)');
  }
}
