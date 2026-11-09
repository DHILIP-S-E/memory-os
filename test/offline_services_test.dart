import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/sync/offline_services.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'support/stub_services.dart';

class FlakyReminderService extends StubReminderService {
  Object? failWith;

  @override
  Future<List<Reminder>> fetchReminders() async {
    if (failWith != null) throw failWith!;
    return super.fetchReminders();
  }

  @override
  Future<Reminder> createReminder(Reminder reminder) async {
    if (failWith != null) throw failWith!;
    return super.createReminder(reminder);
  }
}

Reminder _reminder(String id) => Reminder(
      id: id,
      userId: 'u',
      title: 'Offline $id',
      reminderType: ReminderType.time,
      scheduledAt: DateTime.now().add(const Duration(days: 1)),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

void main() {
  late FlakyReminderService remote;
  late SyncQueue queue;
  late MemoryKeyValueStore store;
  late OfflineReminderService service;

  setUp(() {
    remote = FlakyReminderService();
    store = MemoryKeyValueStore();
    queue = SyncQueue(store);
    service = OfflineReminderService(remote, queue, store);
  });

  test('reminder created offline is LOCAL_ONLY, queued, and visible in the list',
      () async {
    remote.failWith = const SocketException('no network');
    final local = await service.createReminder(_reminder('r-offline'));
    expect(local.syncStatus, 'LOCAL_ONLY');
    expect((await queue.pending()).single.id, 'r-offline');
    expect((await service.fetchReminders()).map((r) => r.id), contains('r-offline'));
  });

  test('reconnect: queued reminder syncs once and leaves the queue', () async {
    remote.failWith = const SocketException('no network');
    await service.createReminder(_reminder('r1'));
    remote.failWith = null;
    final executor = SyncExecutor(remote, StubCaptureService());
    final result = await queue.flush(executor.call);
    expect(result.synced, 1);
    expect(await queue.all(), isEmpty);
    final synced = (await remote.fetchReminders()).where((r) => r.id == 'r1');
    expect(synced.length, 1);
    expect(synced.single.syncStatus, 'SYNCED');
  });

  test('offline reads fall back to the last cached list', () async {
    final online = await service.fetchReminders();
    expect(online, isNotEmpty);
    remote.failWith = TimeoutException('slow');
    final cached = await service.fetchReminders();
    expect(cached.map((r) => r.id).toSet(), online.map((r) => r.id).toSet());
  });

  test('server rejection (4xx) is NOT queued — it surfaces to the user', () async {
    remote.failWith = const ApiException(422, 'bad');
    expect(() => service.createReminder(_reminder('bad')), throwsA(isA<ApiException>()));
    expect(await queue.all(), isEmpty);
  });

  test('5xx and timeouts count as offline; 4xx does not', () {
    expect(isOfflineError(const ApiException(503, 'x')), isTrue);
    expect(isOfflineError(const ApiException(404, 'x')), isFalse);
    expect(isOfflineError(const SocketException('x')), isTrue);
  });

  test('offline text note is queued and returned immediately (capture-first)',
      () async {
    final captures = OfflineCaptureService(_OfflineCaptures(), queue);
    final c = await captures.saveTextNote(text: 'idea', eventId: 'e1');
    expect(c.type, CaptureType.note);
    expect(c.content, 'idea');
    final op = (await queue.pending()).single;
    expect(op.type, SyncOpType.createNote);
    expect(op.payload['eventId'], 'e1');
  });
}

class _OfflineCaptures extends StubCaptureService {
  @override
  Future<Capture> saveTextNote({required String text, String? eventId}) =>
      throw const SocketException('offline');
}
