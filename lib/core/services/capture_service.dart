import 'dart:io';
import 'package:personal_memory_os/core/models/capture.dart';

abstract class CaptureService {
  Future<List<Capture>> fetchCaptures();
  Future<Capture> uploadCapture({
    required File file,
    required CaptureType type,
    String? eventId,
  });
  Future<Capture> saveTextNote({required String text, String? eventId});
  Future<Capture> saveLink({required String url, String? eventId});
  Future<void> deleteCapture(String id);

  /// Read a failed capture again (for example after the AI was unavailable).
  Future<Capture> retryProcessing(String id);
}
