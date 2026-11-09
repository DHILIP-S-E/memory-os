import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'support/stub_services.dart';

class ScriptedCaptures extends StubCaptureService {
  final List<CaptureProcessingStatus> script;
  int calls = 0;
  ScriptedCaptures(this.script);

  @override
  Future<List<Capture>> fetchCaptures() async {
    final status = script[calls < script.length ? calls : script.length - 1];
    calls++;
    return [
      Capture(
        id: 'c1',
        userId: 'u',
        type: CaptureType.photo,
        processingStatus: status,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ];
  }
}

void main() {
  test('polls until the capture is processed, then stops by itself', () {
    fakeAsync((async) {
      final service = ScriptedCaptures([
        CaptureProcessingStatus.queued,
        CaptureProcessingStatus.processing,
        CaptureProcessingStatus.processed,
      ]);
      final provider =
          CaptureProvider(service, pollInterval: const Duration(seconds: 5));

      provider.loadCaptures();
      async.flushMicrotasks();
      expect(provider.hasInFlight, isTrue);
      expect(service.calls, 1);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(service.calls, 2);
      expect(provider.hasInFlight, isTrue);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(provider.captures.single.processingStatus,
          CaptureProcessingStatus.processed);
      expect(provider.hasInFlight, isFalse);

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(service.calls, 3, reason: 'no more polling once nothing is in flight');
      provider.dispose();
    });
  });

  test('never polls when disabled or when everything is processed', () {
    fakeAsync((async) {
      final service = ScriptedCaptures([CaptureProcessingStatus.processed]);
      final provider =
          CaptureProvider(service, pollInterval: const Duration(seconds: 5));
      provider.loadCaptures();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(service.calls, 1);

      final off = ScriptedCaptures([CaptureProcessingStatus.queued]);
      final disabled = CaptureProvider(off);
      disabled.loadCaptures();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(off.calls, 1);
      provider.dispose();
      disabled.dispose();
    });
  });
}
