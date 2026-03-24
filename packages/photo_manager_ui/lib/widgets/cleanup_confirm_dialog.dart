import 'package:flutter/material.dart';

/// A confirmation dialog shown before cleaning up local files.
///
/// Use [CleanupConfirmDialog.show] to display the dialog.
/// Returns `true` if the user confirms, `false` (or `null`) if cancelled.
class CleanupConfirmDialog extends StatelessWidget {
  const CleanupConfirmDialog({
    super.key,
    required this.fileCount,
    required this.estimatedBytes,
  });

  final int fileCount;

  /// Estimated space to be freed, in bytes.
  final int estimatedBytes;

  /// Shows the dialog and returns `true` if the user confirmed.
  static Future<bool> show(
    BuildContext context, {
    required int fileCount,
    required int estimatedBytes,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => CleanupConfirmDialog(
        fileCount: fileCount,
        estimatedBytes: estimatedBytes,
      ),
    );
    return result ?? false;
  }

  String get _sizeLabel {
    if (estimatedBytes >= 1024 * 1024 * 1024) {
      return '${(estimatedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (estimatedBytes >= 1024 * 1024) {
      return '${(estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(estimatedBytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Cleanup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$fileCount file${fileCount == 1 ? '' : 's'} will be removed from this device.'),
          const SizedBox(height: 8),
          Text('Estimated space freed: $_sizeLabel'),
          const SizedBox(height: 12),
          const Text(
            'These files have already been backed up to your storage server.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Clean Up'),
        ),
      ],
    );
  }
}
