import 'package:flutter/material.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/scroll_guard/usage_source.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';

/// Opt-in for "also nudge me about time in other apps", plus which apps to watch.
/// Needs Android's Usage access, which only the user can grant in system settings.
class ScrollGuardOtherAppsTiles extends StatefulWidget {
  final ScrollGuard guard;
  final UsageSource source;

  const ScrollGuardOtherAppsTiles({super.key, required this.guard, required this.source});

  @override
  State<ScrollGuardOtherAppsTiles> createState() => _ScrollGuardOtherAppsTilesState();
}

class _ScrollGuardOtherAppsTilesState extends State<ScrollGuardOtherAppsTiles> with WidgetsBindingObserver {
  bool? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system Usage access screen: re-check what the user chose there.
    if (state == AppLifecycleState.resumed) _refreshAccess();
  }

  Future<void> _refreshAccess() async {
    final granted = await widget.source.hasAccess();
    if (mounted) setState(() => _access = granted);
  }

  Future<void> _toggle(bool on) async {
    final settings = widget.guard.settings;
    if (!on) {
      await widget.guard.updateSettings(settings.copyWith(watchOtherApps: false));
      return;
    }
    var apps = settings.watchedApps;
    if (apps.isEmpty) {
      final found = await widget.source.installed([for (final a in watchableApps) a.package]);
      apps = [for (final a in watchableApps) if (found.contains(a.package)) a.package];
    }
    await widget.guard.updateSettings(settings.copyWith(watchOtherApps: true, watchedApps: apps));
    if (_access == true || !mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Allow usage access'),
        content: const Text(
          'To notice time in apps like Instagram or TikTok, Android needs you to allow "Usage access" '
          'for this app. We only read how long those apps were open, never what you do in them, '
          'and nothing leaves your phone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Open settings')),
        ],
      ),
    );
    if (open == true) await widget.source.openAccessSettings();
  }

  Future<void> _chooseApps() async {
    final found = await widget.source.installed([for (final a in watchableApps) a.package]);
    if (!mounted) return;
    final installed = [for (final a in watchableApps) if (found.contains(a.package)) a];
    final chosen = {...widget.guard.settings.watchedApps};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Apps to watch'),
          content: installed.isEmpty
              ? const Text('None of the supported social apps are installed on this phone.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final app in installed)
                      CheckboxListTile(
                        key: ValueKey('watch-${app.package}'),
                        title: Text(app.label),
                        value: chosen.contains(app.package),
                        onChanged: (on) => setDialog(() => on == true ? chosen.add(app.package) : chosen.remove(app.package)),
                      ),
                  ],
                ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialog).pop(chosen), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != null) {
      await widget.guard.updateSettings(widget.guard.settings.copyWith(watchedApps: result.toList()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.guard.settings;
    final needsAccess = settings.watchOtherApps && _access == false;
    return Column(
      children: [
        const Divider(height: 1),
        SwitchListTile(
          key: const ValueKey('scroll-guard-other-apps'),
          secondary: const Icon(Icons.apps, color: AppColors.textSecondary, size: 22),
          title: Text('Also watch other apps', style: AppTextStyles.bodyLarge),
          subtitle: Text(
            needsAccess
                ? 'Needs usage access: turn it on in Android settings'
                : 'Notifies you about time in Instagram, TikTok and similar apps',
            style: AppTextStyles.caption.copyWith(color: needsAccess ? AppColors.warning : null),
          ),
          value: settings.watchOtherApps,
          onChanged: _toggle,
        ),
        if (needsAccess)
          ListTile(
            key: const ValueKey('scroll-guard-grant'),
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: const Text('Open usage access settings'),
            trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            onTap: widget.source.openAccessSettings,
          ),
        if (settings.watchOtherApps)
          ListTile(
            key: const ValueKey('scroll-guard-apps'),
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: const Text('Apps to watch'),
            subtitle: Text('${settings.watchedApps.length} selected', style: AppTextStyles.caption),
            trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            onTap: _chooseApps,
          ),
      ],
    );
  }
}
