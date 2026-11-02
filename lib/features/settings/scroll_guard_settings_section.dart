import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';

/// Settings for the Scroll Guard: on/off and when to nudge or call a break.
class ScrollGuardSettingsSection extends StatelessWidget {
  const ScrollGuardSettingsSection({super.key});

  static const _nudgeChoices = [5, 10, 15, 30];
  static const _breakChoices = [10, 20, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    final guard = context.watch<ScrollGuard>();
    final settings = guard.settings;
    final stats = guard.stats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'SCROLL GUARD',
            style: AppTextStyles.labelLarge.copyWith(color: AppColors.textMuted, letterSpacing: 1.2),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              SwitchListTile(
                key: const ValueKey('scroll-guard-switch'),
                secondary: const Icon(Icons.swipe_vertical, color: AppColors.textSecondary, size: 22),
                title: Text('Doom-scroll nudges', style: AppTextStyles.bodyLarge),
                subtitle: Text(
                  settings.enabled
                      ? 'Nudges you to capture a memory when you scroll for too long'
                      : 'Off: no nudges or breaks',
                  style: AppTextStyles.caption,
                ),
                value: settings.enabled,
                onChanged: (on) => guard.updateSettings(settings.copyWith(enabled: on)),
              ),
              if (settings.enabled) ...[
                const Divider(height: 1),
                _MinutesTile(
                  tileKey: const ValueKey('scroll-guard-nudge'),
                  title: 'Gentle nudge after',
                  value: settings.nudgeAfterMinutes,
                  choices: _nudgeChoices,
                  onChanged: (m) => guard.updateSettings(settings.copyWith(
                    nudgeAfterMinutes: m,
                    // Keep the break strictly later than the nudge.
                    breakAfterMinutes: settings.breakAfterMinutes > m ? null : m + 10,
                  )),
                ),
                _MinutesTile(
                  tileKey: const ValueKey('scroll-guard-break'),
                  title: 'Full-screen break after',
                  value: settings.breakAfterMinutes,
                  choices: [for (final m in _breakChoices) if (m > settings.nudgeAfterMinutes) m],
                  onChanged: (m) => guard.updateSettings(settings.copyWith(breakAfterMinutes: m)),
                ),
              ],
              if (stats.promptsShown > 0) ...[
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('scroll-guard-stats'),
                  leading: const Icon(Icons.insights_outlined, color: AppColors.textSecondary, size: 22),
                  title: Text('Your progress', style: AppTextStyles.bodyLarge),
                  subtitle: Text(
                    '${stats.capturesAfterPrompt} of ${stats.promptsShown} nudges led to a capture'
                    ' · ${stats.minutesReclaimed} min of scrolling turned into memories',
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MinutesTile extends StatelessWidget {
  final Key tileKey;
  final String title;
  final int value;
  final List<int> choices;
  final ValueChanged<int> onChanged;

  const _MinutesTile({
    required this.tileKey,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // A saved value outside the preset list (hand-edited) must still show, not crash the dropdown.
    final items = {...choices, value}.toList()..sort();
    return ListTile(
      key: tileKey,
      contentPadding: const EdgeInsets.only(left: 72, right: 16),
      title: Text(title),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [for (final m in items) DropdownMenuItem(value: m, child: Text('$m min'))],
        onChanged: (m) {
          if (m != null) onChanged(m);
        },
      ),
    );
  }
}
