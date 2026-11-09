import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/scroll_guard/usage_source.dart';

/// Level 3: when the user has spent the nudge time in their watched apps recently, send a
/// notification pointing back to capture. Checks when the app returns to the foreground and
/// every few minutes while the app process is alive; Android may pause it in the background.
class OtherAppsWatcher with WidgetsBindingObserver {
  /// How far back to look for time spent in the watched apps.
  static const windowMinutes = 60;

  final ScrollGuard guard;
  final UsageSource source;
  final Future<void> Function(String title, String body) notify;
  final DateTime Function() _now;
  final Duration cooldown;
  final Duration interval;

  DateTime? _lastNotified;
  bool _lastWasBreak = false;
  bool _checking = false;
  bool _disposed = false;
  Timer? _timer;

  OtherAppsWatcher(
    this.guard,
    this.source,
    this.notify, {
    DateTime Function()? now,
    this.cooldown = const Duration(minutes: 60),
    this.interval = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => check());
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  /// Sends at most one notification per [cooldown], except that the stronger "break" message may
  /// follow a gentle nudge. Returns true if one was sent.
  Future<bool> check() async {
    final s = guard.settings;
    if (_checking || !s.enabled || !s.watchOtherApps || s.watchedApps.isEmpty || !source.supported) return false;
    // Claimed before the first await, so a timer tick and a resume cannot both notify.
    _checking = true;
    try {
      if (!await source.hasAccess() || _disposed) return false;
      final minutes = await source.foregroundMinutes(s.watchedApps.toSet(), windowMinutes);
      if (_disposed || minutes < s.nudgeAfterMinutes) return false;

      final long = minutes >= s.breakAfterMinutes;
      final last = _lastNotified;
      final coolingDown = last != null && _now().difference(last) < cooldown;
      if (coolingDown && !(long && !_lastWasBreak)) return false;

      _lastNotified = _now();
      _lastWasBreak = long;
      await notify(
        long ? 'Time for a break' : "You've been scrolling for $minutes min",
        long
            ? "That's $minutes minutes in your social apps this hour. Capture one thing from today instead."
            : 'Capture a quick memory instead?',
      );
      if (!_disposed) guard.onExternalPrompt(minutes);
      return true;
    } finally {
      _checking = false;
    }
  }
}
