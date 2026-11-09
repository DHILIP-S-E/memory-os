import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/features/today/widgets/pending_registrations_card.dart';
import 'support/stub_services.dart';

final _now = DateTime.now();

EventDeadline deadline(String id, DeadlineType type, int days, {String status = 'active'}) => EventDeadline(
      id: id,
      eventId: 'e',
      userId: 'u',
      title: id,
      deadlineType: type,
      deadlineAt: _now.add(Duration(days: days)),
      status: status,
      createdAt: _now,
    );

Event event(
  String id, {
  RegistrationStatus status = RegistrationStatus.notStarted,
  List<EventDeadline> deadlines = const [],
  EventStatus eventStatus = EventStatus.upcoming,
}) =>
    Event(
      id: id,
      userId: 'u',
      title: 'Event $id',
      eventType: EventType.hackathon,
      startAt: _now.add(const Duration(days: 60)),
      registrationStatus: status,
      status: eventStatus,
      deadlines: deadlines,
      createdAt: _now,
      updatedAt: _now,
    );

Future<EventProvider> provider(List<Event> events) async {
  final service = StubEventService();
  for (final e in events) {
    await service.createEvent(e);
  }
  final p = EventProvider(service);
  await p.loadEvents();
  return p;
}

/// Holds only the events given, unlike the stub, which also ships demo events.
class OnlyThese extends StubEventService {
  final List<Event> mine;

  OnlyThese(this.mine);

  @override
  Future<List<Event>> fetchEvents() async => List.of(mine);
}

List<String> ids(EventProvider p) => p.pendingRegistrations.map((r) => r.event.id).where((id) => id.startsWith('t-')).toList();

void main() {
  group('pendingRegistrations', () {
    test('lists open registrations, soonest deadline first', () async {
      final p = await provider([
        event('t-late', deadlines: [deadline('d1', DeadlineType.registration, 20)]),
        event('t-soon', deadlines: [deadline('d2', DeadlineType.registration, 3)]),
        event('t-mid', status: RegistrationStatus.inProgress, deadlines: [deadline('d3', DeadlineType.registration, 9)]),
      ]);
      expect(ids(p), ['t-soon', 't-mid', 't-late']);
    });

    test('leaves out anything already settled or not chasing a registration', () async {
      final p = await provider([
        event('t-registered', status: RegistrationStatus.registered, deadlines: [deadline('a', DeadlineType.registration, 3)]),
        event('t-skipped', status: RegistrationStatus.skipped, deadlines: [deadline('b', DeadlineType.registration, 3)]),
        event('t-ineligible', status: RegistrationStatus.notEligible, deadlines: [deadline('c', DeadlineType.registration, 3)]),
        event('t-closed', deadlines: [deadline('d', DeadlineType.registration, 3, status: 'completed')]),
        event('t-submission-only', deadlines: [deadline('e', DeadlineType.submission, 3)]),
        event('t-no-deadlines'),
        event('t-cancelled', eventStatus: EventStatus.cancelled, deadlines: [deadline('f', DeadlineType.registration, 3)]),
        event('t-open', deadlines: [deadline('g', DeadlineType.registration, 3)]),
      ]);
      expect(ids(p), ['t-open']);
    });

    test('uses the earliest open registration deadline of an event', () async {
      final p = await provider([
        event('t-two', deadlines: [deadline('late', DeadlineType.registration, 12), deadline('early', DeadlineType.registration, 4)]),
      ]);
      expect(p.pendingRegistrations.singleWhere((r) => r.event.id == 't-two').deadline.id, 'early');
    });

    test('a deadline in the past is marked overdue but still listed', () async {
      final p = await provider([event('t-past', deadlines: [deadline('d', DeadlineType.registration, -2)])]);
      expect(p.pendingRegistrations.singleWhere((r) => r.event.id == 't-past').overdue, isTrue);
    });

    test('registering removes the event from the list', () async {
      final p = await provider([event('t-x', deadlines: [deadline('d', DeadlineType.registration, 3)])]);
      expect(ids(p), ['t-x']);
      await p.setRegistrationStatus('t-x', RegistrationStatus.registered);
      expect(ids(p), isEmpty);
    });
  });

  group('PendingRegistrationsCard', () {
    Future<void> pump(WidgetTester tester, EventProvider events) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => Scaffold(body: SingleChildScrollView(child: PendingRegistrationsCard()))),
        GoRoute(path: '/events/:id', builder: (_, state) => Scaffold(body: Text('detail ${state.pathParameters['id']}'))),
      ]);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: events, child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
    }

    Future<EventProvider> load(WidgetTester tester, List<Event> events) async {
      final p = EventProvider(OnlyThese(events));
      await tester.runAsync(p.loadEvents);
      return p;
    }

    testWidgets('shows nothing when there is nothing to finish', (tester) async {
      await pump(tester, await load(tester, []));
      expect(find.textContaining('REGISTRATION'), findsNothing);
    });

    testWidgets('shows the event, its deadline and its status', (tester) async {
      await pump(tester, await load(tester, [event('t-a', deadlines: [deadline('d', DeadlineType.registration, 5)])]));
      expect(find.text('REGISTRATION TO FINISH'), findsOneWidget);
      expect(find.text('Event t-a'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('when-t-a'))).data, startsWith('Register by '));
      expect(find.text('Not started'), findsOneWidget);
    });

    testWidgets('says plainly when the deadline has passed', (tester) async {
      await pump(tester, await load(tester, [event('t-a', deadlines: [deadline('d', DeadlineType.registration, -1)])]));
      expect(tester.widget<Text>(find.byKey(const ValueKey('when-t-a'))).data, 'The registration deadline has passed');
    });

    testWidgets('shows the first three and counts the rest', (tester) async {
      final five = [
        for (var i = 1; i <= 5; i++) event('t-$i', deadlines: [deadline('d$i', DeadlineType.registration, i)]),
      ];
      await pump(tester, await load(tester, five));
      expect(find.text('REGISTRATIONS TO FINISH'), findsOneWidget);
      expect(find.byType(InkWell), findsNWidgets(3));
      expect(find.text('and 2 more'), findsOneWidget);
    });

    testWidgets('tapping an item opens that event', (tester) async {
      await pump(tester, await load(tester, [event('t-a', deadlines: [deadline('d', DeadlineType.registration, 5)])]));
      await tester.tap(find.byKey(const ValueKey('pending-t-a')));
      await tester.pumpAndSettle();
      expect(find.text('detail t-a'), findsOneWidget);
    });
  });
}
