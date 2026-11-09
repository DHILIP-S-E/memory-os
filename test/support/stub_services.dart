export 'stub_reminder_service.dart';
export 'stub_capture_service.dart';
export 'stub_event_service.dart';
export 'stub_memory_service.dart';
export 'stub_account_service.dart';
export 'stub_device_service.dart';
export 'stub_auth_service.dart';
export 'stub_ai_service.dart';

import 'package:personal_memory_os/core/app_dependencies.dart';
import 'stub_account_service.dart';
import 'stub_ai_service.dart';
import 'stub_auth_service.dart';
import 'stub_capture_service.dart';
import 'stub_event_service.dart';
import 'stub_memory_service.dart';
import 'stub_reminder_service.dart';

/// A full set of in-memory services for booting the app in tests.
AppDependencies stubDeps() => AppDependencies(
      authService: StubAuthService(),
      aiService: StubAiService(),
      accountService: StubAccountService(),
      reminders: StubReminderService(),
      captures: StubCaptureService(),
      events: StubEventService(),
      memory: StubMemoryService(),
    );
