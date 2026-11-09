import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/features/capture/widgets/action_suggestions_section.dart';
import 'support/stub_services.dart';

class FakeCaptures extends StubCaptureService {
  final List<Capture> items;
  FakeCaptures(this.items);

  @override
  Future<List<Capture>> fetchCaptures() async => items;
}

Capture voiceNote(DateTime? due) => Capture(
      id: 'c1',
      userId: 'u',
      eventId: 'e1',
      type: CaptureType.voice,
      processingStatus: CaptureProcessingStatus.processed,
      aiResult: CaptureAiResult(
        summary: 'Talk about Bedrock',
        actions: [ExtractedAction(title: 'Submit the prototype', dueAt: due)],
      ),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

void main() {
  group('reminderTimeFor', () {
    final now = DateTime(2026, 10, 1, 12);
    test('a bare future date becomes 09:00 that day', () {
      expect(reminderTimeFor(DateTime(2026, 10, 20), now), DateTime(2026, 10, 20, 9));
    });
    test('a dated time is kept as is', () {
      expect(reminderTimeFor(DateTime(2026, 10, 20, 15, 30), now), DateTime(2026, 10, 20, 15, 30));
    });
    test('past or missing dates need the user to choose', () {
      expect(reminderTimeFor(DateTime(2026, 9, 1), now), isNull);
      expect(reminderTimeFor(null, now), isNull);
      expect(reminderTimeFor(DateTime(2026, 10, 1), now), isNull); // 09:00 today already passed
    });
  });

  testWidgets('confirming creates a deadline reminder and removes the suggestion',
      (tester) async {
    final due = DateTime.now().add(const Duration(days: 10));
    final captures = CaptureProvider(FakeCaptures([voiceNote(DateTime(due.year, due.month, due.day))]),
        store: MemoryKeyValueStore());
    final reminders = ReminderProvider(StubReminderService());
    final auth = AuthProvider(StubAuthService());
    await captures.loadCaptures();
    final before = reminders.reminders.length;

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: captures),
        ChangeNotifierProvider.value(value: reminders),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ActionSuggestionsSection())),
      ),
    ));

    expect(find.text('You mentioned a deadline — create reminder?'), findsOneWidget);
    expect(find.textContaining('Submit the prototype'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(reminders.reminders.length, before + 1);
    final created = reminders.reminders.last;
    expect(created.title, 'Submit the prototype');
    expect(created.reminderType, ReminderType.deadline);
    expect(created.source, ReminderSource.aiExtracted);
    expect(created.offsets.map((o) => o.offset), ['-1d', '-3h']);
    expect(find.text('You mentioned a deadline — create reminder?'), findsNothing);
  });

  testWidgets('ignoring removes the suggestion without creating anything',
      (tester) async {
    final captures = CaptureProvider(FakeCaptures([voiceNote(DateTime.now().add(const Duration(days: 3)))]),
        store: MemoryKeyValueStore());
    final reminders = ReminderProvider(StubReminderService());
    await captures.loadCaptures();
    final before = reminders.reminders.length;

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: captures),
        ChangeNotifierProvider.value(value: reminders),
        ChangeNotifierProvider.value(value: AuthProvider(StubAuthService())),
      ],
      child: const MaterialApp(home: Scaffold(body: ActionSuggestionsSection())),
    ));
    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    expect(reminders.reminders.length, before);
    expect(captures.pendingActions(), isEmpty);
  });

  test('a dismissed suggestion stays dismissed after a restart', () async {
    final store = MemoryKeyValueStore();
    final first = CaptureProvider(FakeCaptures([voiceNote(null)]), store: store);
    await first.loadCaptures();
    await first.markActionHandled(first.pendingActions().single);

    final second = CaptureProvider(FakeCaptures([voiceNote(null)]), store: store);
    await second.loadCaptures();
    expect(second.pendingActions(), isEmpty);
  });
}
