import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/scroll_guard/other_apps_watcher.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/scroll_guard/usage_source.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/features/settings/scroll_guard_settings_section.dart';

class FakeUsage implements UsageSource {
  @override
  bool supported = true;
  bool access = true;
  int minutes = 0;
  Set<String> installedApps = {'com.instagram.android', 'com.zhiliaoapp.musically'};
  int openedSettings = 0;
  Set<String>? askedPackages;
  int? askedWindow;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<void> openAccessSettings() async => openedSettings++;

  @override
  Future<Set<String>> installed(List<String> packages) async => installedApps.intersection(packages.toSet());

  @override
  Future<int> foregroundMinutes(Set<String> packages, int windowMinutes) async {
    askedPackages = packages;
    askedWindow = windowMinutes;
    return minutes;
  }
}

void main() {
  const watching = ScrollGuardSettings(watchOtherApps: true, watchedApps: ['com.instagram.android']);

  group('OtherAppsWatcher', () {
    late DateTime clock;
    late MemoryKeyValueStore store;
    late ScrollGuard guard;
    late FakeUsage usage;
    late List<(String, String)> sent;
    late OtherAppsWatcher watcher;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      clock = DateTime(2026, 11, 8, 20);
      store = MemoryKeyValueStore();
      guard = ScrollGuard(store, now: () => clock);
      await guard.updateSettings(watching);
      usage = FakeUsage()..minutes = 12;
      sent = [];
      watcher = OtherAppsWatcher(guard, usage, (t, b) async => sent.add((t, b)), now: () => clock);
    });

    test('notifies once the watched apps reach the nudge time, asking only about them', () async {
      expect(await watcher.check(), isTrue);
      expect(sent.single.$1, contains('12 min'));
      expect(usage.askedPackages, {'com.instagram.android'});
      expect(usage.askedWindow, OtherAppsWatcher.windowMinutes);
      expect(guard.stats.promptsShown, 1);
    });

    test('says it is time for a break once the break time is reached', () async {
      usage.minutes = 25;
      await watcher.check();
      expect(sent.single.$1, 'Time for a break');
    });

    test('the break message may follow a nudge inside the cooldown, but only once', () async {
      await watcher.check(); // 12 min: nudge
      clock = clock.add(const Duration(minutes: 10));
      usage.minutes = 22;
      expect(await watcher.check(), isTrue);
      expect(sent.last.$1, 'Time for a break');
      clock = clock.add(const Duration(minutes: 10));
      usage.minutes = 30;
      expect(await watcher.check(), isFalse);
      expect(sent, hasLength(2));
    });

    test('two checks at once send one notification', () async {
      final results = await Future.wait([watcher.check(), watcher.check()]);
      expect(results.where((r) => r), hasLength(1));
      expect(sent, hasLength(1));
      expect(guard.stats.promptsShown, 1);
    });

    test('an external prompt does not steal credit from a recent in-app prompt', () async {
      guard.onScroll();
      for (var i = 0; i < 600; i++) {
        clock = clock.add(const Duration(seconds: 1));
        guard.onScroll();
      }
      usage.minutes = 40;
      await watcher.check();
      guard.onCaptured();
      expect(guard.stats.minutesReclaimed, 10);
    });

    test('stays quiet below the nudge time', () async {
      usage.minutes = 9;
      expect(await watcher.check(), isFalse);
      expect(sent, isEmpty);
    });

    test('sends at most one notification per cooldown', () async {
      await watcher.check();
      clock = clock.add(const Duration(minutes: 30));
      expect(await watcher.check(), isFalse);
      clock = clock.add(const Duration(minutes: 31));
      expect(await watcher.check(), isTrue);
      expect(sent, hasLength(2));
    });

    test('does nothing without usage access, when off, or with no apps chosen', () async {
      usage.access = false;
      expect(await watcher.check(), isFalse);
      usage.access = true;

      await guard.updateSettings(watching.copyWith(watchOtherApps: false));
      expect(await watcher.check(), isFalse);

      await guard.updateSettings(watching.copyWith(watchedApps: []));
      expect(await watcher.check(), isFalse);

      await guard.updateSettings(watching.copyWith(enabled: false));
      expect(await watcher.check(), isFalse);
      expect(sent, isEmpty);
    });

    test('does nothing on a platform that cannot report usage', () async {
      usage.supported = false;
      expect(await watcher.check(), isFalse);
    });

    test('a capture soon after the notification counts as it working', () async {
      await watcher.check();
      clock = clock.add(const Duration(minutes: 3));
      guard.onCaptured();
      expect(guard.stats.capturesAfterPrompt, 1);
      expect(guard.stats.minutesReclaimed, 12);
    });
  });

  group('other-app settings', () {
    test('survive a restart, and bad stored values fall back', () async {
      final store = MemoryKeyValueStore();
      await ScrollGuard(store).updateSettings(watching);
      final reloaded = ScrollGuard(store);
      await reloaded.load();
      expect(reloaded.settings.watchOtherApps, isTrue);
      expect(reloaded.settings.watchedApps, ['com.instagram.android']);

      final odd = ScrollGuardSettings.fromJson({'watchOtherApps': 'yes', 'watchedApps': [1, 'a.b', null]});
      expect(odd.watchOtherApps, isFalse);
      expect(odd.watchedApps, ['a.b']);
    });
  });

  group('settings UI', () {
    Future<(ScrollGuard, FakeUsage)> pump(WidgetTester tester, {FakeUsage? usage}) async {
      final guard = ScrollGuard(MemoryKeyValueStore());
      final source = usage ?? FakeUsage();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: guard),
          Provider<UsageSource>.value(value: source),
        ],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ScrollGuardSettingsSection()))),
      ));
      await tester.pump();
      return (guard, source);
    }

    testWidgets('hidden where other-app usage cannot be read', (tester) async {
      await pump(tester, usage: FakeUsage()..supported = false);
      expect(find.byKey(const ValueKey('scroll-guard-other-apps')), findsNothing);
    });

    testWidgets('turning it on watches the installed apps, and with access granted asks nothing more', (tester) async {
      final (guard, usage) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('scroll-guard-other-apps')));
      await tester.pumpAndSettle();
      expect(guard.settings.watchOtherApps, isTrue);
      expect(guard.settings.watchedApps, unorderedEquals(['com.instagram.android', 'com.zhiliaoapp.musically']));
      expect(find.text('Allow usage access'), findsNothing);
      expect(usage.openedSettings, 0);
    });

    testWidgets('without access it explains, and Open settings goes to the system screen', (tester) async {
      final (guard, usage) = await pump(tester, usage: FakeUsage()..access = false);
      await tester.tap(find.byKey(const ValueKey('scroll-guard-other-apps')));
      await tester.pumpAndSettle();
      expect(find.text('Allow usage access'), findsOneWidget);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(usage.openedSettings, 1);
      expect(guard.settings.watchOtherApps, isTrue);
      expect(find.text('Needs usage access: turn it on in Android settings'), findsOneWidget);
    });

    testWidgets('declining the explanation still leaves it on but flagged as needing access', (tester) async {
      final (_, usage) = await pump(tester, usage: FakeUsage()..access = false);
      await tester.tap(find.byKey(const ValueKey('scroll-guard-other-apps')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(usage.openedSettings, 0);
      expect(find.byKey(const ValueKey('scroll-guard-grant')), findsOneWidget);
    });

    testWidgets('the app picker saves the chosen apps', (tester) async {
      final (guard, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('scroll-guard-other-apps')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('scroll-guard-apps')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('watch-com.zhiliaoapp.musically')));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(guard.settings.watchedApps, ['com.instagram.android']);
    });

    testWidgets('turning it off keeps the app choice but stops watching', (tester) async {
      final (guard, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('scroll-guard-other-apps')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scroll-guard-other-apps')));
      await tester.pumpAndSettle();
      expect(guard.settings.watchOtherApps, isFalse);
      expect(guard.settings.watchedApps, isNotEmpty);
      expect(find.byKey(const ValueKey('scroll-guard-apps')), findsNothing);
    });
  });
}
