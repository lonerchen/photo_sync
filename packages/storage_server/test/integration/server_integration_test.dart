/// Integration tests for storage server scenarios.
///
/// Covers:
///   17.6 – Database rebuild: delete DB file, restart, verify auto-scan rebuilds data
///   17.8 – Multi-device concurrency: two devices uploading simultaneously, data isolation
import 'dart:io';

import 'package:common/common.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:storage_server/database/server_database.dart';

// ---------------------------------------------------------------------------
// Setup helpers
// ---------------------------------------------------------------------------

int _dbCounter = 0;

Future<ServerDatabase> openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = ServerDatabase();
  // Use a unique in-memory path per test to avoid shared state
  await db.init(dbPath: 'file:test_db_${_dbCounter++}?mode=memory&cache=shared');
  return db;
}

Future<Directory> buildStorageTree({
  required String deviceName,
  required String deviceId,
  required String albumName,
  required List<String> fileNames,
}) async {
  final root = Directory.systemTemp.createTempSync('srv_integ_');
  final albumDir = Directory(p.join(root.path, '${deviceName}_$deviceId', albumName));
  await albumDir.create(recursive: true);
  for (final name in fileNames) {
    await File(p.join(albumDir.path, name)).writeAsBytes(List.filled(1024, 0xFF));
  }
  return root;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // 17.6 – Database rebuild
  // -------------------------------------------------------------------------

  group('17.6 – Database rebuild from storage directory', () {
    test('rebuild scans directory structure and recreates media_items records', () async {
      final root = await buildStorageTree(
        deviceName: 'iPhone15',
        deviceId: 'device-abc-123',
        albumName: 'Camera Roll',
        fileNames: ['IMG_0001.HEIC', 'IMG_0002.HEIC', 'IMG_0003.MOV', 'IMG_0004.jpg'],
      );

      try {
        final db = await openTestDb();

        int scannedCount = 0;
        await db.rebuildFromStorage(
          root.path,
          onProgress: (scanned, estimated) => scannedCount = scanned,
        );

        // Device must be registered
        final device = await db.getDevice('device-abc-123');
        expect(device, isNotNull, reason: 'Device must be registered after rebuild');
        expect(device!.deviceName, 'iPhone15');

        // All 4 files must be indexed
        final result = await db.getMediaItems(
          deviceId: 'device-abc-123',
          albumName: 'Camera Roll',
          page: 1,
          pageSize: 50,
        );
        expect(result.total, 4, reason: 'All 4 files must be indexed after rebuild');
        expect(result.items.length, 4);

        // All thumbnail_status must be 'pending'
        for (final item in result.items) {
          expect(item.thumbnailStatus, ThumbnailStatus.pending,
              reason: 'thumbnail_status must be pending after rebuild');
        }

        // File names must be correct
        final indexedNames = result.items.map((i) => i.fileName).toSet();
        expect(indexedNames, containsAll(['IMG_0001.HEIC', 'IMG_0002.HEIC', 'IMG_0003.MOV', 'IMG_0004.jpg']));

        // Progress callback must have been called
        expect(scannedCount, 4, reason: 'Progress callback must report 4 scanned files');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('rebuild is idempotent: running twice does not duplicate records', () async {
      final root = await buildStorageTree(
        deviceName: 'iPad',
        deviceId: 'device-ipad-456',
        albumName: 'Favorites',
        fileNames: ['photo1.jpg', 'photo2.jpg'],
      );

      try {
        final db = await openTestDb();

        await db.rebuildFromStorage(root.path);
        await db.rebuildFromStorage(root.path); // second run

        final result = await db.getMediaItems(
          deviceId: 'device-ipad-456',
          albumName: 'Favorites',
          page: 1,
          pageSize: 50,
        );
        expect(result.total, 2, reason: 'Idempotent rebuild must not duplicate records');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('rebuild handles empty storage directory gracefully', () async {
      final root = Directory.systemTemp.createTempSync('srv_empty_');
      try {
        final db = await openTestDb();
        await expectLater(db.rebuildFromStorage(root.path), completes);
        final devices = await db.getAllDevices();
        expect(devices, isEmpty);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('rebuild handles multiple devices in storage directory', () async {
      final root = Directory.systemTemp.createTempSync('srv_multi_');
      try {
        for (final entry in [
          ('iPhone_dev1', 'Album1', ['a.jpg', 'b.jpg']),
          ('Android_dev2', 'Album2', ['c.jpg', 'd.jpg', 'e.jpg']),
        ]) {
          final (deviceDir, album, files) = entry;
          final albumDir = Directory(p.join(root.path, deviceDir, album));
          await albumDir.create(recursive: true);
          for (final f in files) {
            await File(p.join(albumDir.path, f)).writeAsBytes([0]);
          }
        }

        final db = await openTestDb();
        await db.rebuildFromStorage(root.path);

        final devices = await db.getAllDevices();
        expect(devices.length, 2, reason: 'Two devices must be registered');

        final dev1Items = await db.getMediaItems(
          deviceId: 'dev1',
          albumName: 'Album1',
          page: 1,
          pageSize: 50,
        );
        expect(dev1Items.total, 2);

        final dev2Items = await db.getMediaItems(
          deviceId: 'dev2',
          albumName: 'Album2',
          page: 1,
          pageSize: 50,
        );
        expect(dev2Items.total, 3);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });

  // -------------------------------------------------------------------------
  // 17.8 – Multi-device concurrency and data isolation
  // -------------------------------------------------------------------------

  group('17.8 – Multi-device concurrent upload: data isolation', () {
    test('two devices uploading simultaneously do not interfere with each other', () async {
      final db = await openTestDb();

      await db.registerDevice(
        deviceId: 'phone-A',
        deviceName: 'Alice iPhone',
        platform: 'ios',
        storagePath: '/storage/phone-A',
      );
      await db.registerDevice(
        deviceId: 'phone-B',
        deviceName: 'Bob Android',
        platform: 'android',
        storagePath: '/storage/phone-B',
      );

      // Concurrent inserts from both devices
      final futures = <Future>[];
      for (int i = 0; i < 10; i++) {
        futures.add(db.insertMediaItem(
          deviceId: 'phone-A',
          fileName: 'alice_photo_$i.jpg',
          albumName: 'Camera Roll',
          filePath: '/storage/phone-A/Camera Roll/alice_photo_$i.jpg',
          fileSize: 1024 * (i + 1),
          mediaType: MediaType.image,
        ));
        futures.add(db.insertMediaItem(
          deviceId: 'phone-B',
          fileName: 'bob_photo_$i.jpg',
          albumName: 'Camera Roll',
          filePath: '/storage/phone-B/Camera Roll/bob_photo_$i.jpg',
          fileSize: 2048 * (i + 1),
          mediaType: MediaType.image,
        ));
      }
      await Future.wait(futures);

      // Alice sees only her photos
      final aliceResult = await db.getMediaItems(
        deviceId: 'phone-A',
        albumName: 'Camera Roll',
        page: 1,
        pageSize: 50,
      );
      expect(aliceResult.total, 10, reason: 'Alice must have exactly 10 photos');
      for (final item in aliceResult.items) {
        expect(item.deviceId, 'phone-A');
        expect(item.fileName, startsWith('alice_'));
      }

      // Bob sees only his photos
      final bobResult = await db.getMediaItems(
        deviceId: 'phone-B',
        albumName: 'Camera Roll',
        page: 1,
        pageSize: 50,
      );
      expect(bobResult.total, 10, reason: 'Bob must have exactly 10 photos');
      for (final item in bobResult.items) {
        expect(item.deviceId, 'phone-B');
        expect(item.fileName, startsWith('bob_'));
      }
    });

    test('dedup check is scoped per device: same filename on different devices is allowed', () async {
      final db = await openTestDb();

      await db.registerDevice(
        deviceId: 'dev-X',
        deviceName: 'Device X',
        platform: 'ios',
        storagePath: '/storage/dev-X',
      );
      await db.registerDevice(
        deviceId: 'dev-Y',
        deviceName: 'Device Y',
        platform: 'ios',
        storagePath: '/storage/dev-Y',
      );

      await db.insertMediaItem(
        deviceId: 'dev-X',
        fileName: 'IMG_0001.HEIC',
        albumName: 'Camera Roll',
        filePath: '/storage/dev-X/Camera Roll/IMG_0001.HEIC',
        fileSize: 4096,
        mediaType: MediaType.livePhoto,
      );
      await db.insertMediaItem(
        deviceId: 'dev-Y',
        fileName: 'IMG_0001.HEIC',
        albumName: 'Camera Roll',
        filePath: '/storage/dev-Y/Camera Roll/IMG_0001.HEIC',
        fileSize: 5120,
        mediaType: MediaType.livePhoto,
      );

      // Dedup check is scoped to device
      final existingX = await db.getExistingFileNames(
        deviceId: 'dev-X',
        albumName: 'Camera Roll',
        fileNames: ['IMG_0001.HEIC'],
      );
      expect(existingX, contains('IMG_0001.HEIC'));

      final existingY = await db.getExistingFileNames(
        deviceId: 'dev-Y',
        albumName: 'Camera Roll',
        fileNames: ['IMG_0001.HEIC'],
      );
      expect(existingY, contains('IMG_0001.HEIC'));

      // Two separate records exist (one per device)
      final xResult = await db.getMediaItems(
        deviceId: 'dev-X', albumName: 'Camera Roll', page: 1, pageSize: 10,
      );
      final yResult = await db.getMediaItems(
        deviceId: 'dev-Y', albumName: 'Camera Roll', page: 1, pageSize: 10,
      );
      expect(xResult.total, 1);
      expect(yResult.total, 1);
      expect(xResult.items.first.fileSize, 4096);
      expect(yResult.items.first.fileSize, 5120);
    });

    test('transfer task state is isolated per device', () async {
      final db = await openTestDb();

      await db.registerDevice(
        deviceId: 'dev-1',
        deviceName: 'Phone 1',
        platform: 'ios',
        storagePath: '/storage/dev-1',
      );
      await db.registerDevice(
        deviceId: 'dev-2',
        deviceName: 'Phone 2',
        platform: 'android',
        storagePath: '/storage/dev-2',
      );

      await db.upsertTransferTask(
        deviceId: 'dev-1',
        fileName: 'video.mov',
        albumName: 'Videos',
        totalSize: 10000,
        uploadedBytes: 3000,
        tempFilePath: '/tmp/dev-1/video.mov.tmp',
        taskStatus: 'uploading',
        mediaType: MediaType.video,
      );
      await db.upsertTransferTask(
        deviceId: 'dev-2',
        fileName: 'video.mov',
        albumName: 'Videos',
        totalSize: 10000,
        uploadedBytes: 7000,
        tempFilePath: '/tmp/dev-2/video.mov.tmp',
        taskStatus: 'uploading',
        mediaType: MediaType.video,
      );

      final bytes1 = await db.getUploadedBytes(
        deviceId: 'dev-1', fileName: 'video.mov', albumName: 'Videos',
      );
      final bytes2 = await db.getUploadedBytes(
        deviceId: 'dev-2', fileName: 'video.mov', albumName: 'Videos',
      );

      expect(bytes1, 3000, reason: 'dev-1 resume offset must be 3000');
      expect(bytes2, 7000, reason: 'dev-2 resume offset must be 7000');
    });
  });
}
