import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/shared/widgets/capture_card.dart';
import 'package:personal_memory_os/shared/widgets/retry_capture.dart';

final _now = DateTime(2026, 10, 18, 9);

Capture failedNote() => Capture(
      id: 'c1',
      userId: 'u',
      type: CaptureType.note,
      content: 'Call the vendor',
      processingStatus: CaptureProcessingStatus.failed,
      aiResult: const CaptureAiResult(summary: 'Could not analyse this capture: the AI service is not available right now.'),
      createdAt: _now,
      updatedAt: _now,
    );

class OneCapture extends StubCaptureService {
  Capture current;
  Object? retryError;
  int retries = 0;

  OneCapture(this.current);

  @override
  Future<List<Capture>> fetchCaptures() async => [current];

  @override
  Future<Capture> retryProcessing(String id) async {
    if (retryError != null) throw retryError!;
    retries++;
    return current = current.copyWith(processingStatus: CaptureProcessingStatus.queued);
  }
}

Future<CaptureProvider> pump(WidgetTester tester, OneCapture service) async {
  final provider = CaptureProvider(service, store: MemoryKeyValueStore());
  await tester.runAsync(provider.loadCaptures);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer<CaptureProvider>(
          builder: (context, p, _) => CaptureCard(
            capture: p.captures.single,
            onRetry: () => retryCapture(context, p.captures.single.id),
          ),
        ),
      ),
    ),
  ));
  return provider;
}

void main() {
  testWidgets('a capture that could not be read says so, with the reason and a way to try again', (tester) async {
    await pump(tester, OneCapture(failedNote()));
    expect(find.byKey(const ValueKey('failed-badge')), findsOneWidget);
    expect(find.textContaining('the AI service is not available'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-capture')), findsOneWidget);
  });

  testWidgets('Try again asks the server to read it again and shows it is waiting', (tester) async {
    final service = OneCapture(failedNote());
    final provider = await pump(tester, service);
    await tester.tap(find.byKey(const ValueKey('retry-capture')));
    await tester.pump();
    expect(service.retries, 1);
    expect(provider.captures.single.processingStatus, CaptureProcessingStatus.queued);
    expect(find.byKey(const ValueKey('retry-capture')), findsNothing, reason: 'not offered while it is waiting');
    expect(find.text('Reading it again…'), findsOneWidget);
    provider.dispose(); // stops the polling timer started for the waiting capture
  });

  testWidgets('a failed retry request is explained in plain words', (tester) async {
    final service = OneCapture(failedNote())..retryError = Exception('SocketException: Connection timed out');
    await pump(tester, service);
    await tester.tap(find.byKey(const ValueKey('retry-capture')));
    await tester.pump();
    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.byKey(const ValueKey('failed-badge')), findsOneWidget, reason: 'still shown as failed');
  });

  testWidgets('a processed capture offers no retry', (tester) async {
    await pump(tester, OneCapture(failedNote().copyWith(processingStatus: CaptureProcessingStatus.processed)));
    expect(find.byKey(const ValueKey('retry-capture')), findsNothing);
    expect(find.byKey(const ValueKey('failed-badge')), findsNothing);
  });
}
