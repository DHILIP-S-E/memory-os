import 'package:flutter/material.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/utils/date_utils.dart';

class CaptureCard extends StatelessWidget {
  final Capture capture;
  final VoidCallback? onTap;

  /// Shown as "Try again" when the capture could not be read.
  final VoidCallback? onRetry;

  const CaptureCard({super.key, required this.capture, this.onTap, this.onRetry});

  Color get _typeColor {
    switch (capture.type) {
      case CaptureType.photo:
        return AppColors.capturePhoto;
      case CaptureType.voice:
        return AppColors.captureVoice;
      case CaptureType.note:
        return AppColors.captureNote;
      case CaptureType.document:
        return AppColors.captureDoc;
      case CaptureType.link:
        return AppColors.captureLink;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get _typeIcon {
    switch (capture.type) {
      case CaptureType.photo:
        return Icons.image_outlined;
      case CaptureType.voice:
        return Icons.mic_outlined;
      case CaptureType.note:
        return Icons.notes;
      case CaptureType.document:
        return Icons.description_outlined;
      case CaptureType.link:
        return Icons.link;
      default:
        return Icons.attach_file;
    }
  }

  String get _typeLabel {
    switch (capture.type) {
      case CaptureType.photo:
        return 'Photo';
      case CaptureType.voice:
        return 'Voice Note';
      case CaptureType.note:
        return 'Note';
      case CaptureType.document:
        return 'Document';
      case CaptureType.link:
        return 'Link';
      default:
        return 'Capture';
    }
  }

  Widget _buildProcessingBadge() {
    if (capture.processingStatus == CaptureProcessingStatus.processed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 10, color: AppColors.success),
            const SizedBox(width: 3),
            Text(
              'AI ready',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (capture.processingStatus == CaptureProcessingStatus.processing ||
        capture.processingStatus == CaptureProcessingStatus.queued) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Processing',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (capture.processingStatus == CaptureProcessingStatus.failed) {
      return Container(
        key: const ValueKey('failed-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.urgent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Text(
          "Couldn't read",
          style: TextStyle(fontSize: 10, color: AppColors.urgent, fontWeight: FontWeight.w600),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon, color: _typeColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _typeLabel,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _typeColor,
                        ),
                      ),
                      const Spacer(),
                      _buildProcessingBadge(),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (capture.content != null)
                    Text(
                      capture.content!,
                      style: AppTextStyles.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (capture.transcription != null)
                    Text(
                      capture.transcription!,
                      style: AppTextStyles.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      AppDateUtils.formatDateTime(capture.createdAt),
                      style: AppTextStyles.caption,
                    ),
                  if (capture.aiResult?.summary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      capture.aiResult!.summary!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (onRetry != null && capture.processingStatus == CaptureProcessingStatus.failed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('retry-capture'),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Try again'),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    AppDateUtils.timeUntil(capture.createdAt) == 'Overdue'
                        ? AppDateUtils.formatDateTime(capture.createdAt)
                        : '${AppDateUtils.timeUntil(capture.createdAt)} ago',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
