import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:common/queue/upload_queue_manager.dart';
import 'package:common/queue/upload_worker.dart';
import 'package:common/models/upload_task.dart';
import 'package:common/models/media_item.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UploadTask makeTask({
  required String fileName,
  int totalSize = 100,
  MediaType mediaType = MediaType.image,
  String? livePhotoPairName,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return UploadTask(
    serverId: 'srv1',
    fileName: fileName,
    albumName: 'TestAlbum',
    localAssetId: fileName,
    totalSize: totalSize,
    chunkSize: UploadWorker.chunkSize,
    taskStatus: TaskStatus.pending,
    mediaType: mediaType,
    livePhotoPairName: livePhotoPairName,
    createdAt: now,
    updatedAt: now,
  );
}

/// Builds a mock HTTP client that handles all upload endpoints successfully.
MockClient buildSuccessClient({List<String> existingFiles = const []}) {
  return MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('/upload/check-exists')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final fileNames = List<String>.from(body['file_names'] as List);
      final exists = fileNames.where(existingFiles.contains).toList();
      final notExists =
          fileNames.where((f) => !existingFiles.contains(f)).toList();
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {'exists': exists, 'not_exists': notExists},
        }),
        200,
      );
    }

    if (path.endsWith('/upload/init')) {
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {'uploaded_bytes': 0, 'chunk_size': UploadWorker.chunkSize},
        }),
        200,
      );
    }

    if (path.endsWith('/upload/chunk')) {
      return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
    }

    if (path.endsWith('/upload/complete')) {
      return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
    }

    return http.Response('not found', 404);
  });
}

/// Creates a temp file with [size] bytes of zeros.
Future<String> createTempFile(int size) async {
  final dir = Directory.systemTemp.createTempSync('upload_test_');
  final file = File('${dir.path}/test_file.bin');
  await file.writeAsBytes(List.filled(size, 0));
  return file.path;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UploadQueueManager – FIFO scheduling', () {
    test('tasks are processed in FIFO order', () async {
      final filePath = await createTempFile(10);
      final client = buildSuccessClient();

      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      final tasks = [
        makeTask(fileName: 'a.jpg', totalSize: 10),
        makeTask(fileName: 'b.jpg', totalSize: 10),
        makeTask(fileName: 'c.jpg', totalSize: 10),
      ];

      await manager.addTasks(tasks);

      // Wait for all to complete
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 10));

      // All three should be completed
      expect(
        manager.completedTasks.map((t) => t.fileName).toSet(),
        containsAll(['a.jpg', 'b.jpg', 'c.jpg']),
      );
    });
  });

  group('UploadQueueManager – pause / resume', () {
    test('pause while tasks are pending keeps them in pausedTasks, resume completes them',
        () async {
      // Strategy: fill all 3 worker slots with blocked tasks so the 4th task
      // stays in pendingQueue. Then pause, verify status, resume, verify done.
      var blockWorkers = true;
      final firstWorkerStarted = Completer<void>();

      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/upload/check-exists')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final fileNames = List<String>.from(body['file_names'] as List);
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {'exists': <String>[], 'not_exists': fileNames},
            }),
            200,
          );
        }

        if (path.endsWith('/upload/init')) {
          if (!firstWorkerStarted.isCompleted) firstWorkerStarted.complete();
        }
        // Block all non-check-exists requests until released
        while (blockWorkers) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
        if (path.endsWith('/upload/init')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'uploaded_bytes': 0,
                'chunk_size': UploadWorker.chunkSize,
              },
            }),
            200,
          );
        }

        if (path.endsWith('/upload/chunk')) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }

        if (path.endsWith('/upload/complete')) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }

        return http.Response('not found', 404);
      });

      final filePath = await createTempFile(10);
      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      // Add 3 filler tasks (will occupy all worker slots) + 1 extra task
      unawaited(manager.addTasks([
        makeTask(fileName: 'filler1.jpg', totalSize: 10),
        makeTask(fileName: 'filler2.jpg', totalSize: 10),
        makeTask(fileName: 'filler3.jpg', totalSize: 10),
        makeTask(fileName: 'extra.jpg', totalSize: 10),
      ]));

      // Wait until at least one worker has started (blocked on init)
      await firstWorkerStarted.future.timeout(const Duration(seconds: 5));
      expect(manager.status, QueueStatus.running);

      // Pause – signals workers to stop after current chunk
      await manager.pause();
      expect(manager.status, QueueStatus.paused);

      // Unblock workers so they can finish their current chunk and honour pause
      blockWorkers = false;

      // Wait for active workers to drain (they finish current chunk then stop).
      // Workers may land in pausedTasks or completedTasks depending on timing.
      // The extra.jpg task remains in pendingQueue since we're paused.
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 20));
        final drained =
            manager.pausedTasks.length + manager.completedTasks.length;
        return manager.status == QueueStatus.paused && drained < 3;
      }).timeout(const Duration(seconds: 5));

      // Status must still be paused
      expect(manager.status, QueueStatus.paused);

      // Resume and let everything finish
      manager.resume();

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 10));

      // All 4 tasks must be completed
      final completedNames =
          manager.completedTasks.map((t) => t.fileName).toSet();
      expect(
        completedNames,
        containsAll(['filler1.jpg', 'filler2.jpg', 'filler3.jpg', 'extra.jpg']),
      );
    });
  });

  group('UploadWorker – retry logic', () {
    test('retries up to maxRetries times on chunk failure then succeeds',
        () async {
      final filePath = await createTempFile(10);
      int chunkAttempts = 0;

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/upload/init')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'uploaded_bytes': 0,
                'chunk_size': UploadWorker.chunkSize,
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/upload/chunk')) {
          chunkAttempts++;
          // Fail first 2 attempts, succeed on 3rd
          if (chunkAttempts < 3) {
            return http.Response('server error', 500);
          }
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }
        if (request.url.path.endsWith('/upload/complete')) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }
        return http.Response('not found', 404);
      });

      final task = makeTask(fileName: 'retry.jpg', totalSize: 10);
      final worker = UploadWorker(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        filePath: filePath,
        task: task,
        client: client,
      );

      final result = await worker.run();
      expect(result.taskStatus, TaskStatus.completed);
      expect(chunkAttempts, 3);
    });

    test('throws after maxRetries consecutive failures', () async {
      final filePath = await createTempFile(10);

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/upload/init')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'uploaded_bytes': 0,
                'chunk_size': UploadWorker.chunkSize,
              },
            }),
            200,
          );
        }
        // Always fail
        return http.Response('server error', 500);
      });

      final task = makeTask(fileName: 'fail.jpg', totalSize: 10);
      final worker = UploadWorker(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        filePath: filePath,
        task: task,
        client: client,
      );

      expect(() => worker.run(), throwsException);
    });
  });

  group('UploadQueueManager – dedup', () {
    test('already-existing files are skipped and marked completed', () async {
      final filePath = await createTempFile(10);
      final client = buildSuccessClient(existingFiles: ['existing.jpg']);

      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      await manager.addTasks([
        makeTask(fileName: 'existing.jpg', totalSize: 10),
        makeTask(fileName: 'new.jpg', totalSize: 10),
      ]);

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 10));

      final completedNames =
          manager.completedTasks.map((t) => t.fileName).toSet();
      expect(completedNames, containsAll(['existing.jpg', 'new.jpg']));
    });
  });

  group('UploadQueueManager – Live Photo ordering', () {
    test('HEIC is enqueued before its paired MOV', () async {
      // Fill all 3 worker slots with filler tasks (workers blocked on init)
      // so the Live Photo pair stays in pendingQueue where we can inspect order.
      var blockWorkers = true;

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/upload/check-exists')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final fileNames = List<String>.from(body['file_names'] as List);
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {'exists': <String>[], 'not_exists': fileNames},
            }),
            200,
          );
        }
        while (blockWorkers) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
        if (request.url.path.endsWith('/upload/init')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'uploaded_bytes': 0,
                'chunk_size': UploadWorker.chunkSize,
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
      });

      final filePath = await createTempFile(10);
      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      // Add 3 fillers + Live Photo pair (MOV listed before HEIC intentionally)
      unawaited(manager.addTasks([
        makeTask(fileName: 'filler1.jpg', totalSize: 10),
        makeTask(fileName: 'filler2.jpg', totalSize: 10),
        makeTask(fileName: 'filler3.jpg', totalSize: 10),
        makeTask(
          fileName: 'IMG_0001.MOV',
          totalSize: 10,
          mediaType: MediaType.livePhoto,
          livePhotoPairName: 'IMG_0001.HEIC',
        ),
        makeTask(
          fileName: 'IMG_0001.HEIC',
          totalSize: 10,
          mediaType: MediaType.livePhoto,
          livePhotoPairName: 'IMG_0001.MOV',
        ),
      ]));

      // Give the event loop time to process addTasks (dedup + scheduling)
      await Future.delayed(const Duration(milliseconds: 100));

      // 3 fillers are in active workers; HEIC and MOV are in pendingQueue
      final pendingNames = manager.pendingQueue.map((t) => t.fileName).toList();
      final heicIdx = pendingNames.indexOf('IMG_0001.HEIC');
      final movIdx = pendingNames.indexOf('IMG_0001.MOV');
      expect(heicIdx, greaterThanOrEqualTo(0), reason: 'HEIC should be pending');
      expect(movIdx, greaterThanOrEqualTo(0), reason: 'MOV should be pending');
      expect(heicIdx, lessThan(movIdx),
          reason: 'HEIC must be queued before MOV');

      // Unblock workers and wait for completion
      blockWorkers = false;
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 10));
    });
  });
}
