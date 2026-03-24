import 'dart:io';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../platform/live_photo_channel.dart';

/// Lifecycle states for the restore flow.
enum RestoreStatus { idle, restoring, done, error }

/// ChangeNotifier that manages multi-select and restore of media items.
///
/// Covers tasks 16.1 – 16.6:
///   - Multi-select (toggle / selectAll / clearSelection)
///   - Download + save image / video via photo_manager
///   - Download + save Live Photo via LivePhotoChannel (iOS)
///   - Progress tracking (restoredCount / totalCount / failedFiles)
class RestoreProvider extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Selection state (16.1)
  // ---------------------------------------------------------------------------

  final Set<int> _selectedIds = {};

  Set<int> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;

  void toggleSelection(int mediaId) {
    if (_selectedIds.contains(mediaId)) {
      _selectedIds.remove(mediaId);
    } else {
      _selectedIds.add(mediaId);
    }
    notifyListeners();
  }

  void selectAll(List<MediaItem> items) {
    _selectedIds.addAll(items.map((e) => e.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Restore state (16.2 – 16.6)
  // ---------------------------------------------------------------------------

  RestoreStatus _status = RestoreStatus.idle;
  int _restoredCount = 0;
  int _totalCount = 0;
  final List<String> _failedFiles = [];
  String? _errorMessage;

  RestoreStatus get status => _status;
  int get restoredCount => _restoredCount;
  int get totalCount => _totalCount;
  List<String> get failedFiles => List.unmodifiable(_failedFiles);
  String? get errorMessage => _errorMessage;

  // ---------------------------------------------------------------------------
  // Restore logic
  // ---------------------------------------------------------------------------

  /// Downloads and saves each selected [MediaItem] to the system photo library.
  ///
  /// [serverBaseUrl] – e.g. `http://192.168.1.1:8765`
  /// [allItems]      – full list so we can look up Live Photo pairs by name.
  Future<void> restore(
    String serverBaseUrl,
    List<MediaItem> allItems,
  ) async {
    if (_selectedIds.isEmpty) return;

    final selected =
        allItems.where((e) => _selectedIds.contains(e.id)).toList();

    _status = RestoreStatus.restoring;
    _restoredCount = 0;
    _totalCount = selected.length;
    _failedFiles.clear();
    _errorMessage = null;
    notifyListeners();

    final tmpDir = await getTemporaryDirectory();

    for (final item in selected) {
      try {
        await _restoreItem(item, allItems, serverBaseUrl, tmpDir.path);
        _restoredCount++;
      } catch (e) {
        _failedFiles.add(item.fileName);
      }
      notifyListeners();
    }

    _status = RestoreStatus.done;
    notifyListeners();
  }

  Future<void> _restoreItem(
    MediaItem item,
    List<MediaItem> allItems,
    String baseUrl,
    String tmpDir,
  ) async {
    switch (item.mediaType) {
      case MediaType.image:
        await _restoreImage(item, baseUrl, tmpDir);
      case MediaType.video:
        await _restoreVideo(item, baseUrl, tmpDir);
      case MediaType.livePhoto:
        await _restoreLivePhoto(item, allItems, baseUrl, tmpDir);
    }
  }

  // 16.2 – plain image
  Future<void> _restoreImage(
    MediaItem item,
    String baseUrl,
    String tmpDir,
  ) async {
    final tmpPath = '$tmpDir/${item.id}_${item.fileName}';
    await _downloadFile('$baseUrl/api/v1/media/${item.id}/original', tmpPath);
    try {
      final result =
          await PhotoManager.editor.saveImageWithPath(tmpPath, title: item.fileName);
      if (result == null) throw Exception('saveImageWithPath returned null');
    } finally {
      _deleteSilently(tmpPath);
    }
  }

  // 16.2 – video
  Future<void> _restoreVideo(
    MediaItem item,
    String baseUrl,
    String tmpDir,
  ) async {
    final tmpPath = '$tmpDir/${item.id}_${item.fileName}';
    await _downloadFile('$baseUrl/api/v1/media/${item.id}/original', tmpPath);
    try {
      final result = await PhotoManager.editor.saveVideo(
        File(tmpPath),
        title: item.fileName,
      );
      if (result == null) throw Exception('saveVideo returned null');
    } finally {
      _deleteSilently(tmpPath);
    }
  }

  // 16.3 / 16.4 – Live Photo (iOS platform channel)
  Future<void> _restoreLivePhoto(
    MediaItem item,
    List<MediaItem> allItems,
    String baseUrl,
    String tmpDir,
  ) async {
    final heicPath = '$tmpDir/${item.id}_${item.fileName}';
    await _downloadFile('$baseUrl/api/v1/media/${item.id}/original', heicPath);

    // Find the paired MOV by live_photo_pair_name.
    final pairName = item.livePhotoPairName;
    if (pairName == null) {
      // Fallback: save as plain image if no pair found.
      try {
        final result = await PhotoManager.editor
            .saveImageWithPath(heicPath, title: item.fileName);
        if (result == null) throw Exception('saveImageWithPath returned null');
      } finally {
        _deleteSilently(heicPath);
      }
      return;
    }

    final pairItem = allItems.firstWhere(
      (e) => e.fileName == pairName,
      orElse: () => throw Exception('Live Photo pair not found: $pairName'),
    );

    final movPath = '$tmpDir/${pairItem.id}_${pairItem.fileName}';
    await _downloadFile(
        '$baseUrl/api/v1/media/${pairItem.id}/original', movPath);

    try {
      final ok = await LivePhotoChannel.saveLivePhoto(
        heicPath: heicPath,
        movPath: movPath,
      );
      if (!ok) throw Exception('LivePhotoChannel.saveLivePhoto returned false');
    } finally {
      _deleteSilently(heicPath);
      _deleteSilently(movPath);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _downloadFile(String url, String destPath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }
    await File(destPath).writeAsBytes(response.bodyBytes);
  }

  void _deleteSilently(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  /// Resets provider back to idle state.
  void reset() {
    _status = RestoreStatus.idle;
    _restoredCount = 0;
    _totalCount = 0;
    _failedFiles.clear();
    _errorMessage = null;
    _selectedIds.clear();
    notifyListeners();
  }
}
