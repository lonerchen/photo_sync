import 'package:flutter/material.dart';

/// Displays upload progress with file count, percentage, and transfer rate.
class UploadProgressBar extends StatelessWidget {
  const UploadProgressBar({
    super.key,
    required this.uploadedCount,
    required this.totalCount,
    required this.bytesPerSecond,
    this.failedCount = 0,
  });

  final int uploadedCount;
  final int totalCount;
  final double bytesPerSecond;
  final int failedCount;

  int get _processedCount => uploadedCount + failedCount;

  double get _progress =>
      totalCount == 0 ? 0.0 : _processedCount / totalCount;

  String get _percentage =>
      '${(_progress * 100).toStringAsFixed(1)}%';

  String get _rate {
    final mbps = bytesPerSecond / (1024 * 1024);
    return '${mbps.toStringAsFixed(2)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              failedCount > 0
                  ? '$uploadedCount / $totalCount  (失败 $failedCount)'
                  : '$uploadedCount / $totalCount',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '$_percentage  •  $_rate',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }
}
