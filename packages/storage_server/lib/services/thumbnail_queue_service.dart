import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:common/common.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../server/websocket_server.dart';
import 'i_server_database.dart';
import 'i_thumbnail_queue.dart';

// ---------------------------------------------------------------------------
// Isolate message types
// ---------------------------------------------------------------------------

/// Sent from the main isolate to the worker isolate.
class _ThumbnailTask {
  const _ThumbnailTask({
    required this.mediaId,
    required this.filePath,
    required this.mediaType,
    required this.thumbnailPath,
  });

  final int mediaId;
  final String filePath;
  final MediaType mediaType;
  final String thumbnailPath;
}

/// Sent from the worker isolate back to the main isolate.
class _ThumbnailResult {
  const _ThumbnailResult({
    required this.mediaId,
    required this.thumbnailPath,
    required this.success,
    this.error,
  });

  final int mediaId;
  final String thumbnailPath;
  final bool success;
  final String? error;
}

// ---------------------------------------------------------------------------
// Isolate worker entry point
// ---------------------------------------------------------------------------

/// Entry point for the background thumbnail-generation isolate.
///
/// Receives [_ThumbnailTask] messages and replies with [_ThumbnailResult].
void _thumbnailWorkerEntry(SendPort replyPort) {
  final receivePort = ReceivePort();
  replyPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is _ThumbnailTask) {
      final result = await _processTask(message);
      replyPort.send(result);
    }
  });
}

Future<_ThumbnailResult> _processTask(_ThumbnailTask task) async {
  try {
    await Directory(p.dirname(task.thumbnailPath)).create(recursive: true);

    if (task.mediaType == MediaType.video ||
        (task.mediaType == MediaType.livePhoto &&
            task.filePath.toLowerCase().endsWith('.mov'))) {
      await _generateVideoThumbnail(task.filePath, task.thumbnailPath);
    } else {
      await _generateImageThumbnail(task.filePath, task.thumbnailPath);
    }

    return _ThumbnailResult(
      mediaId: task.mediaId,
      thumbnailPath: task.thumbnailPath,
      success: true,
    );
  } catch (e) {
    return _ThumbnailResult(
      mediaId: task.mediaId,
      thumbnailPath: task.thumbnailPath,
      success: false,
      error: e.toString(),
    );
  }
}

/// Generates a 300×300 JPEG thumbnail from an image file.
/// For HEIC files on macOS, uses `sips` to convert first.
Future<void> _generateImageThumbnail(String filePath, String outPath) async {
  final ext = p.extension(filePath).toLowerCase();

  // HEIC/HEIF: use sips (macOS) to convert to JPEG first, then resize.
  if (ext == '.heic' || ext == '.heif') {
    final tempJpeg = '${outPath}_heic_tmp.jpg';
    try {
      final result = await Process.run('sips', [
        '-s', 'format', 'jpeg',
        '-s', 'formatOptions', '85',
        filePath,
        '--out', tempJpeg,
      ]);
      if (result.exitCode == 0 && await File(tempJpeg).exists()) {
        await _resizeAndCrop(tempJpeg, outPath);
        return;
      }
    } finally {
      final tmp = File(tempJpeg);
      if (await tmp.exists()) await tmp.delete();
    }
    // sips failed — fall through to image package (will likely fail too, but worth trying)
  }

  await _resizeAndCrop(filePath, outPath);
}

Future<void> _resizeAndCrop(String filePath, String outPath) async {
  final bytes = await File(filePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Failed to decode image: $filePath');

  final cropped = img.copyResizeCropSquare(decoded, size: 300);
  final jpeg = img.encodeJpg(cropped, quality: 80);
  await File(outPath).writeAsBytes(jpeg);
}

/// Generates a 300×300 JPEG thumbnail from the first frame of a video.
///
/// Strategy:
/// 1. Try `ffmpeg` (cross-platform, needs to be installed).
/// 2. Fallback to `qlmanage -t` (macOS Quick Look, no extra install needed).
/// 3. If both fail, throw so the caller can mark status as 'failed'.
Future<void> _generateVideoThumbnail(String filePath, String outPath) async {
  // --- Attempt 1: ffmpeg ---
  final tempPng = '${outPath}_frame.png';
  try {
    final result = await Process.run('ffmpeg', [
      '-y', '-i', filePath, '-vframes', '1', '-q:v', '2', tempPng,
    ]);
    if (result.exitCode == 0 && await File(tempPng).exists()) {
      await _generateImageThumbnail(tempPng, outPath);
      return;
    }
  } catch (_) {
    // ffmpeg not installed or failed — try fallback
  } finally {
    final tmp = File(tempPng);
    if (await tmp.exists()) await tmp.delete();
  }

  // --- Attempt 2: qlmanage (macOS Quick Look) ---
  final qlDir = p.dirname(outPath);
  try {
    final result = await Process.run('qlmanage', [
      '-t', '-s', '300', '-o', qlDir, filePath,
    ]);
    if (result.exitCode == 0) {
      // qlmanage outputs "<filename>.png" in qlDir
      final qlOut = p.join(qlDir, '${p.basename(filePath)}.png');
      if (await File(qlOut).exists()) {
        await _generateImageThumbnail(qlOut, outPath);
        await File(qlOut).delete();
        return;
      }
    }
  } catch (_) {
    // qlmanage not available (non-macOS)
  }

  throw Exception('No video thumbnail tool available for: $filePath');
}

// ---------------------------------------------------------------------------
// ThumbnailQueueService
// ---------------------------------------------------------------------------

/// Implements [IThumbnailQueue] using a background [Isolate].
///
/// - [normalQueue]: FIFO queue for newly uploaded media.
/// - [priorityQueue]: processed before [normalQueue] (front-of-queue insertion).
///
/// After each thumbnail is generated the service:
/// 1. Updates `media_items.thumbnail_path` and `thumbnail_status` in the DB.
/// 2. Pushes a `thumbnail_ready` WebSocket event to the owning device.
class ThumbnailQueueService implements IThumbnailQueue {
  ThumbnailQueueService({
    required IServerDatabase database,
    required WebSocketServer wsServer,
    required String storagePath,
    Future<String> Function()? storagePathResolver,
  })  : _database = database,
        _wsServer = wsServer,
        _initialStoragePath = storagePath,
        _storagePathResolver = storagePathResolver;

  final IServerDatabase _database;
  final WebSocketServer _wsServer;
  final String _initialStoragePath;
  final Future<String> Function()? _storagePathResolver;

  /// Called on the main isolate after each thumbnail is successfully generated.
  /// Receives the [mediaId] of the completed item.
  void Function(int mediaId)? onThumbnailReady;

  final Queue<int> _priorityQueue = Queue<int>();
  final Queue<int> _normalQueue = Queue<int>();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _receivePort;

  bool _processing = false;
  bool _started = false;

  Future<String> _currentStoragePath() async {
    final resolved = await _storagePathResolver?.call();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return _initialStoragePath;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Spawns the background isolate and starts processing.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _thumbnailWorkerEntry,
      _receivePort!.sendPort,
    );

    // First message is the worker's SendPort; subsequent messages are results.
    final completer = Completer<SendPort>();
    _receivePort!.listen((message) {
      if (!completer.isCompleted && message is SendPort) {
        _workerSendPort = message;
        completer.complete(message);
      } else if (message is _ThumbnailResult) {
        _onResult(message);
      }
    });

    await completer.future;
  }

  /// Stops the background isolate.
  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _workerSendPort = null;
    _started = false;
    _processing = false;
  }

  // ---------------------------------------------------------------------------
  // IThumbnailQueue
  // ---------------------------------------------------------------------------

  @override
  void enqueue(int mediaId) {
    _normalQueue.addLast(mediaId);
    _scheduleNext();
  }

  /// Moves [mediaId] to the front of the priority queue.
  @override
  void enqueuePriority(int mediaId) {
    // Remove from normal queue if present to avoid duplicate processing.
    _normalQueue.remove(mediaId);
    // Insert at front of priority queue.
    _priorityQueue.addFirst(mediaId);
    _scheduleNext();
  }

  // ---------------------------------------------------------------------------
  // Internal processing
  // ---------------------------------------------------------------------------

  void _scheduleNext() {
    if (_processing || _workerSendPort == null) return;
    if (_priorityQueue.isEmpty && _normalQueue.isEmpty) return;

    final mediaId = _priorityQueue.isNotEmpty
        ? _priorityQueue.removeFirst()
        : _normalQueue.removeFirst();

    _dispatchTask(mediaId);
  }

  Future<void> _dispatchTask(int mediaId) async {
    _processing = true;

    final item = await _database.getMediaItem(mediaId);
    if (item == null) {
      _processing = false;
      _scheduleNext();
      return;
    }

    final storagePath = await _currentStoragePath();
    final thumbnailPath = p.join(
      storagePath,
      '.thumbnails',
      item.deviceId,
      item.albumName,
      '${p.basenameWithoutExtension(item.fileName)}.jpg',
    );

    final task = _ThumbnailTask(
      mediaId: mediaId,
      filePath: item.filePath,
      mediaType: item.mediaType,
      thumbnailPath: thumbnailPath,
    );

    _workerSendPort!.send(task);
  }

  Future<void> _onResult(_ThumbnailResult result) async {
    _processing = false;

    final item = await _database.getMediaItem(result.mediaId);
    if (item != null) {
      if (result.success) {
        // Update DB with thumbnail path and ready status.
        await _updateThumbnail(
          mediaId: result.mediaId,
          thumbnailPath: result.thumbnailPath,
          status: 'ready',
        );

        // Push thumbnail_ready WebSocket event to the owning device.
        _wsServer.broadcast(
          item.deviceId,
          WsMessage(
            type: WsEventType.thumbnailReady,
            data: {
              'media_id': result.mediaId,
              'thumbnail_url': '/api/v1/media/${result.mediaId}/thumbnail',
            },
          ),
        );

        // Notify the local UI to refresh.
        onThumbnailReady?.call(result.mediaId);
      } else {
        await _updateThumbnail(
          mediaId: result.mediaId,
          thumbnailPath: result.thumbnailPath,
          status: 'failed',
        );
      }
    }

    _scheduleNext();
  }

  Future<void> _updateThumbnail({
    required int mediaId,
    required String thumbnailPath,
    required String status,
  }) async {
    await _database.updateThumbnail(
      mediaId: mediaId,
      thumbnailPath: thumbnailPath,
      thumbnailStatus: status,
    );
  }
}
