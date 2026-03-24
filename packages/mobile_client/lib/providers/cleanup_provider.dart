import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../database/mobile_database.dart';

/// Lifecycle states for the cleanup flow.
enum CleanupStatus { idle, calculating, confirming, cleaning, done, error }

/// ChangeNotifier that manages the photo cleanup flow.
///
/// Flow:
///   idle → calculateEligible → confirming → confirmCleanup → done
class CleanupProvider extends ChangeNotifier {
  CleanupStatus _status = CleanupStatus.idle;
  int _eligibleCount = 0;
  int _eligibleSize = 0;
  int _cleanedCount = 0;
  int _cleanedSize = 0;
  List<String> _failedFiles = [];
  String? _errorMessage;

  // Progress during calculating phase
  int _scanTotal = 0;
  int _scanDone = 0;

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  CleanupStatus get status => _status;
  int get eligibleCount => _eligibleCount;
  int get eligibleSize => _eligibleSize;
  int get cleanedCount => _cleanedCount;
  int get cleanedSize => _cleanedSize;
  List<String> get failedFiles => List.unmodifiable(_failedFiles);
  String? get errorMessage => _errorMessage;

  /// Total records to scan (only meaningful during [CleanupStatus.calculating]).
  int get scanTotal => _scanTotal;

  /// Records scanned so far (only meaningful during [CleanupStatus.calculating]).
  int get scanDone => _scanDone;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Queries upload_records for completed uploads and updates eligible counts.
  Future<void> calculateEligible(String serverId) async {
    _setStatus(CleanupStatus.calculating);
    try {
      final db = MobileDatabase();
      final count = await db.uploadRecordsDao.countCompleted(serverId);
      var size = await db.uploadRecordsDao.sumCompletedSize(serverId);

      // If all file_size values are 0 (legacy records), try to get real sizes
      // from the device asset library.
      if (size == 0 && count > 0) {
        size = await _estimateSizeFromAssets(db, serverId);
      }

      _eligibleCount = count;
      _eligibleSize = size;
      _setStatus(CleanupStatus.confirming);
    } catch (e) {
      _errorMessage = e.toString();
      _setStatus(CleanupStatus.error);
    }
  }

  /// Falls back to querying AssetEntity for file sizes when DB has zeros.
  Future<int> _estimateSizeFromAssets(MobileDatabase db, String serverId) async {
    try {
      final records = await db.uploadRecordsDao.getCompletedRecords(serverId);
      int total = 0;
      for (final record in records) {
        final storedSize = (record['file_size'] as int?) ?? 0;
        if (storedSize > 0) {
          total += storedSize;
          continue;
        }
        final localAssetId = record['local_asset_id'] as String?;
        if (localAssetId == null) continue;
        final asset = await AssetEntity.fromId(localAssetId);
        if (asset == null) continue;
        final file = await asset.originFile;
        if (file != null) {
          total += await file.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Transitions to confirming state (dialog is shown by the UI layer).
  Future<void> startCleanup(String serverId) async {
    if (_eligibleCount == 0) {
      await calculateEligible(serverId);
    } else {
      _setStatus(CleanupStatus.confirming);
    }
  }

  /// Executes the actual deletion after user confirmation.
  Future<void> confirmCleanup(String serverId) async {
    _setStatus(CleanupStatus.cleaning);
    _cleanedCount = 0;
    _cleanedSize = 0;
    _failedFiles = [];

    try {
      final db = MobileDatabase();
      final records = await db.uploadRecordsDao.getCompletedRecords(serverId);

      // Collect all valid asset IDs and their metadata first.
      final assetIds = <String>[];
      final sizeByAssetId = <String, int>{};
      final nameByAssetId = <String, String>{};

      for (final record in records) {
        final localAssetId = record['local_asset_id'] as String?;
        final fileName = record['file_name'] as String? ?? localAssetId ?? '';
        final fileSize = (record['file_size'] as int?) ?? 0;

        if (localAssetId == null) {
          _failedFiles.add(fileName);
          continue;
        }

        final asset = await AssetEntity.fromId(localAssetId);
        if (asset == null) {
          // Already gone — count as cleaned without needing deletion.
          _cleanedCount++;
          _cleanedSize += fileSize;
          notifyListeners();
          continue;
        }

        // Avoid duplicate asset IDs (same asset in multiple records).
        if (!assetIds.contains(localAssetId)) {
          assetIds.add(localAssetId);
          sizeByAssetId[localAssetId] = fileSize;
          nameByAssetId[localAssetId] = fileName;
        }
      }

      // One batch delete → Android shows a single system confirmation dialog.
      if (assetIds.isNotEmpty) {
        final deleted = await PhotoManager.editor.deleteWithIds(assetIds);
        final deletedFromDb = <String>[];
        for (final id in assetIds) {
          if (deleted.contains(id)) {
            _cleanedCount++;
            _cleanedSize += sizeByAssetId[id] ?? 0;
            deletedFromDb.add(id);
          } else {
            _failedFiles.add(nameByAssetId[id] ?? id);
          }
        }
        // Remove cleaned records from DB so eligible count reflects reality.
        if (deletedFromDb.isNotEmpty) {
          await db.uploadRecordsDao.deleteByAssetIds(deletedFromDb);
        }
        notifyListeners();
      }

      // Refresh eligible count — should be 0 if all cleaned, or remaining failures.
      _eligibleCount = await db.uploadRecordsDao.countCompleted(serverId);
      _eligibleSize = await db.uploadRecordsDao.sumCompletedSize(serverId);

      _setStatus(CleanupStatus.done);
    } catch (e) {
      _errorMessage = e.toString();
      _setStatus(CleanupStatus.error);
    }
  }

  /// Resets provider back to idle state.
  void reset() {
    _status = CleanupStatus.idle;
    _eligibleCount = 0;
    _eligibleSize = 0;
    _cleanedCount = 0;
    _cleanedSize = 0;
    _failedFiles = [];
    _errorMessage = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _setStatus(CleanupStatus s) {
    _status = s;
    notifyListeners();
  }
}
