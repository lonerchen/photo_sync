import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Manages the album list fetched from the storage server HTTP API.
class AlbumProvider extends ChangeNotifier {
  List<Album> _albums = [];
  Album? _selectedAlbum;
  bool _isLoading = false;
  String? _error;

  List<Album> get albums => _albums;
  Album? get selectedAlbum => _selectedAlbum;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetches albums from `GET /api/v1/devices/{deviceId}/albums`.
  Future<void> loadAlbums(String baseUrl, String deviceId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$baseUrl/api/v1/devices/$deviceId/albums');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final apiResponse = ApiResponse.fromJson(json, (data) {
          return (data as List)
              .map((e) => Album.fromJson(e as Map<String, dynamic>))
              .toList();
        });
        _albums = apiResponse.data ?? [];
      } else {
        _error = 'Server error: ${response.statusCode}';
        _albums = [];
      }
    } catch (e) {
      _error = e.toString();
      _albums = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Selects an album and notifies listeners.
  void selectAlbum(Album album) {
    _selectedAlbum = album;
    notifyListeners();
  }

  /// Clears the current state (e.g. on disconnect).
  void clear() {
    _albums = [];
    _selectedAlbum = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
