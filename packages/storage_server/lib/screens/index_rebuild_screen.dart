import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/providers.dart';

/// Shown during database index rebuild. Displays scan progress and ETA.
class IndexRebuildScreen extends StatelessWidget {
  const IndexRebuildScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Consumer<ServerStatusProvider>(
          builder: (context, provider, _) {
            final progress = provider.indexRebuildProgress;
            return IndexRebuildProgress(progress: progress);
          },
        ),
      ),
    );
  }
}

/// Standalone progress widget for database index rebuild.
class IndexRebuildProgress extends StatelessWidget {
  const IndexRebuildProgress({
    super.key,
    required this.progress,
    this.scannedFiles,
    this.totalFiles,
    this.startTime,
  });

  /// 0.0–1.0, or null if not started.
  final double? progress;
  final int? scannedFiles;
  final int? totalFiles;
  final DateTime? startTime;

  @override
  Widget build(BuildContext context) {
    final p = progress ?? 0.0;
    final eta = _estimateEta(p);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'Rebuilding Index',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Scanning storage directory and rebuilding the media database…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(p * 100).toStringAsFixed(1)}%'),
                  if (scannedFiles != null && totalFiles != null)
                    Text('$scannedFiles / $totalFiles files'),
                ],
              ),
              if (eta != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Estimated time remaining: $eta',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _estimateEta(double progress) {
    if (startTime == null || progress <= 0) return null;
    final elapsed = DateTime.now().difference(startTime!).inSeconds;
    final totalEstimated = elapsed / progress;
    final remaining = (totalEstimated - elapsed).round();
    if (remaining <= 0) return null;
    if (remaining < 60) return '$remaining seconds';
    return '${(remaining / 60).round()} minutes';
  }
}
