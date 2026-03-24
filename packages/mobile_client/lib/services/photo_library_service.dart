import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Service for reading the device photo library using photo_manager.
class PhotoLibraryService {
  /// Returns all albums (asset paths) on the device.
  Future<List<AssetPathEntity>> getAlbums() async {
    final permitted = await _requestPermission();
    if (!permitted) return [];
    return PhotoManager.getAssetPathList(type: RequestType.common);
  }

  /// Returns assets in [album], optionally filtered by [dateRange].
  Future<List<AssetEntity>> getAssets(
    AssetPathEntity album, {
    DateTimeRange? dateRange,
  }) async {
    final count = await album.assetCountAsync;
    if (count == 0) return [];

    final assets = await album.getAssetListRange(start: 0, end: count);

    if (dateRange == null) return assets;

    return assets.where((a) {
      final created = a.createDateTime;
      return !created.isBefore(dateRange.start) &&
          !created.isAfter(dateRange.end);
    }).toList();
  }

  /// Returns the local file path for [asset], or null if unavailable.
  Future<String?> getAssetFilePath(AssetEntity asset) async {
    final file = await asset.originFile;
    return file?.path;
  }

  /// Exports HEIC and MOV files for a Live Photo asset.
  ///
  /// Returns a record with [heicPath] and [movPath], or null on failure.
  /// Note: Live Photos only exist on iOS; returns null on Android.
  Future<({String heicPath, String movPath})?> getLivePhotoFiles(
    AssetEntity asset,
  ) async {
    if (!asset.isLivePhoto) return null;

    try {
      // Still image (.HEIC)
      final heicFile = await asset.originFile;
      if (heicFile == null) return null;

      // Paired video (.MOV) — originFileWithSubtype returns the Live Photo video on iOS
      final movFile = await asset.originFileWithSubtype;
      if (movFile == null) return null;

      return (heicPath: heicFile.path, movPath: movFile.path);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<bool> _requestPermission() async {
    final result = await PhotoManager.requestPermissionExtend();
    return result.isAuth || result == PermissionState.limited;
  }
}
