import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/services/api_mapper.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'support/stub_services.dart';

Event hackathon() => eventFromApi({
      'id': 'e1',
      'user_id': 'u1',
      'title': 'Hack',
      'event_type': 'hackathon',
      'start_at': '2031-03-01T10:00:00+00:00',
      'timezone': 'UTC',
      'status': 'upcoming',
      'deadlines': [
        for (final type in ['registration', 'submission'])
          {
            'id': 'd-$type',
            'event_id': 'e1',
            'user_id': 'u1',
            'title': type,
            'deadline_type': type,
            'deadline_at': '2031-02-01T10:00:00+00:00',
            'status': 'active',
            'created_at': '2031-01-01T00:00:00+00:00',
          },
      ],
      'created_at': '2031-01-01T00:00:00+00:00',
      'updated_at': '2031-01-01T00:00:00+00:00',
    });

class FailingEvents extends StubEventService {
  @override
  Future<MilestoneChange> setRegistrationStatus(String eventId, RegistrationStatus status) async =>
      throw Exception('SocketException: Connection timed out');
}

Future<(EventProvider, StubEventService)> setUpProvider([StubEventService? service]) async {
  final stub = service ?? StubEventService();
  await stub.createEvent(hackathon());
  final provider = EventProvider(stub);
  await provider.loadEvents();
  return (provider, stub);
}

EventDeadline deadline(EventProvider p, DeadlineType type) =>
    p.getEventById('e1')!.deadlines.firstWhere((d) => d.deadlineType == type);

void main() {
  test('a new event starts with registration not started and both milestones open', () async {
    final (provider, _) = await setUpProvider();
    final event = provider.getEventById('e1')!;
    expect(event.registrationStatus, RegistrationStatus.notStarted);
    expect(event.deadlines.every((d) => !d.isClosed), isTrue);
  });

  test('registering closes only the registration milestone', () async {
    final (provider, _) = await setUpProvider();
    await provider.setRegistrationStatus('e1', RegistrationStatus.registered);
    expect(provider.getEventById('e1')!.registrationStatus, RegistrationStatus.registered);
    expect(deadline(provider, DeadlineType.registration).status, 'completed');
    expect(deadline(provider, DeadlineType.submission).status, 'active');
  });

  test('skipping, not being eligible and expiring close registration in the right way', () async {
    for (final (status, closed) in [
      (RegistrationStatus.skipped, 'skipped'),
      (RegistrationStatus.notEligible, 'skipped'),
      (RegistrationStatus.expired, 'expired'),
    ]) {
      final (provider, _) = await setUpProvider();
      await provider.setRegistrationStatus('e1', status);
      expect(deadline(provider, DeadlineType.registration).status, closed, reason: status.name);
      expect(deadline(provider, DeadlineType.submission).status, 'active', reason: status.name);
    }
  });

  test('in-between states change the status but close nothing', () async {
    for (final status in [RegistrationStatus.planned, RegistrationStatus.inProgress, RegistrationStatus.waitlisted]) {
      final (provider, _) = await setUpProvider();
      await provider.setRegistrationStatus('e1', status);
      expect(provider.getEventById('e1')!.registrationStatus, status);
      expect(provider.getEventById('e1')!.deadlines.every((d) => !d.isClosed), isTrue, reason: status.name);
    }
  });

  test('completing or skipping one milestone leaves the other open', () async {
    final (provider, _) = await setUpProvider();
    await provider.completeMilestone('e1', 'd-submission');
    expect(deadline(provider, DeadlineType.submission).status, 'completed');
    expect(deadline(provider, DeadlineType.registration).status, 'active');
    await provider.skipMilestone('e1', 'd-registration');
    expect(deadline(provider, DeadlineType.registration).status, 'skipped');
  });

  test('an unknown milestone fails loudly and the error is kept for the screen', () async {
    final (provider, _) = await setUpProvider();
    await expectLater(provider.completeMilestone('e1', 'nope'), throwsA(isA<StateError>()));
    expect(provider.error, isNotNull);
  });

  test('a failed request leaves the event untouched and reports the failure', () async {
    final (provider, _) = await setUpProvider(FailingEvents());
    var notified = 0;
    provider.addListener(() => notified++);
    await expectLater(
      provider.setRegistrationStatus('e1', RegistrationStatus.registered),
      throwsA(isA<Exception>()),
    );
    expect(provider.getEventById('e1')!.registrationStatus, RegistrationStatus.notStarted);
    expect(provider.error, contains('SocketException'));
    expect(notified, greaterThan(0), reason: 'the screen is told so it can show the problem');
  });
}
