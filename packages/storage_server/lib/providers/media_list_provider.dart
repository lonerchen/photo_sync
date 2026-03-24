import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/i_server_database.dart';

/// Manages the paginated media list for the currently selected album.
class MediaListProvider extends ChangeNotifier {
  MediaListProvider({required IServerDatabase database}) : _database = database;

  final IServerDatabase _database;

  static const _pageSize = 50;

  List<MediaItem> _items = [];
  bool _hasMore = false;
  bool _isLoading = false;
  int _currentPage = 1;
  DateTimeRange? _dateFilter;

  String? _deviceId;
  String? _albumName;

  List<MediaItem> get items => _items;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  DateTimeRange? get dateFilter => _dateFilter;

  Future<void> load({required String deviceId, required String albumName}) async {
    _deviceId = deviceId;
    _albumName = albumName;
    _currentPage = 1;
    _items = [];
    await _fetch();
  }

  Future<void> refresh() async {
    if (_deviceId == null || _albumName == null) return;
    _currentPage = 1;
    _items = [];
    await _fetch();
  }

  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;
    _currentPage++;
    await _fetch(append: true);
  }

  void applyFilter(DateTimeRange? range) {
    _dateFilter = range;
    refresh();
  }

  Future<void> _fetch({bool append = false}) async {
    if (_deviceId == null || _albumName == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _database.getMediaItems(
        deviceId: _deviceId!,
        albumName: _albumName!,
        page: _currentPage,
        pageSize: _pageSize,
        startDate: _dateFilter?.start.millisecondsSinceEpoch,
        endDate: _dateFilter?.end.millisecondsSinceEpoch,
      );
      if (append) {
        _items = [..._items, ...result.items];
      } else {
        _items = result.items;
      }
      _hasMore = _items.length < result.total;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
