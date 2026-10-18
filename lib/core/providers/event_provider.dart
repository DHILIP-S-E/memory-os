import 'package:flutter/foundation.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/services/event_service.dart';

/// An event whose registration is still open, with the deadline to register by.
class PendingRegistration {
  final Event event;
  final EventDeadline deadline;

  const PendingRegistration(this.event, this.deadline);

  bool get overdue => deadline.deadlineAt.isBefore(DateTime.now());
}

class EventProvider extends ChangeNotifier {
  final EventService _service;

  EventProvider(this._service);

  List<Event> _events = [];
  bool _isLoading = false;
  String? _error;

  List<Event> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Registrations still to finish (not started, planned or in progress, with an open registration
  /// deadline), soonest deadline first. Once registered, skipped, not eligible or expired, an event is
  /// no longer chased.
  List<PendingRegistration> get pendingRegistrations {
    const open = {RegistrationStatus.notStarted, RegistrationStatus.planned, RegistrationStatus.inProgress};
    final out = <PendingRegistration>[];
    for (final event in _events) {
      if (!open.contains(event.registrationStatus) || event.status == EventStatus.cancelled) continue;
      final deadlines = event.deadlines
          .where((d) => d.deadlineType == DeadlineType.registration && !d.isClosed)
          .toList()
        ..sort((a, b) => a.deadlineAt.compareTo(b.deadlineAt));
      if (deadlines.isNotEmpty) out.add(PendingRegistration(event, deadlines.first));
    }
    return out..sort((a, b) => a.deadline.deadlineAt.compareTo(b.deadline.deadlineAt));
  }

  List<Event> get todayEvents {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return _events
        .where((e) =>
            e.startAt.isAfter(todayStart) && e.startAt.isBefore(todayEnd))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  List<Event> get upcomingEvents {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return _events
        .where((e) =>
            e.startAt.isAfter(tomorrow) &&
            e.status != EventStatus.cancelled &&
            e.status != EventStatus.completed)
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  List<Event> get activeEvents {
    final now = DateTime.now();
    return _events
        .where((e) =>
            e.status == EventStatus.active ||
            (e.startAt.isBefore(now) &&
                (e.endAt == null || e.endAt!.isAfter(now))))
        .toList();
  }

  /// Applies an action that closes a milestone, swaps in the event the server returns, and
  /// gives back how many reminders were stopped. Failures are recorded and rethrown so the
  /// screen can say what went wrong.
  Future<int> _apply(Future<MilestoneChange> Function() action) async {
    try {
      final change = await action();
      final i = _events.indexWhere((e) => e.id == change.event.id);
      if (i != -1) _events[i] = change.event;
      _error = null;
      notifyListeners();
      return change.stoppedReminders;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<int> setRegistrationStatus(String eventId, RegistrationStatus status) =>
      _apply(() => _service.setRegistrationStatus(eventId, status));

  Future<int> completeMilestone(String eventId, String deadlineId) =>
      _apply(() => _service.completeMilestone(eventId, deadlineId));

  Future<int> skipMilestone(String eventId, String deadlineId) =>
      _apply(() => _service.skipMilestone(eventId, deadlineId));

  Future<List<PolicyReminder>> previewReminderPolicy(String eventId, ReminderPolicyChoice choice) =>
      _service.previewReminderPolicy(eventId, choice);

  Future<int> applyReminderPolicy(String eventId, ReminderPolicyChoice choice) =>
      _service.applyReminderPolicy(eventId, choice);

  Future<void> loadEvents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _events = await _service.fetchEvents();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Event> createEvent(Event event) async {
    try {
      final created = await _service.createEvent(event);
      _events.add(created);
      notifyListeners();
      return created;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateEvent(Event event) async {
    try {
      final updated = await _service.updateEvent(event);
      final index = _events.indexWhere((e) => e.id == event.id);
      if (index != -1) {
        _events[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteEvent(String id) async {
    try {
      await _service.deleteEvent(id);
      _events.removeWhere((e) => e.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Event? getEventById(String id) {
    try {
      return _events.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }
}
