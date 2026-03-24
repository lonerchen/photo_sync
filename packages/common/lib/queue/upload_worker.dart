import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/upload_task.dart';
import '../protocol/api_dtos.dart';

/// Callback reporting progress: (uploadedBytes, totalBytes).
typedef ProgressCallback = void Function(int uploadedBytes, int totalBytes);

/// Handles chunked upload of a single file with resume and retry support.
class UploadWorker {
  static const int chunkSize = 512 * 1024; // 512 KB
  static const int maxRetries = 3;

  final String baseUrl;
  final String deviceId;
  final String filePath;
  final UploadTask task;
  final ProgressCallback? onProgress;
  final http.Client _client;

  bool _paused = false;
  bool _completed = false;

  UploadWorker({
    required this.baseUrl,
    required this.deviceId,
    required this.filePath,
    required this.task,
    this.onProgress,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Signals the worker to stop after the current chunk completes.
  void pause() => _paused = true;

  bool get isCompleted => _completed;

  /// Runs the upload. Returns the final [UploadTask] with updated status.
  Future<UploadTask> run() async {
    debugPrint('[Worker] start: ${task.fileName}, filePath=$filePath');
    // Resolve actual file size before anything else.
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[Worker] file not found: $filePath');
      return task.copyWith(
        taskStatus: TaskStatus.failed,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    final totalSize = await file.length();
    debugPrint('[Worker] file size: $totalSize bytes for ${task.fileName}');

    // Step 1: init – get resume offset from server
    final initReq = UploadInitRequest(
      deviceId: deviceId,
      fileName: task.fileName,
      albumName: task.albumName,
      totalSize: totalSize,
      mediaType: task.mediaType,
      livePhotoPairName: task.livePhotoPairName,
    );

    debugPrint('[Worker] calling init for ${task.fileName}');
    final initResp = await _retryRequest(() => _postInit(initReq));
    int offset = initResp.uploadedBytes;
    debugPrint('[Worker] init ok, resume offset=$offset for ${task.fileName}');

    // Step 2: upload chunks
    final raf = await file.open(mode: FileMode.read);
    int chunkIndex = 0;
    try {
      await raf.setPosition(offset);

      while (offset < totalSize) {
        if (_paused) {
          debugPrint('[Worker] paused at offset=$offset for ${task.fileName}');
          return task.copyWith(
            uploadedBytes: offset,
            taskStatus: TaskStatus.paused,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }

        final remaining = totalSize - offset;
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        final chunk = await raf.read(toRead);

        debugPrint('[Worker] chunk #$chunkIndex offset=$offset size=${chunk.length} for ${task.fileName}');
        await _retryRequest(() => _postChunk(offset, chunk));

        offset += chunk.length;
        chunkIndex++;
        onProgress?.call(offset, totalSize);
        debugPrint('[Worker] progress $offset/$totalSize for ${task.fileName}');
      }
    } finally {
      await raf.close();
    }

    debugPrint('[Worker] all chunks done, calling complete for ${task.fileName}');
    // Step 3: complete
    final completeReq = UploadCompleteRequest(
      deviceId: deviceId,
      fileName: task.fileName,
      albumName: task.albumName,
      totalSize: totalSize,
    );
    await _retryRequest(() => _postComplete(completeReq));

    debugPrint('[Worker] complete ok for ${task.fileName}');
    _completed = true;
    return task.copyWith(
      uploadedBytes: totalSize,
      taskStatus: TaskStatus.completed,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<T> _retryRequest<T>(Future<T> Function() fn) async {
    int attempts = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempts++;
        debugPrint('[Worker] request failed (attempt $attempts/$maxRetries): $e for ${task.fileName}');
        if (attempts >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  Future<UploadInitResponse> _postInit(UploadInitRequest req) async {
    final uri = Uri.parse('$baseUrl/api/v1/upload/init');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req.toJson()),
    );
    _assertSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final apiResp = ApiResponse.fromJson(
      body,
      (d) => UploadInitResponse.fromJson(d as Map<String, dynamic>),
    );
    if (!apiResp.isSuccess) {
      throw Exception('upload/init failed: ${apiResp.message}');
    }
    return apiResp.data!;
  }

  Future<void> _postChunk(int offset, List<int> chunk) async {
    final uri = Uri.parse('$baseUrl/api/v1/upload/chunk');
    final request = http.MultipartRequest('POST', uri)
      ..fields['device_id'] = deviceId
      ..fields['file_name'] = task.fileName
      ..fields['album_name'] = task.albumName
      ..fields['offset'] = offset.toString()
      ..files.add(
        http.MultipartFile.fromBytes('chunk', chunk, filename: task.fileName),
      );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _assertSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final apiResp = ApiResponse<void>.fromJson(body, null);
    if (!apiResp.isSuccess) {
      throw Exception('upload/chunk failed at offset $offset: ${apiResp.message}');
    }
  }

  Future<void> _postComplete(UploadCompleteRequest req) async {
    final uri = Uri.parse('$baseUrl/api/v1/upload/complete');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req.toJson()),
    );
    _assertSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final apiResp = ApiResponse<void>.fromJson(body, null);
    if (!apiResp.isSuccess) {
      throw Exception('upload/complete failed: ${apiResp.message}');
    }
  }

  void _assertSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
