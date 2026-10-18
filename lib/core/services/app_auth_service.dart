import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:personal_memory_os/core/config.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';
import 'package:personal_memory_os/core/services/token_store.dart';

/// Email/password login against the app's own backend (/auth/*), no Cognito.
///
/// Stays signed in across restarts and offline: the user and tokens live in
/// secure storage, and the access token is refreshed quietly when it expires.
class AppAuthService implements AuthService {
  static const _kAccess = 'app_access_token';
  static const _kRefresh = 'app_refresh_token';
  static const _kUser = 'app_user';

  final String baseUrl;
  final http.Client _http;
  final TokenStore _store;
  final DateTime Function() _now;

  AppAuthService({
    String? baseUrl,
    http.Client? httpClient,
    TokenStore? tokenStore,
    DateTime Function()? now,
  })  : baseUrl = baseUrl ?? AppConfig.backendUrl,
        _http = httpClient ?? http.Client(),
        _store = tokenStore ?? SecureTokenStore(),
        _now = now ?? DateTime.now;

  Future<http.Response> _post(String path, Map<String, dynamic> body) =>
      _http.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));

  /// The backend's `detail` message, or a generic one.
  static String _detail(http.Response r, String fallback) {
    try {
      final d = jsonDecode(r.body)['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) return (d.first['msg'] ?? fallback).toString();
    } catch (_) {}
    return fallback;
  }

  Future<AppUser> _authenticate(String path, Map<String, dynamic> body) async {
    final http.Response r;
    try {
      r = await _post(path, body);
    } catch (e) {
      // Keep the real cause visible (log + short hint) instead of hiding every
      // failure behind "check your connection".
      debugPrint('AppAuthService $path failed: $e');
      throw const AuthException('Cannot reach the server. Check your internet connection and try again.');
    }
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthException(_detail(r, 'Sign-in failed'));
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    await _store.write(_kAccess, data['access_token'] as String);
    await _store.write(_kRefresh, data['refresh_token'] as String);
    final user = data['user'] as Map<String, dynamic>;
    await _store.write(_kUser, jsonEncode(user));
    return _user(user);
  }

  static AppUser _user(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String?,
      );

  /// Expiry (`exp`) of a JWT, or null if unreadable. Not a security check: the
  /// server verifies every token; this only decides when to refresh.
  static DateTime? expiryOf(String jwt) {
    try {
      final payload = jwt.split('.')[1];
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))));
      return DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000);
    } catch (_) {
      return null;
    }
  }

  /// Access token for the API, refreshed shortly before it expires. Null when
  /// signed out. Offline, the stored token is returned and the request simply fails.
  Future<String?> getAccessToken() async {
    final access = await _store.read(_kAccess);
    if (access == null) return null;
    final expiry = expiryOf(access);
    if (expiry != null && _now().isBefore(expiry.subtract(const Duration(minutes: 1)))) {
      return access;
    }
    final refresh = await _store.read(_kRefresh);
    if (refresh == null) return null;
    try {
      final r = await _post('/auth/refresh', {'refresh_token': refresh});
      if (r.statusCode == 200) {
        final fresh = jsonDecode(r.body)['access_token'] as String;
        await _store.write(_kAccess, fresh);
        return fresh;
      }
      if (r.statusCode == 401) {
        await _store.clear(); // refresh token expired or account deleted
        return null;
      }
    } catch (_) {
      // Offline: keep the session; the stored token may still work or will be
      // refreshed on the next call.
    }
    return access;
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    if (await _store.read(_kAccess) == null) return null;
    final raw = await _store.read(_kUser);
    return raw == null ? null : _user(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<AppUser> signInWithEmail(String email, String password) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  @override
  Future<AppUser> signUp(String email, String password, String displayName) =>
      _authenticate('/auth/register',
          {'email': email, 'password': password, 'display_name': displayName});

  @override
  Future<AppUser> signInWithGoogle(String idToken) => _authenticate('/auth/google', {'id_token': idToken});

  @override
  Future<void> signOut() => _store.clear();
}
