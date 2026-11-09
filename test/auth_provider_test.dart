import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'support/stub_services.dart';

class HangingAuth extends StubAuthService {
  @override
  Future<AppUser?> getCurrentUser() => Completer<AppUser?>().future; // never completes
}

class ThrowingAuth extends StubAuthService {
  @override
  Future<AppUser?> getCurrentUser() async => throw StateError('keystore broke');
}

void main() {
  test('a session check that never finishes falls back to signed out', () {
    fakeAsync((async) {
      final auth = AuthProvider(HangingAuth(), sessionCheckTimeout: const Duration(seconds: 3));
      auth.checkAuthState();
      async.elapse(const Duration(seconds: 2));
      expect(auth.status, AuthStatus.unknown, reason: 'still within the limit');
      async.elapse(const Duration(seconds: 2));
      expect(auth.status, AuthStatus.unauthenticated);
    });
  });

  test('a session check that throws falls back to signed out', () async {
    final auth = AuthProvider(ThrowingAuth());
    await auth.checkAuthState();
    expect(auth.status, AuthStatus.unauthenticated);
  });

  test('a stored session signs the user in', () async {
    final stub = StubAuthService();
    await stub.signInWithEmail('ada@example.com', 'x');
    final auth = AuthProvider(stub);
    await auth.checkAuthState();
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.user!.email, 'ada@example.com');
  });
}
