import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'package:personal_memory_os/core/services/reminder_service.dart';
import 'package:personal_memory_os/features/events/widgets/reminder_plan_section.dart';

Event hackathon({bool withRegistration = true, RegistrationStatus status = RegistrationStatus.notStarted}) {
  final now = DateTime.now();
  return Event(
    id: 'e1',
    userId: 'u',
    title: 'AWS Hackathon',
    eventType: EventType.hackathon,
    startAt: now.add(const Duration(days: 20)),
    registrationStatus: status,
    deadlines: [
      if (withRegistration)
        EventDeadline(
          id: 'd1', eventId: 'e1', userId: 'u', title: 'Register', deadlineType: DeadlineType.registration,
          deadlineAt: now.add(const Duration(days: 8)), createdAt: now,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

class FakePolicy extends StubEventService {
  final previews = <ReminderPolicyChoice>[];
  final applied = <ReminderPolicyChoice>[];
  List<PolicyReminder> result = [
    PolicyReminder(title: 'Register due in 3d', at: DateTime(2031, 1, 1, 9), isDeadline: true),
    PolicyReminder(title: 'AWS Hackathon starts in 1d', at: DateTime(2031, 1, 5, 9)),
  ];
  Object? applyError;

  @override
  Future<List<PolicyReminder>> previewReminderPolicy(String eventId, ReminderPolicyChoice choice) async {
    previews.add(choice);
    return result;
  }

  @override
  Future<int> applyReminderPolicy(String eventId, ReminderPolicyChoice choice) async {
    if (applyError != null) throw applyError!;
    applied.add(choice);
    return result.length;
  }
}

class ExistingReminders extends StubReminderService {
  final List<Reminder> items;

  ExistingReminders(this.items);

  @override
  Future<List<Reminder>> fetchReminders() async => items;
}

Future<void> pump(WidgetTester tester, Event event, FakePolicy policy, {ReminderProvider? reminders}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: EventProvider(policy)),
      ChangeNotifierProvider.value(value: reminders ?? ReminderProvider(ExistingReminders(const []))),
    ],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReminderPlanSection(event: event)))),
  ));
  await tester.pumpAndSettle();
}

bool selected(WidgetTester tester, String step) => tester.widget<FilterChip>(find.byKey(ValueKey('step-$step'))).selected;

void main() {
  testWidgets('shows the server preview with the default cadence', (tester) async {
    final policy = FakePolicy();
    await pump(tester, hackathon(), policy);
    expect(find.textContaining('Register due in 3d'), findsOneWidget);
    expect(['3d', '1d', '3h'].every((s) => selected(tester, s)), isTrue);
    expect(selected(tester, '7d'), isFalse);
    expect(find.text('Create 2 reminders'), findsOneWidget);
    expect(policy.previews.single, const ReminderPolicyChoice());
  });

  testWidgets('changing the cadence asks the server again', (tester) async {
    final policy = FakePolicy();
    await pump(tester, hackathon(), policy);
    await tester.tap(find.byKey(const ValueKey('step-7d')));
    await tester.pumpAndSettle();
    expect(policy.previews.last.cadence, ['7d', '3d', '1d', '3h']);
    expect(selected(tester, '7d'), isTrue);
  });

  testWidgets('the last step cannot be turned off', (tester) async {
    final policy = FakePolicy();
    await pump(tester, hackathon(), policy);
    for (final step in ['3d', '1d', '3h']) {
      await tester.tap(find.byKey(ValueKey('step-$step')));
      await tester.pumpAndSettle();
    }
    expect(selected(tester, '3h'), isTrue, reason: 'at least one reminder before each deadline');
  });

  testWidgets('daily until registered is offered for an open registration and sent with the plan', (tester) async {
    final policy = FakePolicy();
    await pump(tester, hackathon(), policy);
    await tester.tap(find.byKey(const ValueKey('daily-until-registered')));
    await tester.pumpAndSettle();
    expect(policy.previews.last.dailyUntilRegistered, isTrue);
    await tester.tap(find.byKey(const ValueKey('apply-plan')));
    await tester.pumpAndSettle();
    expect(policy.applied.single.dailyUntilRegistered, isTrue);
    expect(find.text('2 reminders scheduled'), findsOneWidget);
  });

  testWidgets('no daily option once registered, or without a registration deadline', (tester) async {
    await pump(tester, hackathon(status: RegistrationStatus.registered), FakePolicy());
    expect(find.byKey(const ValueKey('daily-until-registered')), findsNothing);
    await pump(tester, hackathon(withRegistration: false), FakePolicy());
    expect(find.byKey(const ValueKey('daily-until-registered')), findsNothing);
  });

  testWidgets('a failed apply is explained and never claims anything was scheduled', (tester) async {
    final policy = FakePolicy()..applyError = Exception('SocketException: Connection timed out');
    await pump(tester, hackathon(), policy);
    await tester.tap(find.byKey(const ValueKey('apply-plan')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.textContaining('scheduled'), findsNothing);
  });

  testWidgets('hidden once the plan exists', (tester) async {
    final now = DateTime.now();
    final existing = ReminderProvider(ExistingReminders([
      Reminder(id: 'r1', userId: 'u', title: 'x', reminderType: ReminderType.deadline, source: ReminderSource.eventPolicy,
          contextId: 'e1', createdAt: now, updatedAt: now),
    ]));
    await tester.runAsync(existing.loadReminders);
    await pump(tester, hackathon(), FakePolicy(), reminders: existing);
    expect(find.text('REMINDER PLAN'), findsNothing);
  });

  testWidgets('hidden when there is nothing left to remind about', (tester) async {
    await pump(tester, hackathon(), FakePolicy()..result = []);
    expect(find.text('REMINDER PLAN'), findsNothing);
  });

  test('alreadyApplied only counts this event\'s policy reminders', () {
    final now = DateTime.now();
    Reminder r(ReminderSource source, String? ctx) => Reminder(
        id: '$source$ctx', userId: 'u', title: 't', reminderType: ReminderType.time, source: source, contextId: ctx,
        createdAt: now, updatedAt: now);
    final event = hackathon();
    expect(ReminderPlanSection.alreadyApplied(event, [r(ReminderSource.manual, 'e1')]), isFalse);
    expect(ReminderPlanSection.alreadyApplied(event, [r(ReminderSource.eventPolicy, 'other')]), isFalse);
    expect(ReminderPlanSection.alreadyApplied(event, [r(ReminderSource.eventPolicy, 'e1')]), isTrue);
  });
}
