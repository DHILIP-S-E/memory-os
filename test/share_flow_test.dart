import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/services/share_source.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/main.dart';
import 'support/stub_services.dart';

class FakeShare implements ShareSource {
  final String? initial;
  final live = StreamController<String>.broadcast();
  FakeShare({this.initial});

  @override
  Future<String?> initialText() async => initial;

  @override
  Stream<String> get texts => live.stream;
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'a@b.co');
  await tester.enterText(find.byType(TextField).at(1), 'password1');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  testWidgets('text shared before sign-in waits, then opens the event screen with it',
      (tester) async {
    final share = FakeShare(initial: 'AWS Hackathon Oct 4-5, register by Oct 1');
    await tester.pumpWidget(
        PersonalMemoryOsApp(deps: stubDeps(), store: MemoryKeyValueStore(), shareSource: share));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Welcome back'), findsOneWidget, reason: 'still on the login screen');
    expect(find.textContaining('Paste event information'), findsNothing);

    await signIn(tester);

    expect(find.textContaining('Paste event information'), findsOneWidget);
    expect(find.text('AWS Hackathon Oct 4-5, register by Oct 1'), findsWidgets);
  });

  testWidgets('text shared while the app is open also opens the event screen',
      (tester) async {
    final share = FakeShare();
    await tester.pumpWidget(
        PersonalMemoryOsApp(deps: stubDeps(), store: MemoryKeyValueStore(), shareSource: share));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await signIn(tester);
    expect(find.textContaining('Paste event information'), findsNothing);

    share.live.add('Gemini Workshop Oct 12 10 AM');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining('Paste event information'), findsOneWidget);
  });
}
