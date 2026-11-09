import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/features/events/screens/event_create_screen.dart';
import 'package:personal_memory_os/features/events/widgets/extraction_review.dart';
import 'support/stub_services.dart';

final _register = DateTime(2026, 11, 5, 23, 59);

EventExtractionResult found({DateTime? start, bool withEvidence = true}) => EventExtractionResult(
      title: 'AWS Student Hackathon',
      eventType: EventType.hackathon,
      startAt: start,
      registrationDeadline: _register,
      registrationUrl: 'https://example.org/register',
      evidence: withEvidence ? {'registration_deadline': 'Register by 5 November 2026'} : const {},
      assumedTimes: const ['registration_deadline'],
    );

Widget review(EventExtractionResult r, {DateTime? picked, VoidCallback? onPick, VoidCallback? onCreate}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExtractionReview(
            result: r,
            pickedStart: picked,
            onPickStart: onPick ?? () {},
            onCreate: onCreate ?? () {},
            onEdit: () {},
          ),
        ),
      ),
    );

String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

class FakeAi extends StubAiService {
  final Future<EventExtractionResult> Function() extract;
  int calls = 0;

  FakeAi(this.extract);

  @override
  Future<EventExtractionResult> extractEventFromText(String text) {
    calls++;
    return extract();
  }
}

Future<EventProvider> openCreate(WidgetTester tester, FakeAi ai) async {
  final events = EventProvider(StubEventService());
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<AiService>.value(value: ai),
      ChangeNotifierProvider.value(value: events),
      ChangeNotifierProvider.value(value: AuthProvider(StubAuthService())),
    ],
    child: const MaterialApp(home: EventCreateScreen(initialText: 'AWS Student Hackathon, register by 5 November')),
  ));
  await tester.pumpAndSettle();
  return events;
}

void main() {
  group('buildReviewRows', () {
    test('a field the page did not state is missing, not filled in', () {
      final rows = {for (final r in buildReviewRows(found())) r.field: r};
      expect(rows['start_at']!.missing, isTrue);
      expect(rows['end_at']!.missing, isTrue);
      expect(rows['submission_deadline']!.missing, isTrue);
      expect(rows['registration_deadline']!.missing, isFalse);
    });

    test('evidence and assumed time attach only to values that exist', () {
      final rows = {for (final r in buildReviewRows(found())) r.field: r};
      expect(rows['registration_deadline']!.evidence, 'Register by 5 November 2026');
      expect(rows['registration_deadline']!.assumedTime, isTrue);
      expect(rows['end_at']!.evidence, isNull);
      final lonely = EventExtractionResult(
        title: 'x',
        eventType: EventType.custom,
        evidence: const {'end_at': 'quote for a value that is not there'},
        assumedTimes: const ['end_at'],
      );
      final end = buildReviewRows(lonely).firstWhere((r) => r.field == 'end_at');
      expect(end.evidence, isNull);
      expect(end.assumedTime, isFalse);
    });

    test('a start date the user picked is the one shown', () {
      final picked = DateTime(2026, 11, 20, 9);
      final start = buildReviewRows(found(), startAt: picked).firstWhere((r) => r.field == 'start_at');
      expect(start.missing, isFalse);
    });
  });

  group('ExtractionReview', () {
    testWidgets('shows what was found with its evidence, and what was not found', (tester) async {
      await tester.pumpWidget(review(found(start: DateTime(2026, 11, 20, 9))));
      expect(text(tester, 'value-title'), 'AWS Student Hackathon');
      expect(text(tester, 'evidence-registration_deadline'), contains('Register by 5 November 2026'));
      expect(find.byKey(const ValueKey('assumed-registration_deadline')), findsOneWidget);
      expect(text(tester, 'value-submission_deadline'), 'Not found on the page');
      expect(text(tester, 'value-registration_url'), 'https://example.org/register');
    });

    testWidgets('without a start date the user must choose one, and cannot create yet', (tester) async {
      var picks = 0, creates = 0;
      await tester.pumpWidget(review(found(), onPick: () => picks++, onCreate: () => creates++));
      expect(find.byKey(const ValueKey('needs-start')), findsOneWidget);
      expect(find.text('Create event'), findsNothing);
      await tester.tap(find.text('Choose start date'));
      expect(picks, 1);
      expect(creates, 0);
    });

    testWidgets('with a start date, or one the user picked, the event can be created', (tester) async {
      var creates = 0;
      await tester.pumpWidget(review(found(start: DateTime(2026, 11, 20, 9)), onCreate: () => creates++));
      await tester.tap(find.text('Create event'));
      expect(creates, 1);

      await tester.pumpWidget(review(found(), picked: DateTime(2026, 11, 20, 9)));
      expect(find.text('Create event'), findsOneWidget);
      expect(find.byKey(const ValueKey('needs-start')), findsNothing);
    });

    testWidgets('dates that could be read two ways are called out', (tester) async {
      final result = EventExtractionResult(title: 'x', eventType: EventType.custom, ambiguousDates: const ['04/05/2027']);
      await tester.pumpWidget(review(result));
      expect(text(tester, 'ambiguous-dates'), contains('04/05/2027'));
    });
  });

  group('the event form', () {
    testWidgets('a failed extraction explains itself with Retry, and creates no placeholder', (tester) async {
      var fail = true;
      final ai = FakeAi(() async => fail ? throw Exception('SocketException: Connection timed out') : found(start: DateTime(2026, 11, 20, 9)));
      final events = await openCreate(tester, ai);

      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('Review what was found'), findsNothing);
      expect(events.events, isEmpty, reason: 'no blank "Event" was created behind the scenes');

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Review what was found'), findsOneWidget);
      expect(find.textContaining("Can't reach the server"), findsNothing);
    });

    testWidgets('no start date: the form asks for one and does not save a made-up day', (tester) async {
      final ai = FakeAi(() async => found());
      final events = await openCreate(tester, ai);
      expect(find.byKey(const ValueKey('needs-start')), findsOneWidget);
      expect(events.events, isEmpty);

      await tester.ensureVisible(find.text('Choose start date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose start date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('needs-start')), findsOneWidget, reason: 'still no start date');
      expect(events.events, isEmpty);
    });
  });
}
