import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/features/events/screens/event_detail_screen.dart';
import 'support/stub_services.dart';

Event hackathon() {
  final now = DateTime.now();
  EventDeadline deadline(String id, DeadlineType type, String title, int days) => EventDeadline(
        id: id,
        eventId: 'e1',
        userId: 'u',
        title: title,
        deadlineType: type,
        deadlineAt: now.add(Duration(days: days)),
        createdAt: now,
      );
  return Event(
    id: 'e1',
    userId: 'u',
    title: 'AWS Hackathon',
    eventType: EventType.hackathon,
    startAt: now.add(const Duration(days: 30)),
    registrationUrl: 'https://example.org/register',
    deadlines: [
      deadline('d-reg', DeadlineType.registration, 'Register', 5),
      deadline('d-sub', DeadlineType.submission, 'Submit', 20),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> open(WidgetTester tester, StubEventService service) async {
  final events = EventProvider(service);
  // The stub simulates network delay with real timers, so set it up outside the fake clock.
  await tester.runAsync(() async {
    await service.createEvent(hackathon());
    await events.loadEvents();
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: events),
      ChangeNotifierProvider.value(value: ReminderProvider(StubReminderService())),
      ChangeNotifierProvider.value(value: CaptureProvider(StubCaptureService(), store: MemoryKeyValueStore())),
    ],
    child: const MaterialApp(home: EventDetailScreen(eventId: 'e1')),
  ));
  await tester.pump();
}

class FailingEvents extends StubEventService {
  @override
  Future<MilestoneChange> setRegistrationStatus(String eventId, RegistrationStatus status) async =>
      throw Exception('SocketException: Connection timed out');
}

String status() => (find.byKey(const ValueKey('registration-status')).evaluate().single.widget as Text).data!;

void main() {
  testWidgets('registration shows its status and both milestones are open', (tester) async {
    await open(tester, StubEventService());
    expect(find.text('Registration'), findsOneWidget);
    expect(status(), 'Not started');
    expect(find.byKey(const ValueKey('closed-d-reg')), findsNothing);
    expect(find.byKey(const ValueKey('closed-d-sub')), findsNothing);
  });

  testWidgets('choosing Registered closes only the registration milestone', (tester) async {
    await open(tester, StubEventService());
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered').last);
    await tester.pumpAndSettle();

    expect(status(), 'Registered', reason: 'the card now says so');
    expect(tester.widget<Text>(find.byKey(const ValueKey('closed-d-reg'))).data, 'Done');
    expect(find.byKey(const ValueKey('closed-d-sub')), findsNothing, reason: 'submission is still open');
    expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'the submission milestone still has its actions');
  });

  testWidgets('a milestone can be marked done from its menu', (tester) async {
    await open(tester, StubEventService());
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('closed-d-sub'))).data, 'Done');
    expect(find.byKey(const ValueKey('closed-d-reg')), findsNothing, reason: 'registration is still open');
    expect(status(), 'Not started', reason: 'registration status is unchanged');
  });

  testWidgets('a failed change says why in plain words and changes nothing', (tester) async {
    await open(tester, FailingEvents());
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered').last);
    await tester.pumpAndSettle();

    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(status(), 'Not started');
  });

  testWidgets('an event with no registration has no registration card', (tester) async {
    final service = StubEventService();
    final now = DateTime.now();
    final bare = Event(
      id: 'bare',
      userId: 'u',
      title: 'Meetup',
      eventType: EventType.meetup,
      startAt: now.add(const Duration(days: 3)),
      createdAt: now,
      updatedAt: now,
    );
    final events = EventProvider(service);
    await tester.runAsync(() async {
      await service.createEvent(bare);
      await events.loadEvents();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: events),
        ChangeNotifierProvider.value(value: ReminderProvider(StubReminderService())),
        ChangeNotifierProvider.value(value: CaptureProvider(StubCaptureService(), store: MemoryKeyValueStore())),
      ],
      child: const MaterialApp(home: EventDetailScreen(eventId: 'bare')),
    ));
    await tester.pump();
    expect(find.text('Registration'), findsNothing);
  });
}
