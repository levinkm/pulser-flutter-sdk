import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../storage/secure_store.dart';

/// API client with automatic auth header injection and retry logic.
class ApiClient {
  final PulserConfig _config;
  final SecureStore _store;
  final http.Client _http;

  String get baseURL => _config.baseURL;
  ApiClient({required PulserConfig config, required SecureStore store})
      : _config = config,
        _store = store,
        _http = http.Client();

  /// Make a request authenticated with the API key (used only for device registration).
  Future<Map<String, dynamic>> apiKeyRequest(String method, String path, {Map<String, dynamic>? body}) async {
    return _request(method, path, body: body, headers: {
      'X-API-Key': _config.apiKey,
      'X-App-ID': _config.appId,
    });
  }

  /// Make a request authenticated with the device token (all client operations).
  Future<Map<String, dynamic>> authenticatedRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    final token = await _store.deviceToken;
    if (token == null) throw PulserAuthException('Not authenticated. Call identify() first.');

    return _request(method, path, body: body, queryParams: queryParams, headers: {
      'Authorization': 'Bearer $token',
    });
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('${_config.baseURL}$path').replace(
      queryParameters: queryParams?.isNotEmpty == true ? queryParams : null,
    );

    headers['Content-Type'] = 'application/json';

    int attempts = 0;
    const maxRetries = 2;

    while (true) {
      try {
        final resp = await _send(method, uri, headers, body).timeout(_config.timeout);
        return _handleResponse(resp);
      } on SocketException catch (e) {
        attempts++;
        if (attempts > maxRetries) throw PulserNetworkException(e.message);
        await Future.delayed(Duration(seconds: attempts));
      } on HttpException catch (e) {
        attempts++;
        if (attempts > maxRetries) throw PulserNetworkException(e.message);
        await Future.delayed(Duration(seconds: attempts));
      } on TimeoutException {
        attempts++;
        if (attempts > maxRetries) throw PulserNetworkException('Request timed out');
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  Map<String, dynamic> _handleResponse(http.Response resp) {
    if (resp.statusCode == 401) throw PulserAuthException('Invalid or expired credentials');
    if (resp.statusCode == 429) {
      final retryAfter = resp.headers['retry-after'] ?? '5';
      throw PulserRateLimitException(int.tryParse(retryAfter) ?? 5);
    }
    if (resp.statusCode >= 400) {
      final errBody = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      final msg = errBody['message'] ?? errBody['error'] ?? 'HTTP ${resp.statusCode}';
      throw PulserApiException(msg, resp.statusCode);
    }
    if (resp.body.isEmpty) return {};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<http.Response> _send(String method, Uri uri, Map<String, String> headers, Map<String, dynamic>? body) {
    final encoded = body != null ? jsonEncode(body) : null;
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encoded);
      case 'PUT':
        return _http.put(uri, headers: headers, body: encoded);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encoded);
      case 'DELETE':
        return _http.delete(uri, headers: headers);
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }

  void dispose() => _http.close();
}

// --- Exceptions ---

class PulserAuthException implements Exception {
  final String message;
  PulserAuthException(this.message);
  @override
  String toString() => 'PulserAuthException: $message';
}

class PulserNetworkException implements Exception {
  final String message;
  PulserNetworkException(this.message);
  @override
  String toString() => 'PulserNetworkException: $message';
}

class PulserRateLimitException implements Exception {
  final int retryAfterSeconds;
  PulserRateLimitException(this.retryAfterSeconds);
  @override
  String toString() => 'PulserRateLimitException: retry after ${retryAfterSeconds}s';
}

class PulserApiException implements Exception {
  final String message;
  final int statusCode;
  PulserApiException(this.message, this.statusCode);
  @override
  String toString() => 'PulserApiException($statusCode): $message';
}

