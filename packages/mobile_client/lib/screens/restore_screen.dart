import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/restore_provider.dart';

/// Overlay widget that adds restore-mode UI on top of the media grid.
///
/// Usage: wrap the media grid area with this widget when restore mode is active.
/// It shows:
///   - A bottom action bar with selected count + "Restore" button (16.1)
///   - A progress dialog while restoring (16.5)
///   - A summary dialog on completion (16.5)
///   - Error details if any items failed (16.6)
class RestoreBottomBar extends StatelessWidget {
  const RestoreBottomBar({
    super.key,
    required this.allItems,
    required this.serverBaseUrl,
    required this.onExitRestoreMode,
  });

  final List<MediaItem> allItems;
  final String serverBaseUrl;
  final VoidCallback onExitRestoreMode;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RestoreProvider>();

    // Show progress dialog when restoring.
    if (provider.status == RestoreStatus.restoring) {
      return _RestoreProgressBar(
        restored: provider.restoredCount,
        total: provider.totalCount,
      );
    }

    return SafeArea(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              '${provider.selectedCount} selected',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                provider.clearSelection();
                onExitRestoreMode();
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.restore),
              label: Text('Restore ${provider.selectedCount}'),
              onPressed: provider.selectedCount == 0
                  ? null
                  : () => _startRestore(context, provider),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRestore(
    BuildContext context,
    RestoreProvider provider,
  ) async {
    await provider.restore(serverBaseUrl, allItems);

    if (!context.mounted) return;

    // Show summary dialog (16.5 / 16.6).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RestoreSummaryDialog(
        restoredCount: provider.restoredCount,
        failedFiles: provider.failedFiles,
        onDone: () {
          Navigator.of(context).pop();
          provider.reset();
          onExitRestoreMode();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress indicator (16.5)
// ---------------------------------------------------------------------------

class _RestoreProgressBar extends StatelessWidget {
  const _RestoreProgressBar({required this.restored, required this.total});

  final int restored;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : restored / total;
    return SafeArea(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Restoring $restored / $total…'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary dialog (16.5 / 16.6)
// ---------------------------------------------------------------------------

class _RestoreSummaryDialog extends StatelessWidget {
  const _RestoreSummaryDialog({
    required this.restoredCount,
    required this.failedFiles,
    required this.onDone,
  });

  final int restoredCount;
  final List<String> failedFiles;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final hasFailed = failedFiles.isNotEmpty;

    return AlertDialog(
      title: Text(hasFailed ? 'Restore completed with errors' : 'Restore complete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$restoredCount item(s) restored to your photo library.'),
          if (hasFailed) ...[
            const SizedBox(height: 12),
            Text(
              '${failedFiles.length} item(s) failed:',
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 4),
            // Show up to 5 failed file names to keep dialog compact.
            ...failedFiles.take(5).map(
                  (f) => Text('• $f',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
            if (failedFiles.length > 5)
              Text('… and ${failedFiles.length - 5} more'),
          ],
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
