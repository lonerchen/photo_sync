import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';

import '../database/mobile_database.dart';

/// ChangeNotifier that wraps [UploadQueueManager] and exposes upload state
/// to the UI. Also writes completed tasks to the `upload_records` table.
class UploadQueueProvider extends ChangeNotifier {
  UploadQueueManager? _manager;
  StreamSubscription<QueueState>? _sub;

  QueueStatus _status = QueueStatus.idle;
  int _totalCount = 0;
  int _completedCount = 0;
  int _failedCount = 0;
  double _bytesPerSecond = 0;

  // For speed calculation
  int _lastBytesSnapshot = 0;
  DateTime _lastSpeedCheck = DateTime.now();

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  QueueStatus get status => _status;
  int get totalCount => _totalCount;
  int get completedCount => _completedCount;
  int get failedCount => _failedCount;
  double get bytesPerSecond => _bytesPerSecond;

  double get progress =>
      _totalCount == 0 ? 0.0 : _completedCount / _totalCount;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initialises a new [UploadQueueManager] and starts uploading [tasks].
  Future<void> startUpload({
    required List<UploadTask> tasks,
    required String baseUrl,
    required String deviceId,
    required Future<String> Function(UploadTask) resolveFilePath,
  }) async {
    // Dispose any previous manager.
    await _disposeManager();

    _totalCount = tasks.length;
    _completedCount = 0;
    _failedCount = 0;
    _bytesPerSecond = 0;
    _lastBytesSnapshot = 0;
    _lastSpeedCheck = DateTime.now();
    _status = QueueStatus.idle;
    notifyListeners();

    _manager = UploadQueueManager(
      baseUrl: baseUrl,
      deviceId: deviceId,
      resolveFilePath: resolveFilePath,
    );

    _sub = _manager!.stateStream.listen(_onState);
    await _manager!.addTasks(tasks);
  }

  /// Pauses the active upload queue.
  Future<void> pause() async {
    await _manager?.pause();
  }

  /// Resumes a paused upload queue.
  void resume() {
    _manager?.resume();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _onState(QueueState state) {
    _status = state.status;

    final done = state.completed;
    _completedCount = done.where((t) => t.taskStatus == TaskStatus.completed).length;
    _failedCount = done.where((t) => t.taskStatus == TaskStatus.failed).length;

    // 计算上传速率（每500ms更新一次）
    final now = DateTime.now();
    final elapsed = now.difference(_lastSpeedCheck).inMilliseconds;
    if (elapsed >= 500 && _manager != null) {
      final bytesDelta = _manager!.totalUploadedBytes - _lastBytesSnapshot;
      _bytesPerSecond = bytesDelta / (elapsed / 1000.0);
      _lastBytesSnapshot = _manager!.totalUploadedBytes;
      _lastSpeedCheck = now;
    }

    // Write newly completed tasks to upload_records.
    _persistCompleted(done);

    notifyListeners();
  }

  // Track which task IDs have already been persisted to avoid duplicates.
  final _persisted = <String>{};

  void _persistCompleted(List<UploadTask> completed) {
    final db = MobileDatabase();
    final newlyDone = completed.where((t) =>
        t.taskStatus == TaskStatus.completed &&
        !_persisted.contains('${t.serverId}:${t.fileName}'));

    if (newlyDone.isEmpty) return;

    final records = newlyDone.map((t) {
      _persisted.add('${t.serverId}:${t.fileName}');
      return {
        'server_id': t.serverId,
        'local_asset_id': t.localAssetId,
        'file_name': t.fileName,
        'album_name': t.albumName,
        'file_size': t.totalSize,
        'media_type': t.mediaType.toJson(),
        'upload_status': 'completed',
        'uploaded_at': DateTime.now().millisecondsSinceEpoch,
      };
    }).toList();

    // Fire-and-forget; errors are non-fatal.
    db.uploadRecordsDao.insertBatch(records).catchError((_) {});
  }

  Future<void> _disposeManager() async {
    await _sub?.cancel();
    _sub = null;
    _manager?.dispose();
    _manager = null;
    _persisted.clear();
  }

  @override
  void dispose() {
    _disposeManager();
    super.dispose();
  }
}
