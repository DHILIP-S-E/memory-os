import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';
import 'package:personal_memory_os/core/utils/action_suggestions.dart';

class CaptureProvider extends ChangeNotifier {
  static const _handledKey = 'handled_action_suggestions_v1';

  final CaptureService _service;
  final KeyValueStore? _store;
  final Set<String> _handled = {};
  bool _handledLoaded = false;

  /// How often to re-check captures that are still being processed; null = never.
  final Duration? pollInterval;
  Timer? _pollTimer;

  /// Called after the user successfully captures something (Scroll Guard uses it to end a session).
  final VoidCallback? onCaptured;

  CaptureProvider(this._service, {KeyValueStore? store, this.pollInterval, this.onCaptured})
      : _store = store;

  /// True while any capture is waiting for or undergoing AI processing.
  bool get hasInFlight => _captures.any((c) =>
      c.processingStatus == CaptureProcessingStatus.queued ||
      c.processingStatus == CaptureProcessingStatus.processing ||
      c.processingStatus == CaptureProcessingStatus.uploaded);

  /// Poll until nothing is in flight, so "AI ready" appears without a manual
  /// refresh. Stops by itself; restarted whenever new captures arrive.
  void _syncPolling() {
    final interval = pollInterval;
    if (interval == null || !hasInFlight) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(interval, (_) => _refreshQuietly());
  }

  Future<void> _refreshQuietly() async {
    try {
      _captures = await _service.fetchCaptures();
      notifyListeners();
    } catch (_) {
      // Transient (offline): keep the current list and try again next tick.
    }
    _syncPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  List<Capture> _captures = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String? _error;

  List<Capture> get captures => _captures;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  String? get error => _error;

  List<Capture> capturesForEvent(String eventId) =>
      _captures.where((c) => c.eventId == eventId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Capture> get recentCaptures =>
      _captures.take(10).toList();

  /// AI-extracted actions the user has not yet turned into a reminder or dismissed.
  List<ActionSuggestion> pendingActions({String? eventId}) =>
      pendingSuggestions(_captures, _handled, eventId: eventId);

  /// Record the user's decision so the suggestion never reappears (survives restarts).
  Future<void> markActionHandled(ActionSuggestion suggestion) async {
    _handled.add(suggestion.key);
    notifyListeners();
    await _store?.write(_handledKey, jsonEncode(_handled.toList()));
  }

  Future<void> _loadHandled() async {
    if (_handledLoaded) return;
    _handledLoaded = true;
    final raw = await _store?.read(_handledKey);
    if (raw != null && raw.isNotEmpty) {
      _handled.addAll((jsonDecode(raw) as List<dynamic>).cast<String>());
    }
  }

  Future<void> loadCaptures() async {
    await _loadHandled();
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _captures = await _service.fetchCaptures();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _syncPolling();
      notifyListeners();
    }
  }

  Future<void> uploadPhoto({required File file, String? eventId}) async {
    _isUploading = true;
    notifyListeners();
    try {
      final capture = await _service.uploadCapture(
        file: file,
        type: CaptureType.photo,
        eventId: eventId,
      );
      _captures.insert(0, capture);
      _syncPolling();
      onCaptured?.call();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<void> uploadVoiceNote({required File file, String? eventId}) async {
    _isUploading = true;
    notifyListeners();
    try {
      final capture = await _service.uploadCapture(
        file: file,
        type: CaptureType.voice,
        eventId: eventId,
      );
      _captures.insert(0, capture);
      _syncPolling();
      onCaptured?.call();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<void> saveTextNote({required String text, String? eventId}) async {
    try {
      final capture = await _service.saveTextNote(text: text, eventId: eventId);
      _captures.insert(0, capture);
      _syncPolling();
      onCaptured?.call();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveLink({required String url, String? eventId}) async {
    try {
      final capture = await _service.saveLink(url: url, eventId: eventId);
      _captures.insert(0, capture);
      _syncPolling();
      onCaptured?.call();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteCapture(String id) async {
    try {
      await _service.deleteCapture(id);
      _captures.removeWhere((c) => c.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Ask the server to read a failed capture again. Errors are recorded and rethrown so the
  /// screen can say what went wrong.
  Future<void> retryProcessing(String id) async {
    try {
      final updated = await _service.retryProcessing(id);
      final index = _captures.indexWhere((c) => c.id == id);
      if (index != -1) _captures[index] = updated;
      _error = null;
      _syncPolling(); // follow it until it is read
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void updateCaptureLocally(Capture updated) {
    final index = _captures.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _captures[index] = updated;
      notifyListeners();
    }
  }
}
