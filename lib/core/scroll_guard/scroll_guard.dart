import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';

/// How far the current scrolling session has escalated.
enum ScrollGuardLevel { none, nudge, breakTime }

/// The user's Scroll Guard preferences.
class ScrollGuardSettings {
  final bool enabled;

  /// Minutes of passive scrolling before the gentle nudge.
  final int nudgeAfterMinutes;

  /// Minutes of passive scrolling before the full-screen break.
  final int breakAfterMinutes;

  /// Android only: also nudge when the user spends this long in the [watchedApps].
  final bool watchOtherApps;

  /// Package names of the other apps to watch (e.g. com.instagram.android).
  final List<String> watchedApps;

  const ScrollGuardSettings({
    this.enabled = true,
    this.nudgeAfterMinutes = 10,
    this.breakAfterMinutes = 20,
    this.watchOtherApps = false,
    this.watchedApps = const [],
  });

  ScrollGuardSettings copyWith({
    bool? enabled,
    int? nudgeAfterMinutes,
    int? breakAfterMinutes,
    bool? watchOtherApps,
    List<String>? watchedApps,
  }) =>
      ScrollGuardSettings(
        enabled: enabled ?? this.enabled,
        nudgeAfterMinutes: nudgeAfterMinutes ?? this.nudgeAfterMinutes,
        breakAfterMinutes: breakAfterMinutes ?? this.breakAfterMinutes,
        watchOtherApps: watchOtherApps ?? this.watchOtherApps,
        watchedApps: watchedApps ?? this.watchedApps,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'nudgeAfterMinutes': nudgeAfterMinutes,
        'breakAfterMinutes': breakAfterMinutes,
        'watchOtherApps': watchOtherApps,
        'watchedApps': watchedApps,
      };

  factory ScrollGuardSettings.fromJson(Map<String, dynamic> json) {
    const defaults = ScrollGuardSettings();
    final nudge = json['nudgeAfterMinutes'];
    final brk = json['breakAfterMinutes'];
    final nudgeMinutes = nudge is int && nudge > 0 ? nudge : defaults.nudgeAfterMinutes;
    var breakMinutes = brk is int && brk > 0 ? brk : defaults.breakAfterMinutes;
    // A hand-edited or old value must never put the break before the nudge.
    if (breakMinutes <= nudgeMinutes) breakMinutes = nudgeMinutes + 1;
    return ScrollGuardSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : defaults.enabled,
      nudgeAfterMinutes: nudgeMinutes,
      breakAfterMinutes: breakMinutes,
      watchOtherApps: json['watchOtherApps'] is bool ? json['watchOtherApps'] as bool : defaults.watchOtherApps,
      watchedApps: json['watchedApps'] is List
          ? [for (final a in json['watchedApps'] as List) if (a is String) a]
          : defaults.watchedApps,
    );
  }
}

/// What the guard has achieved so far; shown on the Today screen.
class ScrollGuardStats {
  final int promptsShown;
  final int capturesAfterPrompt;

  /// Whole minutes of scrolling that ended with the user capturing something.
  final int minutesReclaimed;

  const ScrollGuardStats({this.promptsShown = 0, this.capturesAfterPrompt = 0, this.minutesReclaimed = 0});

  Map<String, dynamic> toJson() => {
        'promptsShown': promptsShown,
        'capturesAfterPrompt': capturesAfterPrompt,
        'minutesReclaimed': minutesReclaimed,
      };

  factory ScrollGuardStats.fromJson(Map<String, dynamic> json) {
    int read(String key) => json[key] is int && (json[key] as int) >= 0 ? json[key] as int : 0;
    return ScrollGuardStats(
      promptsShown: read('promptsShown'),
      capturesAfterPrompt: read('capturesAfterPrompt'),
      minutesReclaimed: read('minutesReclaimed'),
    );
  }
}

/// Detects doom scrolling inside the app and decides when to nudge.
///
/// "Passive scrolling" is scroll movement with no capture. A pause longer than [idleGap]
/// ends the session, and so does capturing something. The UI reports scroll movement with
/// [onScroll]; everything else here is pure state so it can be tested with a fake clock.
class ScrollGuard extends ChangeNotifier {
  static const settingsKey = 'scroll_guard_settings';
  static const statsKey = 'scroll_guard_stats';

  /// A capture this soon after a prompt counts as the prompt working.
  static const conversionWindow = Duration(minutes: 10);

  final KeyValueStore _store;
  final DateTime Function() _now;
  final Duration idleGap;

  ScrollGuardSettings _settings = const ScrollGuardSettings();
  ScrollGuardStats _stats = const ScrollGuardStats();

  Duration _scrolled = Duration.zero;
  DateTime? _lastScroll;
  ScrollGuardLevel _acknowledged = ScrollGuardLevel.none;
  ScrollGuardLevel _counted = ScrollGuardLevel.none;
  DateTime? _lastPromptAt;
  Duration _scrolledAtPrompt = Duration.zero;

  ScrollGuard(
    this._store, {
    DateTime Function()? now,
    this.idleGap = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  ScrollGuardSettings get settings => _settings;
  ScrollGuardStats get stats => _stats;

  /// Passive scrolling time in the current session.
  Duration get scrolled => _scrolled;

  ScrollGuardLevel get _reached {
    if (!_settings.enabled) return ScrollGuardLevel.none;
    if (_scrolled >= Duration(minutes: _settings.breakAfterMinutes)) return ScrollGuardLevel.breakTime;
    if (_scrolled >= Duration(minutes: _settings.nudgeAfterMinutes)) return ScrollGuardLevel.nudge;
    return ScrollGuardLevel.none;
  }

  /// The prompt to show right now, or none if the user already dismissed this level.
  ScrollGuardLevel get pending => _reached.index > _acknowledged.index ? _reached : ScrollGuardLevel.none;

  Future<void> load() async {
    _settings = await _readJson(settingsKey, ScrollGuardSettings.fromJson, _settings);
    _stats = await _readJson(statsKey, ScrollGuardStats.fromJson, _stats);
    notifyListeners();
  }

  Future<T> _readJson<T>(String key, T Function(Map<String, dynamic>) parse, T fallback) async {
    try {
      final raw = await _store.read(key);
      if (raw == null) return fallback;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? parse(decoded) : fallback;
    } catch (_) {
      return fallback; // corrupt storage must never stop the app starting
    }
  }

  Future<void> updateSettings(ScrollGuardSettings next) async {
    _settings = next;
    if (!next.enabled) _resetSession();
    notifyListeners();
    await _store.write(settingsKey, jsonEncode(next.toJson()));
  }

  /// Called for every scroll movement in the app.
  void onScroll() {
    if (!_settings.enabled) return;
    final now = _now();
    final last = _lastScroll;
    if (last != null) {
      final gap = now.difference(last);
      if (gap > idleGap) {
        _resetSession();
      } else {
        _scrolled += gap;
      }
    }
    _lastScroll = now;

    final reached = _reached;
    if (reached.index > _counted.index && reached.index > _acknowledged.index) {
      _counted = reached;
      _lastPromptAt = now;
      _scrolledAtPrompt = _scrolled;
      _stats = ScrollGuardStats(
        promptsShown: _stats.promptsShown + 1,
        capturesAfterPrompt: _stats.capturesAfterPrompt,
        minutesReclaimed: _stats.minutesReclaimed,
      );
      _saveStats();
    }
    notifyListeners();
  }

  /// A notification about time in other apps was sent. If the user captures soon after, it counts.
  void onExternalPrompt(int minutes) {
    _lastPromptAt = _now();
    _scrolledAtPrompt = Duration(minutes: minutes);
    _stats = ScrollGuardStats(
      promptsShown: _stats.promptsShown + 1,
      capturesAfterPrompt: _stats.capturesAfterPrompt,
      minutesReclaimed: _stats.minutesReclaimed,
    );
    _saveStats();
    notifyListeners();
  }

  /// The user closed the prompt; stay quiet until the next level is reached.
  void dismiss() {
    final shown = pending;
    if (shown == ScrollGuardLevel.none) return;
    _acknowledged = shown;
    notifyListeners();
  }

  /// The user captured something: the session is over, and if a prompt led here it worked.
  void onCaptured() {
    final promptedAt = _lastPromptAt;
    if (promptedAt != null && _now().difference(promptedAt) <= conversionWindow) {
      _stats = ScrollGuardStats(
        promptsShown: _stats.promptsShown,
        capturesAfterPrompt: _stats.capturesAfterPrompt + 1,
        minutesReclaimed: _stats.minutesReclaimed + _scrolledAtPrompt.inMinutes,
      );
      _saveStats();
    }
    // The prompt has paid off (or expired); a later capture must not count it again.
    _lastPromptAt = null;
    _scrolledAtPrompt = Duration.zero;
    _resetSession();
    notifyListeners();
  }

  void _resetSession() {
    _scrolled = Duration.zero;
    _lastScroll = null;
    _acknowledged = ScrollGuardLevel.none;
    _counted = ScrollGuardLevel.none;
  }

  void _saveStats() {
    _store.write(statsKey, jsonEncode(_stats.toJson()));
  }
}
