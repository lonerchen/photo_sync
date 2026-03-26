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
  String _sortOrder = 'desc'; // 'desc' = 最新在前, 'asc' = 最旧在前
  int _currentPage = 1;
  int _total = 0;

  String? _baseUrl;
  String? _deviceId;
  String? _albumName;

  List<MediaItem> get items => _items;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  DateTimeRange? get dateFilter => _dateFilter;
  String get sortOrder => _sortOrder;

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

  /// Toggles sort order between 'desc' and 'asc', then reloads.
  void toggleSortOrder() {
    _sortOrder = _sortOrder == 'desc' ? 'asc' : 'desc';
    // 先对已加载的数据做内存排序，立即响应
    if (_items.isNotEmpty) {
      _items = List.of(_items)
        ..sort((a, b) {
          final ta = a.takenAt ?? 0;
          final tb = b.takenAt ?? 0;
          return _sortOrder == 'asc' ? ta.compareTo(tb) : tb.compareTo(ta);
        });
    }
    notifyListeners(); // 立即更新 UI
    // 同时从服务端重新拉取（保证分页数据也是正确顺序）
    if (_baseUrl != null && _deviceId != null && _albumName != null) {
      _currentPage = 1;
      _total = 0;
      _fetch();
    }
  }

  /// Reloads the current album from page 1 (e.g. after a new upload).
  /// 保留旧数据直到新数据到达，避免闪烁。
  void reload() {
    if (_baseUrl != null && _deviceId != null && _albumName != null) {
      _currentPage = 1;
      _total = 0;
      // 不清空 _items，让旧数据继续显示
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
    // 只在列表为空时通知 loading 状态，避免有数据时闪烁
    if (_items.isEmpty) notifyListeners();

    try {
      final queryParams = <String, String>{
        'page': '$_currentPage',
        'page_size': '$_pageSize',
        'sort_order': _sortOrder,
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
          List<MediaItem> newItems = result.items;
          // 客户端兜底排序，防止服务端未更新时顺序不对
          newItems.sort((a, b) {
            final ta = a.takenAt ?? 0;
            final tb = b.takenAt ?? 0;
            return _sortOrder == 'asc' ? ta.compareTo(tb) : tb.compareTo(ta);
          });
          if (append) {
            _items = [..._items, ...newItems];
          } else {
            _items = newItems;
          }
          _total = result.total;
          _hasMore = _items.length < _total;
        }
      }
    } catch (e) {
      // Keep existing items on error; hasMore stays as-is.
      debugPrint('[MediaListProvider] _fetch error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
