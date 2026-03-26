import 'package:flutter/foundation.dart';

import '../services/i_server_database.dart';
import '../services/storage_path_service.dart';

/// Manages the storage path configuration.
class StorageSettingsProvider extends ChangeNotifier {
  StorageSettingsProvider({
    required StoragePathService pathService,
    required IServerDatabase database,
  })  : _pathService = pathService,
        _database = database;

  final StoragePathService _pathService;
  final IServerDatabase _database;

  String? _storagePath;
  bool _isValidating = false;
  bool _isMigrating = false;
  double _migrationProgress = 0;
  String _migrationMessage = '';
  String? _validationError;

  String? get storagePath => _storagePath;
  bool get isValidating => _isValidating;
  bool get isMigrating => _isMigrating;
  double get migrationProgress => _migrationProgress;
  String get migrationMessage => _migrationMessage;
  String? get validationError => _validationError;
  bool get isBusy => _isValidating || _isMigrating;
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
      final targetPath = newPath.trim();
      final isValid = await _pathService.isValidPath(targetPath);
      if (!isValid) {
        throw ArgumentError('Storage path does not exist or is not writable: $targetPath');
      }

      final currentPath = _storagePath?.trim();
      final shouldMigrate = currentPath != null &&
          currentPath.isNotEmpty &&
          currentPath != targetPath;

      if (shouldMigrate) {
        _isMigrating = true;
        _migrationProgress = 0;
        _migrationMessage = '正在迁移数据到新存储路径...';
        notifyListeners();

        await _database.migrateStoragePath(
          oldPath: currentPath,
          newPath: targetPath,
          onProgress: (done, total) {
            _migrationProgress = total == 0 ? 1 : done / total;
            _migrationMessage = '正在迁移数据 ($done/$total)...';
            notifyListeners();
          },
        );
      }

      // 数据迁移成功后再落盘新配置，才算设置成功。
      await _pathService.setStoragePath(targetPath);
      _storagePath = targetPath;
      _validationError = null;
      return true;
    } catch (e) {
      _validationError = e.toString().replaceFirst('Invalid argument(s): ', '');
      return false;
    } finally {
      _isValidating = false;
      _isMigrating = false;
      _migrationProgress = 0;
      _migrationMessage = '';
      notifyListeners();
    }
  }

  Future<bool> validatePath(String path) async {
    return _pathService.isValidPath(path);
  }
}
