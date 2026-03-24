import 'package:flutter/foundation.dart';

import '../services/storage_path_service.dart';

/// Manages the storage path configuration.
class StorageSettingsProvider extends ChangeNotifier {
  StorageSettingsProvider({required StoragePathService pathService})
      : _pathService = pathService;

  final StoragePathService _pathService;

  String? _storagePath;
  bool _isValidating = false;
  String? _validationError;

  String? get storagePath => _storagePath;
  bool get isValidating => _isValidating;
  String? get validationError => _validationError;
  bool get isConfigured => _storagePath != null && _storagePath!.isNotEmpty;

  Future<void> load() async {
    _storagePath = await _pathService.getStoragePath();
    notifyListeners();
  }

  Future<bool> changePath(String newPath) async {
    _isValidating = true;
    _validationError = null;
    notifyListeners();
    try {
      await _pathService.setStoragePath(newPath);
      _storagePath = newPath;
      _validationError = null;
      return true;
    } catch (e) {
      _validationError = e.toString().replaceFirst('Invalid argument(s): ', '');
      return false;
    } finally {
      _isValidating = false;
      notifyListeners();
    }
  }

  Future<bool> validatePath(String path) async {
    return _pathService.isValidPath(path);
  }
}
