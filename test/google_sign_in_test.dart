import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/services/app_auth_service.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';
import 'package:personal_memory_os/core/services/google_token_source.dart';
import 'package:personal_memory_os/core/services/token_store.dart';

class FakeGoogle implements GoogleTokenSource {
  String? token;
  Object? error;
  int signOuts = 0;

  FakeGoogle({this.token, this.error});

  @override
  Future<String?> idToken() async {
    if (error != null) throw error!;
    return token;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class RecordingAuth extends StubAuthService {
  final events = <String>[];
  String? googleToken;

  @override
  Future<AppUser> signInWithGoogle(String idToken) async {
    googleToken = idToken;
    events.add('google-sign-in');
    return const AppUser(id: 'g1', email: 'ada@example.com', displayName: 'Ada');
  }

  @override
  Future<void> signOut() async => events.add('sign-out');
}

void main() {
  group('AuthProvider with Google', () {
    test('a Google token signs the user in through the backend', () async {
      final auth = RecordingAuth();
      final provider = AuthProvider(auth, google: FakeGoogle(token: 'id-token-1'));
      expect(provider.canUseGoogle, isTrue);
      expect(await provider.signInWithGoogle(), isTrue);
      expect(auth.googleToken, 'id-token-1');
      expect(provider.isAuthenticated, isTrue);
      expect(provider.user!.email, 'ada@example.com');
    });

    test('closing the Google sheet is not an error', () async {
      final provider = AuthProvider(RecordingAuth(), google: FakeGoogle(token: null));
      expect(await provider.signInWithGoogle(), isFalse);
      expect(provider.error, isNull);
      expect(provider.isAuthenticated, isFalse);
    });

    test('a Google failure is reported in words the screen can show', () async {
      final provider = AuthProvider(
        RecordingAuth(),
        google: FakeGoogle(error: const AuthException('Google sign-in failed. Please try again.')),
      );
      expect(await provider.signInWithGoogle(), isFalse);
      expect(provider.error, 'Google sign-in failed. Please try again.');
    });

    test('without Google configured there is no Google sign-in', () async {
      final provider = AuthProvider(RecordingAuth());
      expect(provider.canUseGoogle, isFalse);
      expect(await provider.signInWithGoogle(), isFalse);
    });
  });

  group('signing out', () {
    test('cleanup runs first, while the session still works, then Google and the session are cleared', () async {
      final auth = RecordingAuth();
      final google = FakeGoogle(token: 't');
      final order = <String>[];
      final provider = AuthProvider(auth, google: google, onSigningOut: () async => order.add('unregister phone'));
      await provider.signInWithGoogle();
      await provider.signOut();
      order.addAll(auth.events.where((e) => e == 'sign-out'));
      expect(order, ['unregister phone', 'sign-out']);
      expect(google.signOuts, 1);
      expect(provider.isAuthenticated, isFalse);
    });

    test('a failing cleanup never stops someone signing out', () async {
      final auth = RecordingAuth();
      final provider = AuthProvider(auth, onSigningOut: () async => throw StateError('offline'));
      await provider.signOut();
      expect(auth.events, ['sign-out']);
      expect(provider.isAuthenticated, isFalse);
    });
  });

  test('AppAuthService sends the Google ID token to /auth/google and keeps the session', () async {
    final calls = <http.Request>[];
    final store = MemoryTokenStore();
    final service = AppAuthService(
      baseUrl: 'http://api',
      tokenStore: store,
      httpClient: MockClient((req) async {
        calls.add(req);
        return http.Response(
          jsonEncode({
            'access_token': 'a.b.c',
            'refresh_token': 'r',
            'user': {'id': 'g1', 'email': 'ada@example.com', 'display_name': 'Ada'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final user = await service.signInWithGoogle('id-token-1');
    expect(user.id, 'g1');
    expect(calls.single.url.path, '/auth/google');
    expect(jsonDecode(calls.single.body), {'id_token': 'id-token-1'});
    expect(await service.getCurrentUser(), isNotNull);
  });
}
