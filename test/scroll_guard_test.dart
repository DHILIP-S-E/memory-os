import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard_host.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/features/settings/scroll_guard_settings_section.dart';

/// A guard on a fake clock; [scrollFor] scrolls once a second for the given time.
class Harness {
  DateTime clock = DateTime(2026, 11, 2, 12);
  final store = MemoryKeyValueStore();
  late final ScrollGuard guard = ScrollGuard(store, now: () => clock);

  void scrollFor(Duration d) {
    for (var s = 0; s < d.inSeconds; s++) {
      clock = clock.add(const Duration(seconds: 1));
      guard.onScroll();
    }
  }
}

void main() {
  group('ScrollGuard detection', () {
    test('stays quiet below the nudge threshold', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 9));
      expect(h.guard.pending, ScrollGuardLevel.none);
    });

    test('nudges at 10 minutes and breaks at 20', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      expect(h.guard.pending, ScrollGuardLevel.nudge);
      h.scrollFor(const Duration(minutes: 10));
      expect(h.guard.pending, ScrollGuardLevel.breakTime);
    });

    test('a pause longer than the idle gap ends the session', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 9));
      h.clock = h.clock.add(const Duration(minutes: 2));
      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 9));
      expect(h.guard.pending, ScrollGuardLevel.none);
    });

    test('dismissing a nudge hides it until the break level', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      h.guard.dismiss();
      expect(h.guard.pending, ScrollGuardLevel.none);
      h.scrollFor(const Duration(minutes: 5));
      expect(h.guard.pending, ScrollGuardLevel.none);
      h.scrollFor(const Duration(minutes: 5));
      expect(h.guard.pending, ScrollGuardLevel.breakTime);
    });

    test('capturing ends the session', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 12));
      h.guard.onCaptured();
      expect(h.guard.pending, ScrollGuardLevel.none);
      expect(h.guard.scrolled, Duration.zero);
    });

    test('does nothing when switched off', () async {
      final h = Harness();
      await h.guard.updateSettings(const ScrollGuardSettings(enabled: false));
      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 30));
      expect(h.guard.pending, ScrollGuardLevel.none);
    });
  });

  group('ScrollGuard stats', () {
    test('a capture after a prompt counts, even after the user stopped scrolling', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      h.clock = h.clock.add(const Duration(minutes: 2)); // stops scrolling, goes to capture
      h.guard.onCaptured();
      expect(h.guard.stats.promptsShown, 1);
      expect(h.guard.stats.capturesAfterPrompt, 1);
      expect(h.guard.stats.minutesReclaimed, 10);
    });

    test('a capture long after the prompt does not count', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      h.clock = h.clock.add(const Duration(minutes: 30));
      h.guard.onCaptured();
      expect(h.guard.stats.capturesAfterPrompt, 0);
    });

    test('one capture is not counted twice', () {
      final h = Harness()..guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      h.guard.onCaptured();
      h.guard.onCaptured();
      expect(h.guard.stats.capturesAfterPrompt, 1);
    });
  });

  group('ScrollGuard storage', () {
    test('settings and stats survive a restart', () async {
      final h = Harness();
      await h.guard.updateSettings(const ScrollGuardSettings(nudgeAfterMinutes: 5, breakAfterMinutes: 15));
      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);

      final reloaded = ScrollGuard(h.store);
      await reloaded.load();
      expect(reloaded.settings.nudgeAfterMinutes, 5);
      expect(reloaded.settings.breakAfterMinutes, 15);
      expect(reloaded.stats.promptsShown, 1);
    });

    test('corrupt storage falls back to defaults', () async {
      final store = MemoryKeyValueStore();
      await store.write(ScrollGuard.settingsKey, 'not json');
      final guard = ScrollGuard(store);
      await guard.load();
      expect(guard.settings.enabled, isTrue);
      expect(guard.settings.nudgeAfterMinutes, 10);
    });

    test('a break threshold at or before the nudge is repaired', () {
      final s = ScrollGuardSettings.fromJson({'nudgeAfterMinutes': 15, 'breakAfterMinutes': 10});
      expect(s.breakAfterMinutes, greaterThan(s.nudgeAfterMinutes));
    });
  });

  group('ScrollGuardHost', () {
    Future<(Harness, List<String>)> pump(WidgetTester tester) async {
      final h = Harness();
      final opened = <String>[];
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: h.guard,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: ScrollGuardHost(
              onCapture: () => opened.add('capture'),
              child: const Material(child: SizedBox.expand()),
            ),
          ),
        ),
      ));
      return (h, opened);
    }

    testWidgets('shows the nudge, and Capture opens capture and closes it', (tester) async {
      final (h, opened) = await pump(tester);
      expect(find.byKey(const ValueKey('scroll-nudge')), findsNothing);

      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-nudge')), findsOneWidget);
      expect(find.textContaining('10 min'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scroll-nudge-capture')));
      await tester.pump();
      expect(opened, ['capture']);
      expect(find.byKey(const ValueKey('scroll-nudge')), findsNothing);
    });

    testWidgets('dismissing the nudge closes it without opening capture', (tester) async {
      final (h, opened) = await pump(tester);
      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('scroll-nudge-dismiss')));
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-nudge')), findsNothing);
      expect(opened, isEmpty);
    });

    testWidgets('the break holds "Not now" for 30 seconds, but Capture works at once', (tester) async {
      final (h, opened) = await pump(tester);
      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 20));
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-break')), findsOneWidget);

      TextButton notNow() => tester.widget(find.byKey(const ValueKey('scroll-break-continue')));
      expect(notNow().onPressed, isNull);

      await tester.pump(const Duration(seconds: 31));
      expect(notNow().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('scroll-break-continue')));
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-break')), findsNothing);
      expect(opened, isEmpty);
    });

    testWidgets('dragging a list reports scrolling; a programmatic jump does not', (tester) async {
      final h = Harness();
      final controller = ScrollController();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: h.guard,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: ScrollGuardHost(
              onCapture: () {},
              child: Material(
                child: ListView(controller: controller, children: [for (var i = 0; i < 50; i++) SizedBox(height: 80, child: Text('row $i'))]),
              ),
            ),
          ),
        ),
      ));

      h.clock = h.clock.add(const Duration(seconds: 5));
      controller.jumpTo(100);
      await tester.pump();
      h.clock = h.clock.add(const Duration(seconds: 5));
      controller.jumpTo(200);
      await tester.pump();
      expect(h.guard.scrolled, Duration.zero);

      await tester.drag(find.byType(ListView), const Offset(0, -100));
      h.clock = h.clock.add(const Duration(seconds: 5));
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      expect(h.guard.scrolled, greaterThan(Duration.zero));
    });
  });

  group('ScrollGuardSettingsSection', () {
    Future<Harness> pump(WidgetTester tester) async {
      final h = Harness();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: h.guard,
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ScrollGuardSettingsSection()))),
      ));
      return h;
    }

    testWidgets('the switch turns the guard off and hides the thresholds', (tester) async {
      final h = await pump(tester);
      expect(find.byKey(const ValueKey('scroll-guard-nudge')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scroll-guard-switch')));
      await tester.pump();
      expect(h.guard.settings.enabled, isFalse);
      expect(find.byKey(const ValueKey('scroll-guard-nudge')), findsNothing);
    });

    testWidgets('raising the nudge past the break pushes the break later', (tester) async {
      final h = await pump(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('scroll-guard-nudge')), matching: find.byType(DropdownButton<int>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();
      expect(h.guard.settings.nudgeAfterMinutes, 30);
      expect(h.guard.settings.breakAfterMinutes, greaterThan(30));
    });

    testWidgets('progress is shown once a nudge has been given', (tester) async {
      final h = await pump(tester);
      expect(find.byKey(const ValueKey('scroll-guard-stats')), findsNothing);

      h.guard.onScroll();
      h.scrollFor(const Duration(minutes: 10));
      h.guard.onCaptured();
      await tester.pump();
      expect(find.textContaining('1 of 1 nudges led to a capture'), findsOneWidget);
    });
  });
}
