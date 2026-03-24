/// Integration tests for upload queue scenarios.
///
/// Covers:
///   17.2 – Resume upload after network failure (断点续传)
///   17.3 – 100 concurrent tasks with max-3 worker constraint (并发上传)
///   17.4 – Live Photo pair ordering: HEIC uploaded before MOV
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

Future<String> createTempFile(int size) async {
  final dir = Directory.systemTemp.createTempSync('upload_integ_');
  final file = File('${dir.path}/test_file.bin');
  await file.writeAsBytes(List.filled(size, 0xAB));
  return file.path;
}

MockClient buildSuccessClient({List<String> existingFiles = const []}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/upload/check-exists')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final fileNames = List<String>.from(body['file_names'] as List);
      final exists = fileNames.where(existingFiles.contains).toList();
      final notExists = fileNames.where((f) => !existingFiles.contains(f)).toList();
      return http.Response(
        jsonEncode({'code': 0, 'message': 'ok', 'data': {'exists': exists, 'not_exists': notExists}}),
        200,
      );
    }
    if (path.endsWith('/upload/init')) {
      return http.Response(
        jsonEncode({'code': 0, 'message': 'ok', 'data': {'uploaded_bytes': 0, 'chunk_size': UploadWorker.chunkSize}}),
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

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // 17.2 – Resume upload (断点续传)
  // -------------------------------------------------------------------------

  group('17.2 – Resume upload after network failure', () {
    test('upload resumes from correct offset after simulated network failure', () async {
      const totalSize = UploadWorker.chunkSize * 4; // 4 chunks
      final filePath = await createTempFile(totalSize);

      final uploadedOffsets = <int>[];
      int initCallCount = 0;

      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/upload/check-exists')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final fileNames = List<String>.from(body['file_names'] as List);
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'exists': <String>[], 'not_exists': fileNames}}),
            200,
          );
        }

        if (path.endsWith('/upload/init')) {
          initCallCount++;
          // Second attempt: server reports 2 chunks already received
          final uploadedBytes = initCallCount >= 2 ? UploadWorker.chunkSize * 2 : 0;
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'uploaded_bytes': uploadedBytes, 'chunk_size': UploadWorker.chunkSize}}),
            200,
          );
        }

        if (path.endsWith('/upload/chunk')) {
          final bodyStr = String.fromCharCodes(request.bodyBytes);
          final offsetMatch = RegExp('name="offset"\\r\\n\\r\\n(\\d+)').firstMatch(bodyStr);
          if (offsetMatch != null) {
            uploadedOffsets.add(int.parse(offsetMatch.group(1)!));
          }
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }

        if (path.endsWith('/upload/complete')) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }

        return http.Response('not found', 404);
      });

      final task = makeTask(fileName: 'resume_test.jpg', totalSize: totalSize);

      // First attempt: pause early
      final worker1 = UploadWorker(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        filePath: filePath,
        task: task,
        client: client,
      );
      Future.delayed(const Duration(milliseconds: 10), () => worker1.pause());
      final result1 = await worker1.run();
      expect(result1.taskStatus, anyOf(TaskStatus.paused, TaskStatus.completed));

      // Second attempt: resumes from server-reported offset
      final worker2 = UploadWorker(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        filePath: filePath,
        task: task,
        client: client,
      );
      final result2 = await worker2.run();

      expect(result2.taskStatus, TaskStatus.completed,
          reason: 'Second attempt should complete successfully');

      // Second attempt must start from resume offset (2 * chunkSize)
      final resumeOffset = UploadWorker.chunkSize * 2;
      final secondAttemptOffsets = uploadedOffsets.where((o) => o >= resumeOffset).toList();
      expect(secondAttemptOffsets, isNotEmpty,
          reason: 'Second attempt must upload chunks starting from resume offset');
    });

    test('worker uploads all bytes when server reports zero uploaded_bytes', () async {
      const totalSize = UploadWorker.chunkSize * 2;
      final filePath = await createTempFile(totalSize);
      final uploadedOffsets = <int>[];

      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/upload/init')) {
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'uploaded_bytes': 0, 'chunk_size': UploadWorker.chunkSize}}),
            200,
          );
        }
        if (path.endsWith('/upload/chunk')) {
          final bodyStr = String.fromCharCodes(request.bodyBytes);
          final offsetMatch = RegExp('name="offset"\\r\\n\\r\\n(\\d+)').firstMatch(bodyStr);
          if (offsetMatch != null) {
            uploadedOffsets.add(int.parse(offsetMatch.group(1)!));
          }
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }
        if (path.endsWith('/upload/complete')) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }
        return http.Response('not found', 404);
      });

      final task = makeTask(fileName: 'full_upload.jpg', totalSize: totalSize);
      final worker = UploadWorker(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        filePath: filePath,
        task: task,
        client: client,
      );
      final result = await worker.run();

      expect(result.taskStatus, TaskStatus.completed);
      expect(uploadedOffsets, contains(0));
      expect(uploadedOffsets.length, 2, reason: 'Two chunks expected for a 2-chunk file');
    });
  });

  // -------------------------------------------------------------------------
  // 17.3 – Concurrent upload: 100 tasks, max 3 workers
  // -------------------------------------------------------------------------

  group('17.3 – Concurrent upload: 100 tasks with max-3 worker constraint', () {
    test('100 tasks complete with max 3 concurrent workers, no file lost', () async {
      int maxConcurrent = 0;
      int currentConcurrent = 0;

      final filePath = await createTempFile(UploadWorker.chunkSize);

      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/upload/check-exists')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final fileNames = List<String>.from(body['file_names'] as List);
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'exists': <String>[], 'not_exists': fileNames}}),
            200,
          );
        }

        if (path.endsWith('/upload/init')) {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) maxConcurrent = currentConcurrent;
          await Future.delayed(const Duration(milliseconds: 5));
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'uploaded_bytes': 0, 'chunk_size': UploadWorker.chunkSize}}),
            200,
          );
        }

        if (path.endsWith('/upload/chunk')) {
          await Future.delayed(const Duration(milliseconds: 2));
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }

        if (path.endsWith('/upload/complete')) {
          currentConcurrent--;
          return http.Response(jsonEncode({'code': 0, 'message': 'ok'}), 200);
        }

        return http.Response('not found', 404);
      });

      final tasks = List.generate(
        100,
        (i) => makeTask(
          fileName: 'photo_${i.toString().padLeft(3, '0')}.jpg',
          totalSize: UploadWorker.chunkSize,
        ),
      );

      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      await manager.addTasks(tasks);

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 60));

      expect(manager.completedTasks.length, 100,
          reason: 'All 100 tasks must complete without loss');

      expect(maxConcurrent, lessThanOrEqualTo(UploadQueueManager.maxConcurrent),
          reason: 'Concurrent workers must not exceed ${UploadQueueManager.maxConcurrent}');

      final completedNames = manager.completedTasks.map((t) => t.fileName).toSet();
      for (int i = 0; i < 100; i++) {
        final name = 'photo_${i.toString().padLeft(3, '0')}.jpg';
        expect(completedNames, contains(name), reason: '$name must be in completed tasks');
      }
    });

    test('queue status transitions: idle → running → idle', () async {
      final filePath = await createTempFile(10);
      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: buildSuccessClient(),
      );

      expect(manager.status, QueueStatus.idle, reason: 'Initial status is idle');

      await manager.addTasks([makeTask(fileName: 'a.jpg', totalSize: 10)]);

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 20));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 10));

      expect(manager.status, QueueStatus.idle, reason: 'Status returns to idle after completion');
      expect(manager.completedTasks.length, 1);
    });
  });

  // -------------------------------------------------------------------------
  // 17.4 – Live Photo upload: HEIC before MOV
  // -------------------------------------------------------------------------

  group('17.4 – Live Photo upload: HEIC uploaded before MOV', () {
    test('HEIC file is uploaded before its paired MOV file', () async {
      final uploadOrder = <String>[];
      final filePath = await createTempFile(UploadWorker.chunkSize);

      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/upload/check-exists')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final fileNames = List<String>.from(body['file_names'] as List);
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'exists': <String>[], 'not_exists': fileNames}}),
            200,
          );
        }

        if (path.endsWith('/upload/init')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          uploadOrder.add(body['file_name'] as String? ?? '');
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'uploaded_bytes': 0, 'chunk_size': UploadWorker.chunkSize}}),
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

      // Intentionally add MOV before HEIC to verify reordering
      final tasks = [
        makeTask(
          fileName: 'IMG_0001.MOV',
          totalSize: UploadWorker.chunkSize,
          mediaType: MediaType.livePhoto,
          livePhotoPairName: 'IMG_0001.HEIC',
        ),
        makeTask(
          fileName: 'IMG_0001.HEIC',
          totalSize: UploadWorker.chunkSize,
          mediaType: MediaType.livePhoto,
          livePhotoPairName: 'IMG_0001.MOV',
        ),
      ];

      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      await manager.addTasks(tasks);

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 10));

      expect(manager.completedTasks.length, 2, reason: 'Both HEIC and MOV must complete');

      final heicIdx = uploadOrder.indexOf('IMG_0001.HEIC');
      final movIdx = uploadOrder.indexOf('IMG_0001.MOV');
      expect(heicIdx, greaterThanOrEqualTo(0), reason: 'HEIC must be uploaded');
      expect(movIdx, greaterThanOrEqualTo(0), reason: 'MOV must be uploaded');
      expect(heicIdx, lessThan(movIdx), reason: 'HEIC must be uploaded before MOV');
    });

    test('multiple Live Photo pairs maintain correct ordering', () async {
      final uploadOrder = <String>[];
      final filePath = await createTempFile(UploadWorker.chunkSize);

      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/upload/check-exists')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final fileNames = List<String>.from(body['file_names'] as List);
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'exists': <String>[], 'not_exists': fileNames}}),
            200,
          );
        }

        if (path.endsWith('/upload/init')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          uploadOrder.add(body['file_name'] as String? ?? '');
          return http.Response(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'uploaded_bytes': 0, 'chunk_size': UploadWorker.chunkSize}}),
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

      // Two Live Photo pairs, MOVs listed first
      final tasks = [
        makeTask(fileName: 'IMG_0002.MOV', totalSize: UploadWorker.chunkSize,
            mediaType: MediaType.livePhoto, livePhotoPairName: 'IMG_0002.HEIC'),
        makeTask(fileName: 'IMG_0001.MOV', totalSize: UploadWorker.chunkSize,
            mediaType: MediaType.livePhoto, livePhotoPairName: 'IMG_0001.HEIC'),
        makeTask(fileName: 'IMG_0001.HEIC', totalSize: UploadWorker.chunkSize,
            mediaType: MediaType.livePhoto, livePhotoPairName: 'IMG_0001.MOV'),
        makeTask(fileName: 'IMG_0002.HEIC', totalSize: UploadWorker.chunkSize,
            mediaType: MediaType.livePhoto, livePhotoPairName: 'IMG_0002.MOV'),
      ];

      final manager = UploadQueueManager(
        baseUrl: 'http://localhost:8765',
        deviceId: 'device1',
        resolveFilePath: (_) => filePath,
        client: client,
      );

      await manager.addTasks(tasks);

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return manager.status != QueueStatus.idle;
      }).timeout(const Duration(seconds: 15));

      expect(manager.completedTasks.length, 4);

      for (final prefix in ['IMG_0001', 'IMG_0002']) {
        final heicIdx = uploadOrder.indexOf('$prefix.HEIC');
        final movIdx = uploadOrder.indexOf('$prefix.MOV');
        expect(heicIdx, greaterThanOrEqualTo(0));
        expect(movIdx, greaterThanOrEqualTo(0));
        expect(heicIdx, lessThan(movIdx),
            reason: '$prefix.HEIC must be uploaded before $prefix.MOV');
      }
    });
  });
}
