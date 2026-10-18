import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/utils/error_text.dart';

/// "Try again" on a capture that could not be read: ask the server to read it again, and say
/// plainly if that request itself fails.
Future<void> retryCapture(BuildContext context, String captureId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<CaptureProvider>().retryProcessing(captureId);
    messenger.showSnackBar(const SnackBar(content: Text('Reading it again…')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e.toString())), backgroundColor: AppColors.urgent));
  }
}
