import 'package:flutter/material.dart';
import 'package:common/common.dart';
import 'package:photo_manager_ui/photo_manager_ui.dart';
import 'package:provider/provider.dart';

import '../providers/cleanup_provider.dart';
import '../services/connection_service.dart';

/// Screen for cleaning up locally stored photos that have been backed up.
class CleanupScreen extends StatelessWidget {
  const CleanupScreen({super.key});

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _onCalculate(BuildContext context) async {
    final server = context.read<ConnectionService>().currentServer;
    if (server == null) return;
    await context.read<CleanupProvider>().calculateEligible(server.serverId);
  }

  Future<void> _onCleanUp(BuildContext context) async {
    final server = context.read<ConnectionService>().currentServer;
    if (server == null) return;

    final provider = context.read<CleanupProvider>();
    await provider.startCleanup(server.serverId);

    if (!context.mounted) return;
    if (provider.status != CleanupStatus.confirming) return;

    final confirmed = await CleanupConfirmDialog.show(
      context,
      fileCount: provider.eligibleCount,
      estimatedBytes: provider.eligibleSize,
    );

    if (confirmed && context.mounted) {
      await context.read<CleanupProvider>().confirmCleanup(server.serverId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CleanupProvider>();
    final connectionService = context.watch<ConnectionService>();
    final l = AppLocalizations.of(context);
    final isConnected =
        connectionService.status == ConnectionStatus.connected;

    final isBusy = provider.status == CleanupStatus.calculating ||
        provider.status == CleanupStatus.cleaning;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.cleanupTitle),
        actions: [
          if (provider.status != CleanupStatus.idle)
            TextButton(
              onPressed: isBusy ? null : provider.reset,
              child: Text(l.reset),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isConnected)
              Card(
                color: Colors.orange,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l.notConnectedWarning,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.backedUpPhotos,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (provider.status == CleanupStatus.calculating)
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(l.calculating),
                        ],
                      )
                    else if (provider.status == CleanupStatus.done) ...[
                      Text(l.zeroFiles),
                      Text(l.zeroKbFreed),
                    ] else if (provider.eligibleCount > 0 ||
                        provider.status == CleanupStatus.confirming ||
                        provider.status == CleanupStatus.cleaning) ...[
                      Text(l.filesCount(provider.eligibleCount)),
                      Text(l.canBeFreed(_formatBytes(provider.eligibleSize))),
                    ] else
                      Text(l.tapCalculate),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (!isConnected || isBusy) ? null : () => _onCalculate(context),
                    child: Text(l.calculate),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (!isConnected ||
                            isBusy ||
                            provider.eligibleCount == 0 ||
                            provider.status == CleanupStatus.done)
                        ? null
                        : () => _onCleanUp(context),
                    child: isBusy && provider.status == CleanupStatus.cleaning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l.cleanUp),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (provider.status == CleanupStatus.done) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.cleanupComplete,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(l.filesRemoved(provider.cleanedCount)),
                      Text(l.sizeFreed(_formatBytes(provider.cleanedSize))),
                    ],
                  ),
                ),
              ),
              if (provider.failedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.filesCouldNotDelete(provider.failedFiles.length),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...provider.failedFiles.map(
                          (f) => Text(f, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],

            if (provider.status == CleanupStatus.done) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.cloud_outlined, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.cloudReminderBody,
                          style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (provider.status == CleanupStatus.error &&
                provider.errorMessage != null) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${l.errorPrefix}${provider.errorMessage}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
