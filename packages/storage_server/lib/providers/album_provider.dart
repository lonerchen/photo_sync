import 'package:common/common.dart';
import 'package:flutter/foundation.dart';

import '../services/i_server_database.dart';

/// Manages the selected device and album for the album browser screen.
class AlbumProvider extends ChangeNotifier {
  AlbumProvider({required IServerDatabase database}) : _database = database;

  final IServerDatabase _database;

  DeviceInfo? _selectedDevice;
  List<Album> _albums = [];
  Album? _selectedAlbum;
  bool _isLoading = false;

  DeviceInfo? get selectedDevice => _selectedDevice;
  List<Album> get albums => _albums;
  Album? get selectedAlbum => _selectedAlbum;
  bool get isLoading => _isLoading;

  /// Called after albums are loaded; if set, auto-selects the first album.
  void Function(Album album)? onAutoSelectAlbum;

  Future<void> selectDevice(DeviceInfo device) async {
    _selectedDevice = device;
    _selectedAlbum = null;
    _albums = [];
    notifyListeners();
    await _loadAlbums();
  }

  void selectAlbum(Album album) {
    _selectedAlbum = album;
    notifyListeners();
  }

  Future<void> _loadAlbums() async {
    if (_selectedDevice == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      _albums = await _database.getAlbums(_selectedDevice!.deviceId);
      // 如果只有一个相册，自动选中
      if (_albums.length == 1 && _selectedAlbum == null) {
        _selectedAlbum = _albums.first;
        onAutoSelectAlbum?.call(_albums.first);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reloads albums for the currently selected device (no-op if none selected).
  Future<void> refresh() => _loadAlbums();
}
