import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:personal_memory_os/core/config.dart';

/// Base HTTP client for all FastAPI calls.
/// Auto-injects the backend's JWT bearer token from the token provider function.
/// Handles JSON serialisation and HTTP error mapping.
class ApiClient {
  final String _baseUrl;
  final Future<String?> Function() _getToken;

  ApiClient({
    String? baseUrl,
    required Future<String?> Function() getToken,
  })  : _baseUrl = baseUrl ?? AppConfig.backendUrl,
        _getToken = getToken;

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final response = await http.get(uri, headers: await _headers());
    return _handle(response);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handle(response);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handle(response);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _handle(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
    );
    return _handle(response);
  }

  /// Upload a file directly to object storage (Cloudflare R2) using a pre-signed PUT URL.
  /// No auth header needed — pre-signed URLs carry their own credentials.
  Future<void> putFileToStorage(String uploadUrl, List<int> bytes, String contentType) async {
    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Upload failed: ${response.body}');
    }
  }

  dynamic _handle(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    String detail = response.body;
    try {
      final decoded = jsonDecode(response.body);
      detail = decoded['detail'] ?? decoded.toString();
    } catch (_) {}
    throw ApiException(response.statusCode, detail);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
