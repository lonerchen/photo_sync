import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';

import '../database/mobile_database.dart';
import '../services/background_transfer_service.dart';

/// ChangeNotifier that wraps [UploadQueueManager] and exposes upload state
/// to the UI. Also writes completed tasks to the `upload_records` table.
class UploadQueueProvider extends ChangeNotifier {
  UploadQueueManager? _manager;
  StreamSubscription<QueueState>? _sub;
  final _bgService = BackgroundTransferService();

  QueueStatus _status = QueueStatus.idle;
  int _totalCount = 0;
  int _completedCount = 0;
  int _failedCount = 0;
  double _bytesPerSecond = 0;

  /// 上传完成时回调，传入 localAssetId，用于 UI 更新 badge。
  void Function(String assetId)? onAssetUploaded;

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
    Future<List<int>?> Function(UploadTask task)? resolveThumbnailBytes,
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
      resolveThumbnailBytes: resolveThumbnailBytes,
    );

    _sub = _manager!.stateStream.listen(_onState);
    await _bgService.begin();
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

  /// 追加单张或少量任务到已有队列。
  /// 如果队列不存在，则新建队列。
  Future<void> enqueueTask({
    required List<UploadTask> tasks,
    required String baseUrl,
    required String deviceId,
    required Future<String> Function(UploadTask) resolveFilePath,
    Future<List<int>?> Function(UploadTask task)? resolveThumbnailBytes,
  }) async {
    // 注册 resolver（在 dispose 之前）
    for (final t in tasks) {
      _resolverMap[t.fileName] = resolveFilePath;
    }

    if (_manager == null) {
      // 队列不存在，直接创建（不走 startUpload 避免 _disposeManager 清空 map）
      await _disposeManager();
      // 重新注册（_disposeManager 会清空，所以在它之后再写）
      for (final t in tasks) {
        _resolverMap[t.fileName] = resolveFilePath;
      }

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
        resolveFilePath: (task) {
          final fn = _resolverMap[task.fileName];
          return fn != null ? fn(task) : Future.value('');
        },
        resolveThumbnailBytes: resolveThumbnailBytes,
      );
      _sub = _manager!.stateStream.listen(_onState);
      await _bgService.begin();
      await _manager!.addTasks(tasks);
    } else {
      // 队列已存在，追加任务
      _totalCount += tasks.length;
      await _manager!.addTasks(tasks);
      notifyListeners();
    }
  }

  // fileName → resolver，支持动态追加任务
  final _resolverMap = <String, Future<String> Function(UploadTask)>{};

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

    // 上传全部完成时释放后台任务
    if (state.status == QueueStatus.idle) {
      _bgService.end();
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
      // 通知 UI 该 asset 已上传完成
      if (t.localAssetId.isNotEmpty) {
        onAssetUploaded?.call(t.localAssetId);
      }
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
    _resolverMap.clear();
    await _bgService.end();
  }

  @override
  void dispose() {
    _disposeManager();
    super.dispose();
  }
}
