import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/shared/widgets/ai_suggestion_banner.dart';

class EventCreateScreen extends StatefulWidget {
  /// Text shared into the app (share sheet) or pasted before opening: it is
  /// dropped into the extract tab and parsed straight away.
  final String? initialText;

  const EventCreateScreen({super.key, this.initialText});

  @override
  State<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends State<EventCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Manual fields
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _urlController = TextEditingController();
  final _organizerController = TextEditingController();
  EventType _eventType = EventType.hackathon;
  DateTime? _startAt;
  DateTime? _endAt;
  DateTime? _registrationDeadline;
  bool _isVirtual = false;

  // NLP / paste fields
  final _pasteController = TextEditingController();
  bool _isParsing = false;
  EventExtractionResult? _extracted;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final shared = widget.initialText?.trim();
    if (shared != null && shared.isNotEmpty) {
      _tabController.index = 1;
      _pasteController.text = shared;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _parseText();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _urlController.dispose();
    _organizerController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  /// Capture-first: copy an event page anywhere, then paste and extract in one tap.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _pasteController.text = text;
    await _parseText();
  }

  Future<void> _parseText() async {
    if (_pasteController.text.trim().isEmpty) return;
    setState(() {
      _isParsing = true;
      _extracted = null;
    });
    try {
      final ai = context.read<AiService>();
      final result = await ai.extractEventFromText(_pasteController.text);
      setState(() => _extracted = result);
    } catch (_) {
      setState(() => _extracted = EventExtractionResult(
            title: 'Event',
            eventType: EventType.custom,
          ));
    } finally {
      setState(() => _isParsing = false);
    }
  }

  Future<void> _saveManual() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Please enter an event title');
      return;
    }
    if (_startAt == null) {
      _showError('Please set the event date and time');
      return;
    }
    await _createEvent(
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      type: _eventType,
      startAt: _startAt!,
      endAt: _endAt,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      eventUrl: _urlController.text.trim().isEmpty
          ? null
          : _urlController.text.trim(),
      organizer: _organizerController.text.trim().isEmpty
          ? null
          : _organizerController.text.trim(),
      isVirtual: _isVirtual,
      registrationDeadline: _registrationDeadline,
    );
  }

  Future<void> _saveExtracted() async {
    if (_extracted == null) return;
    await _createEvent(
      title: _extracted!.title,
      description: _extracted!.description,
      type: _extracted!.eventType,
      startAt: _extracted!.startAt ?? DateTime.now().add(const Duration(days: 1)),
      endAt: _extracted!.endAt,
      location: _extracted!.location,
      eventUrl: _extracted!.eventUrl,
      organizer: _extracted!.organizer,
      isVirtual: _extracted!.isVirtual ?? false,
      registrationDeadline: _extracted!.registrationDeadline,
    );
  }

  Future<void> _createEvent({
    required String title,
    String? description,
    required EventType type,
    required DateTime startAt,
    DateTime? endAt,
    String? location,
    String? eventUrl,
    String? organizer,
    required bool isVirtual,
    DateTime? registrationDeadline,
  }) async {
    final userId = context.read<AuthProvider>().user?.id ?? 'local';
    final now = DateTime.now();
    final deadlines = <EventDeadline>[];

    if (registrationDeadline != null) {
      deadlines.add(EventDeadline(
        id: const Uuid().v4(),
        eventId: '',
        userId: userId,
        title: 'Registration deadline',
        deadlineType: DeadlineType.registration,
        deadlineAt: registrationDeadline,
        createdAt: now,
      ));
    }

    final event = Event(
      id: const Uuid().v4(),
      userId: userId,
      title: title,
      description: description,
      eventType: type,
      startAt: startAt,
      endAt: endAt,
      location: location,
      eventUrl: eventUrl,
      organizer: organizer,
      isVirtual: isVirtual,
      deadlines: deadlines,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final created = await context.read<EventProvider>().createEvent(event);
      // Open the new event: its reminder plan is offered there.
      if (mounted) context.pushReplacement('/events/${created.id}');
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.urgent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Event'),
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
            Tab(text: 'Paste / AI Extract'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualForm(),
          _buildPasteForm(),
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
          _label('Event Title'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            autofocus: true,
            style: AppTextStyles.bodyLarge,
            decoration: const InputDecoration(hintText: 'Event name'),
          ),
          const SizedBox(height: 16),
          _label('Event Type'),
          const SizedBox(height: 8),
          _buildTypeSelector(),
          const SizedBox(height: 16),
          _label('Start Date & Time'),
          const SizedBox(height: 8),
          _buildDateTimeTile(
            value: _startAt,
            hint: 'Set start date & time',
            onTap: () => _pickDateTime(isStart: true),
            onClear: () => setState(() => _startAt = null),
          ),
          const SizedBox(height: 12),
          _label('End Date & Time (optional)'),
          const SizedBox(height: 8),
          _buildDateTimeTile(
            value: _endAt,
            hint: 'Set end date & time',
            onTap: () => _pickDateTime(isStart: false),
            onClear: () => setState(() => _endAt = null),
          ),
          const SizedBox(height: 12),
          _label('Registration Deadline (optional)'),
          const SizedBox(height: 8),
          _buildDateTimeTile(
            value: _registrationDeadline,
            hint: 'Set registration deadline',
            onTap: _pickRegistrationDeadline,
            onClear: () => setState(() => _registrationDeadline = null),
            icon: Icons.flag_outlined,
            color: AppColors.urgent,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Virtual Event', style: AppTextStyles.titleMedium),
              Switch(
                value: _isVirtual,
                onChanged: (v) => setState(() => _isVirtual = v),
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label('Location / URL'),
          const SizedBox(height: 8),
          TextField(
            controller: _isVirtual ? _urlController : _locationController,
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: _isVirtual ? 'Meeting link' : 'Venue or address',
            ),
          ),
          const SizedBox(height: 12),
          _label('Organizer (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _organizerController,
            style: AppTextStyles.bodyLarge,
            decoration: const InputDecoration(hintText: 'Who is organising it?'),
          ),
          const SizedBox(height: 12),
          _label('Description (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            style: AppTextStyles.bodyLarge,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Event details…'),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveManual,
              child: const Text('Add Event'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPasteForm() {
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
                    'Paste event text, a URL, or an email. AI will extract the event details.',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Paste event information'),
              TextButton.icon(
                onPressed: _isParsing ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste, size: 16),
                label: const Text('Paste & extract'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pasteController,
            style: AppTextStyles.bodyLarge,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Paste an invitation, message or announcement here',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isParsing ? null : _parseText,
              icon: _isParsing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent),
                    )
                  : const Icon(Icons.psychology_outlined),
              label: Text(_isParsing ? 'Extracting…' : 'Extract with AI'),
            ),
          ),
          if (_extracted != null) ...[
            const SizedBox(height: 20),
            AiSuggestionBanner(
              message: _extracted!.title,
              detail: _extracted!.startAt != null
                  ? '${_extracted!.startAt!.toLocal()}'
                  : null,
              confirmLabel: 'Create Event',
              dismissLabel: 'Edit Manually',
              onConfirm: _saveExtracted,
              onDismiss: () {
                // Populate manual form then switch tab
                _titleController.text = _extracted!.title;
                if (_extracted!.startAt != null) _startAt = _extracted!.startAt;
                if (_extracted!.endAt != null) _endAt = _extracted!.endAt;
                if (_extracted!.registrationDeadline != null) {
                  _registrationDeadline = _extracted!.registrationDeadline;
                }
                if (_extracted!.location != null) {
                  _locationController.text = _extracted!.location!;
                }
                if (_extracted!.eventUrl != null) {
                  _urlController.text = _extracted!.eventUrl!;
                }
                _eventType = _extracted!.eventType;
                _tabController.animateTo(0);
                setState(() => _extracted = null);
              },
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style:
            AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
      );

  Widget _buildTypeSelector() {
    const types = [
      (EventType.hackathon, 'Hackathon', Icons.code),
      (EventType.workshop, 'Workshop', Icons.build_outlined),
      (EventType.conference, 'Conference', Icons.groups_outlined),
      (EventType.webinar, 'Webinar', Icons.videocam_outlined),
      (EventType.meetup, 'Meetup', Icons.people_outline),
      (EventType.meeting, 'Meeting', Icons.calendar_today_outlined),
      (EventType.deadline, 'Deadline', Icons.flag_outlined),
      (EventType.custom, 'Custom', Icons.star_border),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((t) {
        final (type, label, icon) = t;
        final selected = _eventType == type;
        return GestureDetector(
          onTap: () => setState(() => _eventType = type),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? AppColors.accent : AppColors.cardBorder),
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
                    color:
                        selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateTimeTile({
    required DateTime? value,
    required String hint,
    required VoidCallback onTap,
    required VoidCallback onClear,
    IconData icon = Icons.calendar_today_outlined,
    Color color = AppColors.accent,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value == null ? hint : '${value.toLocal()}',
                style: value == null
                    ? AppTextStyles.bodyMedium
                    : AppTextStyles.bodyLarge,
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.clear,
                    size: 16, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart
        ? (_startAt ?? DateTime.now().add(const Duration(days: 1)))
        : (_endAt ?? (_startAt ?? DateTime.now()).add(const Duration(hours: 4)));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
        child: child!,
      ),
    );
    if (time == null) return;
    final dt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
      } else {
        _endAt = dt;
      }
    });
  }

  Future<void> _pickRegistrationDeadline() async {
    final initial = _registrationDeadline ??
        (_startAt != null
            ? _startAt!.subtract(const Duration(days: 3))
            : DateTime.now().add(const Duration(days: 7)));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _registrationDeadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
}
