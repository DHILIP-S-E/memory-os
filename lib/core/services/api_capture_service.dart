import 'dart:io';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/services/api_mapper.dart';

/// Real implementation of [CaptureService].
/// Upload flow:
///   1. POST /captures/upload-url  → get pre-signed S3 PUT URL + capture_id
///   2. PUT <upload_url>           → upload file bytes directly to S3
///   3. POST /captures             → register capture metadata in DB
class ApiCaptureService implements CaptureService {
  final ApiClient _client;

  ApiCaptureService(this._client);

  @override
  Future<List<Capture>> fetchCaptures() async {
    final data = await _client.get('/captures') as List<dynamic>;
    return data.map((j) => captureFromApi(j)).toList();
  }

  @override
  Future<Capture> uploadCapture({
    required File file,
    required CaptureType type,
    String? eventId,
  }) async {
    final ext = _extensionFor(type);
    final contentType = _contentTypeFor(type);

    // Step 1: get pre-signed upload URL
    final urlData = await _client.post('/captures/upload-url', {
      'capture_type': type.name,
      'file_extension': ext,
      'content_type': contentType,
      if (eventId != null) 'event_id': eventId,
    }) as Map<String, dynamic>;

    final uploadUrl = urlData['upload_url'] as String;
    final captureId = urlData['capture_id'] as String;
    final s3Key = urlData['s3_key'] as String;

    // Step 2: upload file directly to S3
    final bytes = await file.readAsBytes();
    await _client.putFileToS3(uploadUrl, bytes, contentType);

    // Step 3: register capture in DB
    final captureData = await _client.post('/captures', {
      'capture_id': captureId,
      'storage_key': s3Key,
      'capture_type': type.name,
      if (eventId != null) 'event_id': eventId,
      'mime_type': contentType,
    }) as Map<String, dynamic>;

    return captureFromApi(captureData);
  }

  @override
  Future<Capture> saveTextNote({required String text, String? eventId}) async {
    final data = await _client.post('/captures/note', {
      'content': text,
      if (eventId != null) 'event_id': eventId,
    }) as Map<String, dynamic>;
    return captureFromApi(data);
  }

  @override
  Future<Capture> saveLink({required String url, String? eventId}) async {
    final data = await _client.post('/captures/link', {
      'url': url,
      if (eventId != null) 'event_id': eventId,
    }) as Map<String, dynamic>;
    return captureFromApi(data);
  }

  @override
  Future<void> deleteCapture(String id) async {
    await _client.delete('/captures/$id');
  }

  @override
  Future<Capture> retryProcessing(String id) async =>
      captureFromApi(await _client.post('/captures/$id/process'));

  String _extensionFor(CaptureType type) {
    switch (type) {
      case CaptureType.photo:
        return 'jpg';
      case CaptureType.voice:
        return 'm4a';
      case CaptureType.document:
        return 'pdf';
      default:
        return 'bin';
    }
  }

  String _contentTypeFor(CaptureType type) {
    switch (type) {
      case CaptureType.photo:
        return 'image/jpeg';
      case CaptureType.voice:
        return 'audio/m4a';
      case CaptureType.document:
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
