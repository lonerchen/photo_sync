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

  /// Returns a page of assets in [album], sorted by creation date descending.
  /// [page] is 0-indexed. Returns empty list when no more data.
  Future<List<AssetEntity>> getAssetsPage(
    AssetPathEntity album, {
    required int page,
    int pageSize = 80,
    DateTimeRange? dateRange,
  }) async {
    if (dateRange != null) {
      // photo_manager 不支持按日期分页，需要先全量过滤再手动分页
      final all = await getAssets(album, dateRange: dateRange);
      final start = page * pageSize;
      if (start >= all.length) return [];
      final end = (start + pageSize).clamp(0, all.length);
      return all.sublist(start, end);
    }
    return album.getAssetListPaged(page: page, size: pageSize);
  }

  /// Returns total asset count in [album], optionally filtered by [dateRange].
  Future<int> getAssetCount(
    AssetPathEntity album, {
    DateTimeRange? dateRange,
  }) async {
    if (dateRange == null) return album.assetCountAsync;
    final all = await getAssets(album, dateRange: dateRange);
    return all.length;
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
