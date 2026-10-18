import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';
import 'package:personal_memory_os/core/services/reminder_service.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';

/// True when [error] means "we could not reach the server" (offline, timeout,
/// or a 5xx), as opposed to the server rejecting the request.
bool isOfflineError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    (error is ApiException && error.statusCode >= 500);

/// Wraps a [ReminderService] with an offline cache and a queue for creates
/// (spec R6.1, R6.2). Reads fall back to the last cached list; a reminder
/// created offline is stored locally as LOCAL_ONLY and synced on reconnect.
class OfflineReminderService implements ReminderService {
  static const cacheKey = 'cache_reminders_v1';

  final ReminderService _remote;
  final SyncQueue _queue;
  final KeyValueStore _store;

  OfflineReminderService(this._remote, this._queue, this._store);

  @override
  Future<List<Reminder>> fetchReminders() async {
    try {
      final reminders = await _remote.fetchReminders();
      await _store.write(
        cacheKey,
        jsonEncode(reminders.map((r) => r.toJson()).toList()),
      );
      return [...reminders, ...await _pendingLocal()];
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return [...await _cached(), ...await _pendingLocal()];
    }
  }

  Future<List<Reminder>> _cached() async {
    final raw = await _store.read(cacheKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((j) => Reminder.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Reminder>> _pendingLocal() async => (await _queue.pending())
      .where((o) => o.type == SyncOpType.createReminder)
      .map((o) => Reminder.fromJson(o.payload))
      .toList();

  @override
  Future<Reminder> createReminder(Reminder reminder) async {
    try {
      return await _remote.createReminder(reminder);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final local = reminder.copyWith(syncStatus: 'LOCAL_ONLY');
      await _queue.enqueue(
        id: local.id,
        type: SyncOpType.createReminder,
        payload: local.toJson(),
      );
      return local;
    }
  }

  @override
  Future<Reminder> updateReminder(Reminder reminder) =>
      _remote.updateReminder(reminder);

  @override
  Future<void> deleteReminder(String id) => _remote.deleteReminder(id);

  @override
  Future<void> updateReminderStatus(String id, ReminderStatus status) =>
      _remote.updateReminderStatus(id, status);

  @override
  Future<void> snoozeReminder(String id, DateTime newTime) =>
      _remote.snoozeReminder(id, newTime);
}

/// Wraps a [CaptureService] so captures made offline are queued and uploaded
/// when connectivity returns (spec R3.9, R6.3). Capture-first: the user is
/// never blocked by the network.
class OfflineCaptureService implements CaptureService {
  final CaptureService _remote;
  final SyncQueue _queue;

  OfflineCaptureService(this._remote, this._queue);

  @override
  Future<List<Capture>> fetchCaptures() async {
    try {
      return await _remote.fetchCaptures();
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return [];
    }
  }

  @override
  Future<Capture> uploadCapture({
    required File file,
    required CaptureType type,
    String? eventId,
  }) async {
    try {
      return await _remote.uploadCapture(
          file: file, type: type, eventId: eventId);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return _queueLocal(
        SyncOpType.uploadCapture,
        type,
        eventId,
        {'path': file.path},
      );
    }
  }

  @override
  Future<Capture> saveTextNote({required String text, String? eventId}) async {
    try {
      return await _remote.saveTextNote(text: text, eventId: eventId);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return _queueLocal(
        SyncOpType.createNote,
        CaptureType.note,
        eventId,
        {'text': text},
        content: text,
      );
    }
  }

  @override
  Future<Capture> saveLink({required String url, String? eventId}) async {
    try {
      return await _remote.saveLink(url: url, eventId: eventId);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return _queueLocal(
        SyncOpType.createLink,
        CaptureType.link,
        eventId,
        {'url': url},
        content: url,
      );
    }
  }

  @override
  Future<void> deleteCapture(String id) => _remote.deleteCapture(id);

  @override
  Future<Capture> retryProcessing(String id) => _remote.retryProcessing(id);

  Future<Capture> _queueLocal(
    SyncOpType op,
    CaptureType type,
    String? eventId,
    Map<String, dynamic> data, {
    String? content,
  }) async {
    final id = const Uuid().v4();
    await _queue.enqueue(
      id: id,
      type: op,
      payload: {...data, 'captureType': type.name, 'eventId': eventId},
    );
    final now = DateTime.now();
    return Capture(
      id: id,
      userId: 'local',
      eventId: eventId,
      type: type,
      content: content,
      processingStatus: CaptureProcessingStatus.uploaded,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Replays queued operations against the real services.
class SyncExecutor {
  final ReminderService _reminders;
  final CaptureService _captures;

  SyncExecutor(this._reminders, this._captures);

  Future<void> call(SyncOperation op) async {
    try {
      switch (op.type) {
        case SyncOpType.createReminder:
          await _reminders.createReminder(Reminder.fromJson(op.payload));
        case SyncOpType.uploadCapture:
          await _captures.uploadCapture(
            file: File(op.payload['path'] as String),
            type: CaptureType.values.byName(op.payload['captureType']),
            eventId: op.payload['eventId'] as String?,
          );
        case SyncOpType.createNote:
          await _captures.saveTextNote(
            text: op.payload['text'] as String,
            eventId: op.payload['eventId'] as String?,
          );
        case SyncOpType.createLink:
          await _captures.saveLink(
            url: op.payload['url'] as String,
            eventId: op.payload['eventId'] as String?,
          );
      }
    } catch (e) {
      if (isOfflineError(e)) throw TransientSyncException(e.toString());
      if (e is ApiException && e.statusCode == 409) {
        throw SyncConflictException(e.message);
      }
      rethrow;
    }
  }
}
