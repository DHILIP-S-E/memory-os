import 'package:personal_memory_os/core/services/account_service.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'package:personal_memory_os/core/services/memory_service.dart';
import 'package:personal_memory_os/core/services/reminder_service.dart';

/// The services the app talks to. The shipped app builds the real ones; tests pass their own.
class AppDependencies {
  final AuthService authService;
  final AiService aiService;
  final AccountService accountService;
  final ReminderService reminders;
  final CaptureService captures;
  final EventService events;
  final MemoryService memory;

  const AppDependencies({
    required this.authService,
    required this.aiService,
    required this.accountService,
    required this.reminders,
    required this.captures,
    required this.events,
    required this.memory,
  });
}
