import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An app the Scroll Guard knows how to watch.
class WatchableApp {
  final String package;
  final String label;

  const WatchableApp(this.package, this.label);
}

const watchableApps = [
  WatchableApp('com.instagram.android', 'Instagram'),
  WatchableApp('com.instagram.barcelona', 'Threads'),
  WatchableApp('com.zhiliaoapp.musically', 'TikTok'),
  WatchableApp('com.google.android.youtube', 'YouTube'),
  WatchableApp('com.facebook.katana', 'Facebook'),
  WatchableApp('com.twitter.android', 'X'),
  WatchableApp('com.reddit.frontpage', 'Reddit'),
  WatchableApp('com.snapchat.android', 'Snapchat'),
];

/// Time spent in other apps, from Android's Usage Access. The user must grant it in system settings.
abstract class UsageSource {
  /// False on platforms that cannot report other apps' usage (iOS, web, tests).
  bool get supported;

  Future<bool> hasAccess();

  /// Opens the system "Usage access" screen, where the user grants or revokes access.
  Future<void> openAccessSettings();

  /// Which of [packages] are installed on this phone.
  Future<Set<String>> installed(List<String> packages);

  /// Minutes the [packages] were on screen during the last [windowMinutes].
  Future<int> foregroundMinutes(Set<String> packages, int windowMinutes);
}

class NoUsageSource implements UsageSource {
  const NoUsageSource();

  @override
  bool get supported => false;

  @override
  Future<bool> hasAccess() async => false;

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<Set<String>> installed(List<String> packages) async => {};

  @override
  Future<int> foregroundMinutes(Set<String> packages, int windowMinutes) async => 0;
}

/// Android Usage Access via MainActivity's `pmos/usage` channel (no plugin).
class ChannelUsageSource implements UsageSource {
  final MethodChannel _channel;

  const ChannelUsageSource({MethodChannel channel = const MethodChannel('pmos/usage')}) : _channel = channel;

  @override
  bool get supported => defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null; // a failed usage read must never break the app
    }
  }

  @override
  Future<bool> hasAccess() async => (await _call<bool>('hasAccess')) ?? false;

  @override
  Future<void> openAccessSettings() => _call<void>('openAccessSettings');

  @override
  Future<Set<String>> installed(List<String> packages) async {
    final found = await _call<List<Object?>>('installed', {'packages': packages});
    return {for (final p in found ?? const []) if (p is String) p};
  }

  @override
  Future<int> foregroundMinutes(Set<String> packages, int windowMinutes) async =>
      (await _call<int>('foregroundMinutes', {'packages': packages.toList(), 'windowMinutes': windowMinutes})) ?? 0;
}
