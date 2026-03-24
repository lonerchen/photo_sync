import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Manages paginated media items fetched from the storage server HTTP API.
class MediaListProvider extends ChangeNotifier {
  static const _pageSize = 50;

  List<MediaItem> _items = [];
  bool _hasMore = false;
  bool _isLoading = false;
  DateTimeRange? _dateFilter;
  int _currentPage = 1;
  int _total = 0;

  String? _baseUrl;
  String? _deviceId;
  String? _albumName;

  List<MediaItem> get items => _items;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  DateTimeRange? get dateFilter => _dateFilter;

  /// Loads the first page of media for the given album.
  Future<void> load(String baseUrl, String deviceId, String albumName) async {
    _baseUrl = baseUrl;
    _deviceId = deviceId;
    _albumName = albumName;
    _currentPage = 1;
    _items = [];
    _total = 0;
    await _fetch();
  }

  /// Loads the next page (called when scrolling near the bottom).
  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;
    _currentPage++;
    await _fetch(append: true);
  }

  /// Applies a date filter and reloads from page 1.
  void applyFilter(DateTimeRange? range) {
    _dateFilter = range;
    if (_baseUrl != null && _deviceId != null && _albumName != null) {
      _currentPage = 1;
      _items = [];
      _total = 0;
      _fetch();
    }
  }

  /// Updates a single item's thumbnail URL after a `thumbnail_ready` event.
  void refreshItem(int mediaId, String thumbnailUrl) {
    final index = _items.indexWhere((item) => item.id == mediaId);
    if (index == -1) return;

    final old = _items[index];
    _items[index] = MediaItem(
      id: old.id,
      deviceId: old.deviceId,
      fileName: old.fileName,
      albumName: old.albumName,
      filePath: old.filePath,
      fileSize: old.fileSize,
      mediaType: old.mediaType,
      takenAt: old.takenAt,
      thumbnailPath: thumbnailUrl,
      thumbnailStatus: ThumbnailStatus.ready,
      livePhotoPairName: old.livePhotoPairName,
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
    );
    notifyListeners();
  }

  /// Clears all state (e.g. on disconnect or album deselection).
  void clear() {
    _items = [];
    _hasMore = false;
    _isLoading = false;
    _currentPage = 1;
    _total = 0;
    _baseUrl = null;
    _deviceId = null;
    _albumName = null;
    notifyListeners();
  }

  Future<void> _fetch({bool append = false}) async {
    if (_baseUrl == null || _deviceId == null || _albumName == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final queryParams = <String, String>{
        'page': '$_currentPage',
        'page_size': '$_pageSize',
      };
      if (_dateFilter != null) {
        queryParams['start_date'] =
            '${_dateFilter!.start.millisecondsSinceEpoch}';
        queryParams['end_date'] =
            '${_dateFilter!.end.millisecondsSinceEpoch}';
      }

      final uri = Uri.parse(
        '$_baseUrl/api/v1/devices/$_deviceId/albums/$_albumName/media',
      ).replace(queryParameters: queryParams);

      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final apiResponse = ApiResponse.fromJson(
          json,
          (data) => MediaListResponse.fromJson(data as Map<String, dynamic>),
        );
        final result = apiResponse.data;
        if (result != null) {
          if (append) {
            _items = [..._items, ...result.items];
          } else {
            _items = result.items;
          }
          _total = result.total;
          _hasMore = _items.length < _total;
        }
      }
    } catch (_) {
      // Keep existing items on error; hasMore stays as-is.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
