import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:personal_memory_os/core/app_dependencies.dart';
import 'package:personal_memory_os/core/router/app_router.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/providers/memory_provider.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard.dart';
import 'package:personal_memory_os/core/scroll_guard/other_apps_watcher.dart';
import 'package:personal_memory_os/core/scroll_guard/scroll_guard_host.dart';
import 'package:personal_memory_os/core/scroll_guard/usage_source.dart';

// Abstract service interfaces
import 'package:personal_memory_os/core/services/account_service.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';

// Real implementations
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
import 'package:personal_memory_os/core/config.dart';
import 'package:personal_memory_os/core/services/firebase_push_token_source.dart';
import 'package:personal_memory_os/core/services/google_token_source.dart';
import 'package:personal_memory_os/core/services/timezone_sync.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';

/// Notification taps, forwarded to the running app (it has no router yet when we initialise).
final _notificationTaps = StreamController<String?>.broadcast();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notification service (device-side alarm layer)
  await NotificationService.initialize(
    onNotificationTap: (payload) {
      // payload = reminder ID, or the Scroll Guard marker
      _notificationTaps.add(payload);
    },
    onActionTap: (actionId, payload) {
      // 'action_done' / 'action_snooze' — handled in provider
    },
  );

  final prefs = await SharedPreferences.getInstance();
  runApp(PersonalMemoryOsApp(
    store: PrefsKeyValueStore(prefs),
    shareSource: ChannelShareSource(),
    widgetBridge: ChannelHomeWidgetBridge(),
    usageSource: const ChannelUsageSource(),
  ));
}

class PersonalMemoryOsApp extends StatefulWidget {
  /// Tests supply their own services here; null (the shipped app) builds the real ones.
  final AppDependencies? deps;
  final KeyValueStore store;

  /// Where text shared from the system share sheet comes from.
  final ShareSource shareSource;

  /// Where the home-screen widget's content goes; null = no widget updates (tests).
  final HomeWidgetBridge? widgetBridge;

  /// Time spent in other apps (Android Usage Access); none in tests and on other platforms.
  final UsageSource usageSource;

  const PersonalMemoryOsApp({
    super.key,
    this.deps,
    required this.store,
    this.shareSource = const NoShareSource(),
    this.widgetBridge,
    this.usageSource = const NoUsageSource(),
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
  late final ScrollGuard _scrollGuard;
  late final GoRouter _router;
  SyncCoordinator? _sync;
  PushRegistration? _push;
  StreamSubscription<String>? _shareSub;
  StreamSubscription<String?>? _tapSub;
  OtherAppsWatcher? _otherApps;
  WidgetSync? _widgetSync;
  String? _pendingShare;
  bool _pendingCapture = false;

  @override
  void initState() {
    super.initState();

    _scrollGuard = ScrollGuard(widget.store)..load();

    final deps = widget.deps;
    if (deps == null) {
      final auth = AppAuthService();
      final client = ApiClient(getToken: auth.getAccessToken);
      final queue = SyncQueue(widget.store);

      final remoteReminders = ApiReminderService(client);
      final remoteCaptures = ApiCaptureService(client);

      _authService = auth;
      _aiService = ApiAiService(client);
      _accountService = ApiAccountService(client);
      // Push needs the Firebase build settings; without them only local alarms ring.
      final PushTokenSource pushSource = AppConfig.pushEnabled ? FirebasePushTokenSource() : NoPushTokenSource();
      _push = PushRegistration(ApiDeviceService(client), pushSource, widget.store)
        ..listenForRefresh();
      _reminders = ReminderProvider(
          OfflineReminderService(remoteReminders, queue, widget.store));
      _captures = CaptureProvider(OfflineCaptureService(remoteCaptures, queue), store: widget.store, pollInterval: const Duration(seconds: 5), onCaptured: _scrollGuard.onCaptured);
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
      _authService = deps.authService;
      _aiService = deps.aiService;
      _accountService = deps.accountService;
      _reminders = ReminderProvider(deps.reminders);
      _captures = CaptureProvider(deps.captures, store: widget.store, onCaptured: _scrollGuard.onCaptured);
      _events = EventProvider(deps.events);
      _memory = MemoryProvider(deps.memory, _aiService);
    }

    _auth = AuthProvider(
      _authService,
      google: deps == null && AppConfig.googleSignInEnabled
          ? PluginGoogleTokenSource(AppConfig.googleServerClientId)
          : null,
      onSigningOut: () async => _push?.unregister(),
    )..checkAuthState();
    _auth.addListener(() {
      if (_auth.isAuthenticated) {
        _push?.register();
        // Quiet hours and recurring reminders follow the phone's own clock.
        unawaited(syncDeviceTimezone(_accountService));
        _openPendingShare();
        _openPendingCapture();
      }
    });
    _listenForShares();
    final bridge = widget.widgetBridge;
    if (bridge != null) {
      _widgetSync = WidgetSync(_reminders, _events, bridge)..start();
    }
    _router = createAppRouter(_auth);

    // A Scroll Guard notification tap opens capture, once the user is signed in. A tap that
    // launched the app from a killed state arrives as the launch payload, not on the stream.
    _pendingCapture = NotificationService.launchPayload == NotificationService.scrollGuardPayload;
    _tapSub = _notificationTaps.stream.listen((payload) {
      if (payload != NotificationService.scrollGuardPayload) return;
      _pendingCapture = true;
      _openPendingCapture();
    });
    if (widget.usageSource.supported) {
      _otherApps = OtherAppsWatcher(
        _scrollGuard,
        widget.usageSource,
        (title, body) => NotificationService.showScrollGuard(title: title, body: body),
      )..start();
    }
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

  void _openPendingCapture() {
    if (!_pendingCapture || !_auth.isAuthenticated) return;
    _pendingCapture = false;
    // Sign-in finishes with go(today); move on only after that has settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _router.go(AppRoutes.capture);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _tapSub?.cancel();
    _otherApps?.dispose();
    _scrollGuard.dispose();
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
        Provider<UsageSource>.value(value: widget.usageSource),
        Provider<HomeWidgetBridge>.value(value: widget.widgetBridge ?? const NoWidgetBridge()),
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _reminders),
        ChangeNotifierProvider.value(value: _events),
        ChangeNotifierProvider.value(value: _captures),
        ChangeNotifierProvider.value(value: _memory),
        ChangeNotifierProvider.value(value: _scrollGuard),
      ],
      child: MaterialApp.router(
        title: 'Personal Memory OS',
        theme: AppTheme.light,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => ScrollGuardHost(
          onCapture: () => _router.go(AppRoutes.capture),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
