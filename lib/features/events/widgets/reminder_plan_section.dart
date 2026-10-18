import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/utils/error_text.dart';

/// The event's reminder plan (spec 4.5): choose when to be reminded before each deadline, and
/// whether to be reminded every day until registered. The server builds the reminders, tags
/// each with its milestone (so finishing that milestone stops exactly those) and schedules both
/// alarm layers. Hidden once the plan exists or when there is nothing left to remind about.
class ReminderPlanSection extends StatefulWidget {
  final Event event;

  const ReminderPlanSection({super.key, required this.event});

  /// True if this event's policy reminders already exist.
  static bool alreadyApplied(Event event, List<Reminder> reminders) =>
      reminders.any((r) => r.source == ReminderSource.eventPolicy && r.contextId == event.id);

  static const stepLabels = {
    'now': 'Right away',
    '7d': '7 days before',
    '3d': '3 days before',
    '1d': '1 day before',
    'morning': 'Deadline morning',
    '3h': '3 hours before',
  };

  @override
  State<ReminderPlanSection> createState() => _ReminderPlanSectionState();
}

class _ReminderPlanSectionState extends State<ReminderPlanSection> {
  ReminderPolicyChoice _choice = const ReminderPolicyChoice();
  List<PolicyReminder>? _preview;
  String? _error;
  bool _saving = false;

  Event get _event => widget.event;

  bool get _hasOpenDeadlines => _event.deadlines.any((d) => !d.isClosed);

  bool get _canRemindDaily =>
      !_event.registrationStatus.stopsReminders &&
      _event.deadlines.any((d) => d.deadlineType == DeadlineType.registration && !d.isClosed);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReminderPlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.event, widget.event)) _load(); // e.g. a milestone was just closed
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final choice = _choice;
    try {
      final preview = await context.read<EventProvider>().previewReminderPolicy(_event.id, choice);
      if (mounted && choice == _choice) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _toggleStep(String step, bool on) {
    final steps = [
      for (final s in ReminderPolicyChoice.steps)
        if (s == step ? on : _choice.cadence.contains(s)) s,
    ];
    if (steps.isEmpty) return; // keep at least one reminder before each deadline
    setState(() => _choice = _choice.copyWith(cadence: steps));
    _load();
  }

  Future<void> _apply() async {
    final events = context.read<EventProvider>();
    final reminders = context.read<ReminderProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final created = await events.applyReminderPolicy(_event.id, _choice);
      await reminders.loadReminders(); // also sets the phone's own alarms for them
      // Only now, after the server saved and scheduled them, say so.
      messenger.showSnackBar(SnackBar(
        content: Text(created == 0 ? 'Those reminders already exist' : '$created reminders scheduled'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e.toString())), backgroundColor: AppColors.urgent));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<ReminderProvider>().reminders;
    if (ReminderPlanSection.alreadyApplied(_event, reminders)) return const SizedBox.shrink();
    final preview = _preview;
    if (preview != null && preview.isEmpty && _error == null) return const SizedBox.shrink();

    final fmt = DateFormat.MMMd().add_jm();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REMINDER PLAN', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textMuted)),
          if (_hasOpenDeadlines) ...[
            const SizedBox(height: 8),
            const Text('Remind me before each deadline:', style: AppTextStyles.caption),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final step in ReminderPolicyChoice.steps)
                  FilterChip(
                    key: ValueKey('step-$step'),
                    label: Text(ReminderPlanSection.stepLabels[step]!),
                    selected: _choice.cadence.contains(step),
                    onSelected: (on) => _toggleStep(step, on),
                  ),
              ],
            ),
          ],
          if (_canRemindDaily)
            SwitchListTile(
              key: const ValueKey('daily-until-registered'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me every day until I register'),
              subtitle: const Text('Stops by itself when you register or the deadline passes', style: AppTextStyles.caption),
              value: _choice.dailyUntilRegistered,
              onChanged: (on) {
                setState(() => _choice = _choice.copyWith(dailyUntilRegistered: on));
                _load();
              },
            ),
          const SizedBox(height: 8),
          if (_error != null)
            Row(
              children: [
                Expanded(child: Text(friendlyError(_error!), style: const TextStyle(color: AppColors.urgent, fontSize: 13))),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            )
          else if (preview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            for (final item in preview.take(4))
              Text(
                item.repeatsDaily
                    ? 'Every day from ${fmt.format(item.at)}  ${item.title}'
                    : '${fmt.format(item.at)}  ${item.title}',
                style: AppTextStyles.caption,
              ),
            if (preview.length > 4) Text('and ${preview.length - 4} more', style: AppTextStyles.caption),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('apply-plan'),
                onPressed: _saving ? null : _apply,
                child: Text(_saving ? 'Scheduling…' : 'Create ${preview.length} reminders'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
