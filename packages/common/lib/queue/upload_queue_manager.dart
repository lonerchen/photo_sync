import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import '../models/upload_task.dart';
import '../protocol/api_dtos.dart';
import 'upload_worker.dart';

/// Overall status of the upload queue.
enum QueueStatus { idle, running, paused }

/// Snapshot of the queue state broadcast to listeners.
class QueueState {
  final QueueStatus status;
  final List<UploadTask> pending;
  final List<UploadTask> active;
  final List<UploadTask> paused;
  final List<UploadTask> completed;

  const QueueState({
    required this.status,
    required this.pending,
    required this.active,
    required this.paused,
    required this.completed,
  });
}

/// Manages concurrent file uploads with pause/resume and dedup support.
///
/// - Max 3 concurrent [UploadWorker]s.
/// - FIFO scheduling from [pendingQueue].
/// - Live Photo pairs: HEIC is enqueued before MOV.
/// - Batch dedup via POST /api/v1/upload/check-exists before starting.
class UploadQueueManager {
  static const int maxConcurrent = 6;

  final String baseUrl;
  final String deviceId;

  /// Returns the local file path for a given [UploadTask].
  final Future<String> Function(UploadTask task) resolveFilePath;

  final http.Client _client;

  final List<UploadTask> pendingQueue = [];
  final List<UploadTask> pausedTasks = [];
  final List<UploadTask> completedTasks = [];

  final _activeWorkers = <UploadTask, UploadWorker>{};

  QueueStatus _status = QueueStatus.idle;
  QueueStatus get status => _status;

  int _totalUploadedBytes = 0;
  int get totalUploadedBytes => _totalUploadedBytes;

  final _stateController = StreamController<QueueState>.broadcast();

  /// Stream of [QueueState] updates.
  Stream<QueueState> get stateStream => _stateController.stream;

  UploadQueueManager({
    required this.baseUrl,
    required this.deviceId,
    required this.resolveFilePath,
    http.Client? client,
  }) : _client = client ?? http.Client();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Adds [tasks] to the queue, applying Live Photo ordering, then runs dedup
  /// and starts uploading.
  Future<void> addTasks(List<UploadTask> tasks) async {
    final ordered = _orderLivePhotos(tasks);
    final filtered = await _dedupFilter(ordered);
    pendingQueue.addAll(filtered);
    _notify();
    _scheduleWorkers();
  }

  /// Pauses all active workers. They finish their current chunk then stop.
  Future<void> pause() async {
    if (_status != QueueStatus.running) return;
    _status = QueueStatus.paused;

    // Signal all active workers to pause
    for (final worker in _activeWorkers.values) {
      worker.pause();
    }
    // Workers will return paused tasks via their futures; _onWorkerDone handles
    // moving them to pausedTasks.
    _notify();
  }

  /// Moves paused tasks back to the pending queue and restarts workers.
  void resume() {
    if (_status != QueueStatus.paused) return;
    _status = QueueStatus.running;
    pendingQueue.insertAll(0, pausedTasks);
    pausedTasks.clear();
    _notify();
    _scheduleWorkers();
  }

  void dispose() {
    _stateController.close();
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Internal scheduling
  // ---------------------------------------------------------------------------

  void _scheduleWorkers() {
    if (_status == QueueStatus.paused) return;
    _status = QueueStatus.running;

    while (_activeWorkers.length < maxConcurrent && pendingQueue.isNotEmpty) {
      final task = pendingQueue.removeAt(0);
      _startWorker(task);
    }

    if (_activeWorkers.isEmpty && pendingQueue.isEmpty) {
      _status = QueueStatus.idle;
    }
    _notify();
  }

  Future<void> _startWorker(UploadTask task) async {
    int _lastReported = 0;
    // 先占位，防止 await resolveFilePath 期间并发超限
    // 每个 worker 独立 http.Client，各自维护独立 TCP 连接，避免串行排队
    _activeWorkers[task] = UploadWorker(
      baseUrl: baseUrl,
      deviceId: deviceId,
      filePath: '',
      task: task,
      onProgress: (_a, _b) {},
    );
    debugPrint('[Queue] resolving filePath for ${task.fileName}');
    final filePath = await resolveFilePath(task);
    debugPrint('[Queue] resolved filePath="${filePath}" for ${task.fileName}');
    final worker = UploadWorker(
      baseUrl: baseUrl,
      deviceId: deviceId,
      filePath: filePath,
      task: task,
      onProgress: (uploaded, total) {
        final delta = uploaded - _lastReported;
        if (delta > 0) {
          _totalUploadedBytes += delta;
          _lastReported = uploaded;
        }
        _notify();
      },
    );
    _activeWorkers[task] = worker;

    worker.run().then((result) => _onWorkerDone(task, result)).catchError(
      (Object e) => _onWorkerError(task, e),
    );
  }

  void _onWorkerDone(UploadTask originalTask, UploadTask result) {
    _activeWorkers.remove(originalTask);

    if (result.taskStatus == TaskStatus.paused) {
      pausedTasks.add(result);
    } else {
      completedTasks.add(result);
    }

    _scheduleWorkers();
  }

  void _onWorkerError(UploadTask task, Object error) {
    debugPrint('[Queue] worker error for ${task.fileName}: $error');
    _activeWorkers.remove(task);
    completedTasks.add(
      task.copyWith(
        taskStatus: TaskStatus.failed,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _scheduleWorkers();
  }

  // ---------------------------------------------------------------------------
  // Live Photo ordering (task 3.4)
  // ---------------------------------------------------------------------------

  /// Ensures HEIC comes before its paired MOV for Live Photo assets.
  List<UploadTask> _orderLivePhotos(List<UploadTask> tasks) {
    final result = <UploadTask>[];
    final movTasks = <UploadTask>[];

    for (final t in tasks) {
      final isLiveMov = t.mediaType == MediaType.livePhoto &&
          t.fileName.toLowerCase().endsWith('.mov');
      if (isLiveMov) {
        movTasks.add(t);
      } else {
        result.add(t);
      }
    }

    // Append MOV tasks after their HEIC counterparts
    for (final mov in movTasks) {
      final pairName = mov.livePhotoPairName;
      if (pairName != null) {
        final heicIndex = result.indexWhere((t) => t.fileName == pairName);
        if (heicIndex >= 0) {
          result.insert(heicIndex + 1, mov);
          continue;
        }
      }
      result.add(mov);
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Batch dedup pre-check (task 3.5)
  // ---------------------------------------------------------------------------

  Future<List<UploadTask>> _dedupFilter(List<UploadTask> tasks) async {
    if (tasks.isEmpty) return tasks;

    // Group by albumName for the API call
    final byAlbum = <String, List<UploadTask>>{};
    for (final t in tasks) {
      byAlbum.putIfAbsent(t.albumName, () => []).add(t);
    }

    final skipped = <String>{};

    for (final entry in byAlbum.entries) {
      final albumName = entry.key;
      final albumTasks = entry.value;
      final fileNames = albumTasks.map((t) => t.fileName).toList();

      try {
        final req = CheckExistsRequest(
          deviceId: deviceId,
          albumName: albumName,
          fileNames: fileNames,
        );
        final uri = Uri.parse('$baseUrl/api/v1/upload/check-exists');
        final response = await _client.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(req.toJson()),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final apiResp = ApiResponse.fromJson(
            body,
            (d) => CheckExistsResponse.fromJson(d as Map<String, dynamic>),
          );
          if (apiResp.isSuccess && apiResp.data != null) {
            skipped.addAll(apiResp.data!.exists);
          }
        }
      } catch (_) {
        // If dedup check fails, proceed with all tasks
      }
    }

    if (skipped.isEmpty) return tasks;

    final now = DateTime.now().millisecondsSinceEpoch;
    final filtered = <UploadTask>[];
    for (final t in tasks) {
      if (skipped.contains(t.fileName)) {
        // Mark as completed (skipped/deduped)
        completedTasks.add(t.copyWith(
          taskStatus: TaskStatus.completed,
          updatedAt: now,
        ));
      } else {
        filtered.add(t);
      }
    }
    return filtered;
  }

  // ---------------------------------------------------------------------------
  // State notification
  // ---------------------------------------------------------------------------

  void _notify() {
    if (_stateController.isClosed) return;
    _stateController.add(QueueState(
      status: _status,
      pending: List.unmodifiable(pendingQueue),
      active: List.unmodifiable(_activeWorkers.keys),
      paused: List.unmodifiable(pausedTasks),
      completed: List.unmodifiable(completedTasks),
    ));
  }
}
