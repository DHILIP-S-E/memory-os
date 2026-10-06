# Flutter Patterns — Personal Memory OS

## Project Structure

```
lib/
  core/
    providers/        ChangeNotifier providers (one per domain)
    services/         Abstract service interfaces + stub/real implementations
    models/           Data models — singular nouns (reminder.dart, event.dart)
    theme/            AppColors, AppTextStyles — only source of colors/styles
  features/
    today/
      screens/        today_screen.dart
      widgets/        now_card.dart, reminder_card.dart, ...
    reminders/
      screens/        reminders_screen.dart, reminder_create_screen.dart
      widgets/        reminder_card.dart, filter_bar.dart, ...
    events/
      screens/        event_create_screen.dart, event_detail_screen.dart
      widgets/
    capture/
      screens/        capture_screen.dart
      widgets/
    memory/
      screens/        memory_screen.dart, memory_search_screen.dart, ai_chat_screen.dart
      widgets/
    auth/
      screens/        auth_screen.dart
      widgets/
    settings/
      screens/        settings_screen.dart
      widgets/
  shared/
    widgets/          Cross-feature reusable widgets
```

---

## Naming Conventions

| Artifact | Convention | Example |
|---|---|---|
| Variables | `lowerCamelCase` | `reminderTitle`, `scheduledAt` |
| Classes | `UpperCamelCase` | `ReminderCard`, `CaptureProvider` |
| Screens | `<feature>_screen.dart` | `reminders_screen.dart` |
| Widgets | descriptive noun | `reminder_card.dart`, `now_card.dart` |
| Models | singular noun | `reminder.dart`, `event.dart` |
| Services | `<domain>_service.dart` | `reminder_service.dart` |
| Providers | `<domain>_provider.dart` | `reminder_provider.dart` |

---

## Colors & Text Styles — STRICT RULE

**Always** reference from `AppColors` and `AppTextStyles`.
**Never** hard-code hex values or inline `TextStyle` definitions.

```dart
// ✅ correct
color: AppColors.primary
style: AppTextStyles.bodyMedium

// ❌ forbidden
color: Color(0xFF6750A4)
style: TextStyle(fontSize: 16, color: Colors.white)
```

Exception: `Colors.transparent` is acceptable.

---

## Scaffold Background

Every `Scaffold` must set `backgroundColor: AppColors.background`.

```dart
// ✅ correct
Scaffold(
  backgroundColor: AppColors.background,
  body: ...
)

// ❌ missing backgroundColor — forbidden
Scaffold(
  body: ...
)
```

---

## Service Layer Pattern

Always define an abstract interface, then provide stub and real implementations.

```dart
// lib/core/services/reminder_service.dart
abstract class ReminderService {
  Future<List<Reminder>> getReminders();
  Future<Reminder> createReminder(Reminder reminder);
  Future<void> deleteReminder(String id);
}

// lib/core/services/stub_reminder_service.dart
class StubReminderService implements ReminderService { ... }

// lib/core/services/real_reminder_service.dart
class RealReminderService implements ReminderService { ... }
```

---

## Provider Pattern

Providers live in `lib/core/providers/` and extend `ChangeNotifier`.

```dart
class ReminderProvider extends ChangeNotifier {
  final ReminderService _service;
  List<Reminder> _reminders = [];

  ReminderProvider(this._service);

  List<Reminder> get reminders => _reminders;

  Future<void> loadReminders() async {
    _reminders = await _service.getReminders();
    notifyListeners();
  }
}
```

---

## Routing

Use `go_router`. All routes are defined centrally — no `Navigator.push` with anonymous routes.

---

## Theme

Dark Material 3. All theme data is in `lib/core/theme/`.
`AppColors` holds every color constant. `AppTextStyles` holds every text style.
Never import `Colors.xxx` for UI colors (only `Colors.transparent` is exempt).

---

## AI — never from Flutter directly

No Bedrock SDK imports. No direct HTTP calls to Bedrock endpoints.
All AI features call an AppSync mutation or REST endpoint → Lambda → Bedrock.
The Flutter client only sends text and receives structured responses.

---

## Two-Layer Notifications

When scheduling a reminder:
1. Call the API (Lambda schedules EventBridge + writes Aurora).
2. Also call `flutter_local_notifications` to schedule the same time on-device.

Both layers are always registered. Neither is optional.
