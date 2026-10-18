import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/shared/widgets/error_banner.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/services/camera_service.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/shared/widgets/capture_card.dart';
import 'package:personal_memory_os/shared/widgets/retry_capture.dart';
import 'package:personal_memory_os/shared/widgets/empty_state.dart';
import 'package:personal_memory_os/features/capture/widgets/voice_recorder_sheet.dart';
import 'package:personal_memory_os/features/capture/widgets/text_note_sheet.dart';
import 'package:personal_memory_os/features/capture/widgets/link_capture_sheet.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<CaptureProvider>().loadCaptures(),
    );
  }

  Future<void> _capturePhoto() async {
    final file = await CameraService.capturePhoto();
    if (file == null || !mounted) return;
    try {
      await context.read<CaptureProvider>().uploadPhoto(file: file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.urgent,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await CameraService.pickFromGallery();
    if (file == null || !mounted) return;
    try {
      await context.read<CaptureProvider>().uploadPhoto(file: file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.urgent,
          ),
        );
      }
    }
  }

  void _openVoiceRecorder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VoiceRecorderSheet(
        onSaved: (file) =>
            context.read<CaptureProvider>().uploadVoiceNote(file: file as dynamic),
      ),
    );
  }

  void _openTextNote() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TextNoteSheet(
        onSaved: (text) =>
            context.read<CaptureProvider>().saveTextNote(text: text),
      ),
    );
  }

  void _openLinkCapture() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LinkCaptureSheet(
        onSaved: (url) =>
            context.read<CaptureProvider>().saveLink(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildCaptureBar(),
            const Divider(height: 1),
            Expanded(child: _buildCaptureList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Capture', style: AppTextStyles.displayMedium),
                SizedBox(height: 2),
                Text(
                  'Capture first. Organize later.',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          Consumer<CaptureProvider>(
            builder: (_, p, __) => p.isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureBar() {
    final actions = [
      (Icons.camera_alt_outlined, 'Camera', AppColors.capturePhoto, _capturePhoto),
      (Icons.photo_library_outlined, 'Gallery', AppColors.capturePhoto, _pickFromGallery),
      (Icons.mic_outlined, 'Voice', AppColors.captureVoice, _openVoiceRecorder),
      (Icons.notes, 'Note', AppColors.captureNote, _openTextNote),
      (Icons.link, 'Link', AppColors.captureLink, _openLinkCapture),
    ];

    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: actions.map((a) {
          final (icon, label, color, fn) = a;
          return Semantics(
            button: true,
            label: label,
            child: GestureDetector(
              onTap: fn,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.25)),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCaptureList() {
    return Consumer<CaptureProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (provider.error != null && provider.captures.isEmpty) {
          return Center(
            child: ErrorBanner(message: provider.error!, onRetry: provider.loadCaptures),
          );
        }
        if (provider.captures.isEmpty) {
          return const EmptyState(
            icon: Icons.camera_outlined,
            title: 'Nothing captured yet',
            subtitle: 'Use the buttons above to capture photos, voice notes, or text',
          );
        }
        return RefreshIndicator(
          onRefresh: provider.loadCaptures,
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 100),
            itemCount: provider.captures.length,
            itemBuilder: (_, i) => CaptureCard(
              capture: provider.captures[i],
              onRetry: () => retryCapture(context, provider.captures[i].id),
            ),
          ),
        );
      },
    );
  }
}
