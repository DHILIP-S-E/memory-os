import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:personal_memory_os/core/router/app_router.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/providers/memory_provider.dart';

// Abstract service interfaces (+ stub implementations, used when USE_REAL_BACKEND=false)
import 'package:personal_memory_os/core/services/account_service.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'package:personal_memory_os/core/services/memory_service.dart';
import 'package:personal_memory_os/core/services/reminder_service.dart';

// Real implementations (used when USE_REAL_BACKEND=true)
import 'package:personal_memory_os/core/services/api_ai_service.dart';
import 'package:personal_memory_os/core/services/api_capture_service.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/services/api_event_service.dart';
import 'package:personal_memory_os/core/services/api_memory_service.dart';
import 'package:personal_memory_os/core/services/api_reminder_service.dart';
import 'package:personal_memory_os/core/services/app_auth_service.dart';
import 'package:personal_memory_os/core/services/device_service.dart';
import 'package:personal_memory_os/core/services/notification_service.dart';
import 'package:personal_memory_os/core/services/push_registration.dart';
import 'package:personal_memory_os/core/services/push_token_source.dart';
import 'package:personal_memory_os/core/services/share_source.dart';

// Offline-first sync (spec R6)
import 'package:personal_memory_os/core/sync/offline_services.dart';
import 'package:personal_memory_os/core/sync/prefs_store.dart';
import 'package:personal_memory_os/core/sync/sync_coordinator.dart';
import 'package:personal_memory_os/core/widget/home_widget_bridge.dart';
import 'package:personal_memory_os/core/widget/widget_sync.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notification service (device-side alarm layer)
  await NotificationService.initialize(
    onNotificationTap: (payload) {
      // payload = reminder ID; navigate to reminder detail
    },
    onActionTap: (actionId, payload) {
      // 'action_done' / 'action_snooze' — handled in provider
    },
  );

  final prefs = await SharedPreferences.getInstance();
  runApp(PersonalMemoryOsApp(
    useRealBackend: true, // the shipped app only ever shows the user's own real data
    store: PrefsKeyValueStore(prefs),
    shareSource: ChannelShareSource(),
    widgetBridge: ChannelHomeWidgetBridge(),
  ));
}

class PersonalMemoryOsApp extends StatefulWidget {
  /// False only in tests, which supply in-memory services instead of the live API.
  final bool useRealBackend;
  final KeyValueStore store;

  /// Where text shared from the system share sheet comes from.
  final ShareSource shareSource;

  /// Where the home-screen widget's content goes; null = no widget updates (tests).
  final HomeWidgetBridge? widgetBridge;

  const PersonalMemoryOsApp({
    super.key,
    this.useRealBackend = false,
    required this.store,
    this.shareSource = const NoShareSource(),
    this.widgetBridge,
  });

  @override
  State<PersonalMemoryOsApp> createState() => _PersonalMemoryOsAppState();
}

class _PersonalMemoryOsAppState extends State<PersonalMemoryOsApp> {
  late final AuthService _authService;
  late final AiService _aiService;
  late final AccountService _accountService;
  late final AuthProvider _auth;
  late final ReminderProvider _reminders;
  late final EventProvider _events;
  late final CaptureProvider _captures;
  late final MemoryProvider _memory;
  late final GoRouter _router;
  SyncCoordinator? _sync;
  PushRegistration? _push;
  StreamSubscription<String>? _shareSub;
  WidgetSync? _widgetSync;
  String? _pendingShare;

  @override
  void initState() {
    super.initState();

    if (widget.useRealBackend) {
      final auth = AppAuthService();
      final client = ApiClient(getToken: auth.getAccessToken);
      final queue = SyncQueue(widget.store);

      final remoteReminders = ApiReminderService(client);
      final remoteCaptures = ApiCaptureService(client);

      _authService = auth;
      _aiService = ApiAiService(client);
      _accountService = ApiAccountService(client);
      // Swap NoPushTokenSource for a firebase_messaging-backed source to enable cloud push.
      _push = PushRegistration(ApiDeviceService(client), NoPushTokenSource(), widget.store)
        ..listenForRefresh();
      _reminders = ReminderProvider(
          OfflineReminderService(remoteReminders, queue, widget.store));
      _captures = CaptureProvider(OfflineCaptureService(remoteCaptures, queue), store: widget.store, pollInterval: const Duration(seconds: 5));
      _events = EventProvider(ApiEventService(client));
      _memory = MemoryProvider(ApiMemoryService(client), _aiService);

      // Replay offline work on launch and whenever connectivity returns.
      final executor = SyncExecutor(remoteReminders, remoteCaptures);
      _sync = SyncCoordinator(
        queue,
        executor.call,
        onFlushed: (result) {
          if (result.synced > 0) {
            _reminders.loadReminders();
            _captures.loadCaptures();
          }
        },
      )..start();
    } else {
      _authService = StubAuthService();
      _aiService = StubAiService();
      _accountService = StubAccountService();
      _reminders = ReminderProvider(StubReminderService());
      _captures = CaptureProvider(StubCaptureService(), store: widget.store);
      _events = EventProvider(StubEventService());
      _memory = MemoryProvider(StubMemoryService(), _aiService);
    }

    _auth = AuthProvider(_authService)..checkAuthState();
    _auth.addListener(() {
      if (_auth.isAuthenticated) {
        _push?.register();
        _openPendingShare();
      }
    });
    _listenForShares();
    final bridge = widget.widgetBridge;
    if (bridge != null) {
      _widgetSync = WidgetSync(_reminders, _events, bridge)..start();
    }
    _router = createAppRouter(_auth);
  }

  /// Shared text waits until the user is signed in, then opens the event screen
  /// with it so the AI can extract the event immediately.
  void _listenForShares() {
    widget.shareSource.initialText().then(_queueShare);
    _shareSub = widget.shareSource.texts.listen(_queueShare);
  }

  void _queueShare(String? text) {
    if (text == null || text.trim().isEmpty) return;
    _pendingShare = text;
    if (_auth.isAuthenticated) _openPendingShare();
  }

  void _openPendingShare() {
    final text = _pendingShare;
    if (text == null) return;
    _pendingShare = null;
    // Sign-in finishes with go(today), which resets the stack; push only after
    // that navigation has settled or the event screen would be wiped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _router.push(AppRoutes.eventCreate, extra: text);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _widgetSync?.dispose();
    _sync?.dispose();
    _push?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: _authService),
        Provider<AiService>.value(value: _aiService),
        Provider<AccountService>.value(value: _accountService),
        Provider<HomeWidgetBridge>.value(value: widget.widgetBridge ?? const NoWidgetBridge()),
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _reminders),
        ChangeNotifierProvider.value(value: _events),
        ChangeNotifierProvider.value(value: _captures),
        ChangeNotifierProvider.value(value: _memory),
      ],
      child: MaterialApp.router(
        title: 'Personal Memory OS',
        theme: AppTheme.light,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
