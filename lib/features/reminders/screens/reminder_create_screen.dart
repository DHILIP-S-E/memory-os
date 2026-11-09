import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/utils/error_text.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/shared/widgets/ai_suggestion_banner.dart';

class ReminderCreateScreen extends StatefulWidget {
  const ReminderCreateScreen({super.key});

  @override
  State<ReminderCreateScreen> createState() => _ReminderCreateScreenState();
}

class _ReminderCreateScreenState extends State<ReminderCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Manual form state
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _scheduledAt;
  ReminderPriority _priority = ReminderPriority.medium;
  ReminderType _type = ReminderType.time;
  bool _alarmEnabled = true;
  bool _recurring = false;

  // NLP form state
  final _nlpController = TextEditingController();
  bool _isParsingNlp = false;
  NlpReminderResult? _nlpResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _nlpController.dispose();
    super.dispose();
  }

  Future<void> _parseNlp() async {
    if (_nlpController.text.trim().isEmpty) return;
    setState(() {
      _isParsingNlp = true;
      _nlpResult = null;
    });
    try {
      final aiService = context.read<AiService>();
      final result =
          await aiService.parseNaturalLanguageReminder(_nlpController.text);
      setState(() => _nlpResult = result);
    } catch (_) {
      // Fall back gracefully — user can still set manually
      setState(() => _nlpResult = NlpReminderResult(
            title: _nlpController.text,
            type: ReminderType.time,
            scheduledAt: DateTime.now().add(const Duration(hours: 1)),
            priority: ReminderPriority.medium,
            offsets: [],
          ));
    } finally {
      setState(() => _isParsingNlp = false);
    }
  }

  Future<void> _saveManual() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Please enter a title');
      return;
    }
    await _createReminder(
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      type: _type,
      scheduledAt: _scheduledAt,
      priority: _priority,
      alarmEnabled: _alarmEnabled,
      recurrenceRule: _recurring ? 'FREQ=WEEKLY' : null,
      offsets: [],
      source: ReminderSource.manual,
    );
  }

  Future<void> _saveNlp() async {
    if (_nlpResult == null) return;
    await _createReminder(
      title: _nlpResult!.title,
      type: _nlpResult!.type,
      scheduledAt: _nlpResult!.scheduledAt,
      priority: _nlpResult!.priority,
      alarmEnabled: true,
      offsets: _nlpResult!.offsets
          .map((o) => ReminderOffset(offset: o))
          .toList(),
      source: ReminderSource.nlp,
    );
  }

  Future<void> _createReminder({
    required String title,
    String? description,
    required ReminderType type,
    DateTime? scheduledAt,
    required ReminderPriority priority,
    required bool alarmEnabled,
    String? recurrenceRule,
    required List<ReminderOffset> offsets,
    required ReminderSource source,
  }) async {
    final userId = context.read<AuthProvider>().user?.id ?? 'local';
    final now = DateTime.now();
    final reminder = Reminder(
      id: const Uuid().v4(),
      userId: userId,
      title: title,
      description: description,
      reminderType: type,
      scheduledAt: scheduledAt,
      priority: priority,
      alarmEnabled: alarmEnabled,
      recurrenceRule: recurrenceRule,
      offsets: offsets,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await context.read<ReminderProvider>().createReminder(reminder);
      if (mounted) context.pop();
    } catch (e) {
      _showError(friendlyError(e.toString()));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.urgent),
    );
  }

  /// AI is unsure about the date: the user picks it, then confirms (AI suggests,
  /// the user confirms).
  Future<void> _pickNlpDateTime() async {
    final current = _nlpResult!.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: current.isAfter(DateTime.now()) ? current : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      _nlpResult = _nlpResult!.withScheduledAt(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    });
  }

  Widget _buildAmbiguityCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.help_outline, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Text('Please check', style: AppTextStyles.labelLarge),
          ]),
          const SizedBox(height: 8),
          for (final message in _nlpResult!.ambiguities)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(message, style: AppTextStyles.bodyMedium),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('New Reminder'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Manual'),
            Tab(text: 'Natural Language'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualForm(),
          _buildNlpForm(),
        ],
      ),
    );
  }

  Widget _buildManualForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Title'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            style: AppTextStyles.bodyLarge,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'What do you need to remember?'),
          ),
          const SizedBox(height: 16),
          _buildLabel('Description (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            style: AppTextStyles.bodyLarge,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Add details…'),
          ),
          const SizedBox(height: 20),
          _buildLabel('Type'),
          const SizedBox(height: 8),
          _buildTypeSelector(),
          const SizedBox(height: 20),
          _buildLabel('Date & Time'),
          const SizedBox(height: 8),
          _buildDateTimePicker(),
          const SizedBox(height: 20),
          _buildLabel('Priority'),
          const SizedBox(height: 8),
          _buildPrioritySelector(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Alarm', style: AppTextStyles.titleMedium),
              Switch(
                value: _alarmEnabled,
                onChanged: (v) => setState(() => _alarmEnabled = v),
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recurring (weekly)', style: AppTextStyles.titleMedium),
              Switch(
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveManual,
              child: const Text('Create Reminder'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNlpForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Describe your reminder in plain English. Powered by Gemini.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildLabel('What do you need to remember?'),
          const SizedBox(height: 8),
          TextField(
            controller: _nlpController,
            style: AppTextStyles.bodyLarge,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'e.g. "Remind me 30 minutes before the hackathon"\n"Every Monday at 9 AM check new hackathons"\n"Submit the form by October 20"',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isParsingNlp ? null : _parseNlp,
              icon: _isParsingNlp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent),
                    )
                  : const Icon(Icons.psychology_outlined),
              label: Text(_isParsingNlp ? 'Understanding…' : 'Parse with AI'),
            ),
          ),
          if (_nlpResult != null) ...[
            const SizedBox(height: 24),
            if (_nlpResult!.ambiguities.isNotEmpty) _buildAmbiguityCard(),
            AiSuggestionBanner(
              message: _nlpResult!.title,
              detail: _nlpResult!.scheduledAt != null
                  ? '${_nlpResult!.scheduledAt!.toLocal()}'
                  : null,
              confirmLabel: _nlpResult!.ambiguities.isEmpty
                  ? 'Create Reminder'
                  : 'Choose date & time',
              dismissLabel: 'Edit',
              onConfirm: _nlpResult!.ambiguities.isEmpty ? _saveNlp : _pickNlpDateTime,
              onDismiss: () => setState(() => _nlpResult = null),
            ),
            if (_nlpResult!.offsets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested reminder offsets',
                      style: AppTextStyles.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _nlpResult!.offsets
                          .map((o) => Chip(
                                label: Text(o),
                                backgroundColor:
                                    AppColors.accent.withValues(alpha: 0.1),
                                labelStyle: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12),
                                side: const BorderSide(
                                    color: AppColors.accent,
                                    width: 0.5),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: AppTextStyles.labelLarge
          .copyWith(color: AppColors.textSecondary),
    );
  }

  Widget _buildTypeSelector() {
    const types = [
      (ReminderType.time, 'Time', Icons.access_time),
      (ReminderType.deadline, 'Deadline', Icons.flag_outlined),
      (ReminderType.recurring, 'Recurring', Icons.repeat),
      (ReminderType.followUp, 'Follow-up', Icons.reply_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((t) {
        final (type, label, icon) = t;
        final selected = _type == type;
        return GestureDetector(
          onTap: () => setState(() => _type = type),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  selected ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected
                      ? AppColors.accent
                      : AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 14,
                    color: selected ? Colors.white : AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateTimePicker() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _scheduledAt ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: AppColors.accent),
            ),
            child: child!,
          ),
        );
        if (date == null || !mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? DateTime.now()),
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: AppColors.accent),
            ),
            child: child!,
          ),
        );
        if (time == null) return;
        setState(() {
          _scheduledAt = DateTime(
              date.year, date.month, date.day, time.hour, time.minute);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Text(
              _scheduledAt == null
                  ? 'Set date & time'
                  : '${_scheduledAt!.toLocal()}',
              style: _scheduledAt == null
                  ? AppTextStyles.bodyMedium
                  : AppTextStyles.bodyLarge,
            ),
            const Spacer(),
            if (_scheduledAt != null)
              GestureDetector(
                onTap: () => setState(() => _scheduledAt = null),
                child: const Icon(Icons.clear,
                    size: 16, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrioritySelector() {
    const priorities = [
      (ReminderPriority.low, 'Low', AppColors.priorityLow),
      (ReminderPriority.medium, 'Medium', AppColors.priorityMedium),
      (ReminderPriority.high, 'High', AppColors.priorityHigh),
    ];
    return Row(
      children: priorities.map((p) {
        final (priority, label, color) = p;
        final selected = _priority == priority;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _priority = priority),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.2) : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? color : AppColors.cardBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? color : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
