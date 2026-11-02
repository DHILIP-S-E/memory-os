import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';

/// Wraps the whole app: reports scroll movement to the [ScrollGuard] and draws its prompts
/// (a dismissible nudge, then a full-screen break) above whatever screen is showing.
class ScrollGuardHost extends StatelessWidget {
  final Widget child;

  /// Opens the capture screen. Runs after the prompt has closed itself.
  final VoidCallback onCapture;

  const ScrollGuardHost({super.key, required this.child, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final guard = context.watch<ScrollGuard>();
    final pending = guard.pending;

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        // Only the user's own drag counts; programmatic jumps (scroll to top) do not.
        if (n.dragDetails != null) context.read<ScrollGuard>().onScroll();
        return false;
      },
      child: Stack(
        children: [
          child,
          if (pending == ScrollGuardLevel.nudge)
            Positioned(
              left: 16,
              right: 16,
              top: 0,
              child: SafeArea(
                child: _NudgeBanner(
                  minutes: guard.scrolled.inMinutes,
                  onCapture: () {
                    guard.dismiss();
                    onCapture();
                  },
                  onDismiss: guard.dismiss,
                ),
              ),
            ),
          if (pending == ScrollGuardLevel.breakTime)
            Positioned.fill(
              child: _BreakScreen(
                minutes: guard.scrolled.inMinutes,
                onCapture: () {
                  guard.dismiss();
                  onCapture();
                },
                onContinue: guard.dismiss,
              ),
            ),
        ],
      ),
    );
  }
}

class _NudgeBanner extends StatelessWidget {
  final int minutes;
  final VoidCallback onCapture;
  final VoidCallback onDismiss;

  const _NudgeBanner({required this.minutes, required this.onCapture, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('scroll-nudge'),
      color: AppColors.surfaceDark,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "You've been scrolling for $minutes min",
                    style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textLight),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Capture a quick memory instead?',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('scroll-nudge-capture'),
              onPressed: onCapture,
              child: const Text('Capture'),
            ),
            // No tooltip: this sits above the Navigator, so there is no Overlay to show one in.
            IconButton(
              key: const ValueKey('scroll-nudge-dismiss'),
              icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakScreen extends StatefulWidget {
  final int minutes;
  final VoidCallback onCapture;
  final VoidCallback onContinue;

  const _BreakScreen({required this.minutes, required this.onCapture, required this.onContinue});

  @override
  State<_BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<_BreakScreen> {
  static const _pauseSeconds = 30;
  late int _left = _pauseSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) t.cancel();
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('scroll-break'),
      color: AppColors.surfaceDark,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.self_improvement, color: AppColors.textLight, size: 56),
              const SizedBox(height: 24),
              Text(
                'Time for a break',
                textAlign: TextAlign.center,
                style: AppTextStyles.displayMedium.copyWith(color: AppColors.textLight),
              ),
              const SizedBox(height: 12),
              Text(
                "That's ${widget.minutes} minutes of scrolling. Turn it into something you'll keep: capture one thing from today.",
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: const ValueKey('scroll-break-capture'),
                onPressed: widget.onCapture,
                child: const Text('Capture a memory'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('scroll-break-continue'),
                onPressed: _left > 0 ? null : widget.onContinue,
                child: Text(_left > 0 ? 'Not now (${_left}s)' : 'Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
