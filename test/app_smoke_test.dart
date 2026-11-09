import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/main.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'support/stub_services.dart';

void main() {
  testWidgets('stub mode boots and gates the app behind sign-in',
      (tester) async {
    await tester.pumpWidget(PersonalMemoryOsApp(deps: stubDeps(), store: MemoryKeyValueStore()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
