import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

typedef WSMessageHandler = void Function(Map<String, dynamic> message);

/// Manages a single WebSocket connection with:
/// - Ticket-based authentication
/// - Exponential backoff reconnect
/// - App lifecycle awareness (pause on background, resume on foreground)
/// - Rate-limit-aware backoff
class WSManager with WidgetsBindingObserver {
  final ApiClient _api;
  final WSMessageHandler _onMessage;
  final void Function(bool)? _onConnectionChange;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastMessageAt;
  bool _disposed = false;
  bool _connecting = false;
  bool _appInForeground = true;
  int _reconnectAttempts = 0;

  static const _maxReconnectDelay = Duration(seconds: 60);
  static const _heartbeatInterval = Duration(seconds: 30);
  static const _heartbeatTimeout = Duration(seconds: 55);

  bool get isConnected => _channel != null;

  WSManager({
    required ApiClient api,
    required WSMessageHandler onMessage,
    void Function(bool)? onConnectionChange,
  })  : _api = api,
        _onMessage = onMessage,
        _onConnectionChange = onConnectionChange {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        // Reconnect if we lost connection while in background
        if (!isConnected && !_disposed) {
          _reconnectAttempts = 0; // reset backoff on foreground
          connect();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _appInForeground = false;
        // Cleanly close — Android will kill it anyway, this avoids error logs
        _reconnectTimer?.cancel();
        _heartbeatTimer?.cancel();
        _subscription?.cancel();
        _channel?.sink.close();
        _channel = null;
        break;
    }
  }

  Future<void> connect() async {
    if (_disposed || _connecting || !_appInForeground) return;
    _connecting = true;

    try {
      final resp = await _api.authenticatedRequest('POST', '/client/ws/ticket');
      final wsUrl = resp['ws_url'] as String?;
      if (wsUrl == null) throw Exception('No ws_url in ticket response');

      final apiBaseUrl = Uri.parse(_api.baseURL);
      final apiHost = apiBaseUrl.host;
      final apiPort = apiBaseUrl.port;
      final isPlainHttp = apiBaseUrl.scheme == 'http';
      var uri = Uri.parse(wsUrl);
      uri = uri.replace(
        scheme: isPlainHttp ? 'ws' : uri.scheme,
        host: apiHost,
        port: apiPort > 0 ? apiPort : null,
      );

      _channel = WebSocketChannel.connect(uri);
      try {
        await _channel!.ready;
      } catch (e) {
        _channel = null;
        rethrow;
      }

      _subscription = _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          _lastMessageAt = DateTime.now();
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _onMessage(msg);
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );

      _startHeartbeat();
      _onConnectionChange?.call(true);
    } on PulserRateLimitException catch (e) {
      _onConnectionChange?.call(false);
      final delay =
          Duration(seconds: e.retryAfterSeconds > 0 ? e.retryAfterSeconds : 60);
      _scheduleReconnect(override: delay);
    } catch (e, st) {
      debugPrint('🔴 WS connect failed: $e\n$st');
      _onConnectionChange?.call(false);
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void disconnect() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _onConnectionChange?.call(false);
  }

  void _handleDisconnect() {
    _channel = null;
    _subscription = null;
    _heartbeatTimer?.cancel();
    _onConnectionChange?.call(false);
    // Only reconnect if app is in foreground
    if (!_disposed && _appInForeground) _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _lastMessageAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!_appInForeground) return;
      if (_lastMessageAt == null) return;
      final silence = DateTime.now().difference(_lastMessageAt!);
      if (silence > _heartbeatTimeout) {
        _channel?.sink.close();
        _handleDisconnect();
      }
    });
  }

  void _scheduleReconnect({Duration? override}) {
    _reconnectTimer?.cancel();
    final delay = override ?? _calculateBackoff();
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      connect();
    });
  }

  Duration _calculateBackoff() {
    final base =
        Duration(seconds: min(pow(2, _reconnectAttempts).toInt() * 2, 60));
    final jitter = Duration(milliseconds: Random().nextInt(2000));
    final total = base + jitter;
    return total > _maxReconnectDelay ? _maxReconnectDelay : total;
  }
}
