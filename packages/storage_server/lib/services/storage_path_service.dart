import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages the root storage path configuration for the server.
///
/// Configuration is persisted as a simple JSON file next to the executable.
class StoragePathService {
  static const _configFileName = 'storage_config.json';
  static const _storagePathKey = 'storage_path';

  final String _configFilePath;

  StoragePathService({String? configFilePath})
      : _configFilePath = configFilePath ?? _defaultConfigPath();

  static String _defaultConfigPath() {
    // Will be overridden at runtime; placeholder for sync constructor.
    // Actual path resolved via getApplicationSupportDirectory() when needed.
    return '';
  }

  Future<String> _resolvedConfigPath() async {
    if (_configFilePath.isNotEmpty) return _configFilePath;
    final appSupport = await getApplicationSupportDirectory();
    return p.join(appSupport.path, 'data', _configFileName);
  }

  // ---------------------------------------------------------------------------
  // Read / write configuration
  // ---------------------------------------------------------------------------

  /// Returns the persisted storage path, or null if not configured yet.
  Future<String?> getStoragePath() async {
    final file = File(await _resolvedConfigPath());
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return json[_storagePathKey] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Validates [path] and persists it if valid.
  ///
  /// Throws [ArgumentError] if the path does not exist or is not writable.
  Future<void> setStoragePath(String path) async {
    await _validatePath(path);
    await _persist(path);
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns true if [path] exists and is writable.
  Future<bool> isValidPath(String path) async {
    try {
      await _validatePath(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _validatePath(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw ArgumentError('Storage path does not exist: $path');
    }

    // Probe writability by creating and deleting a temp file.
    final probe = File(p.join(path, '.write_probe_${DateTime.now().millisecondsSinceEpoch}'));
    try {
      await probe.writeAsString('probe');
      await probe.delete();
    } catch (e) {
      throw ArgumentError('Storage path is not writable: $path ($e)');
    }
  }

  // ---------------------------------------------------------------------------
  // Sub-directory creation
  // ---------------------------------------------------------------------------

  /// Creates the sub-directory `{storagePath}/{deviceName}_{deviceId}/{albumName}/`
  /// and returns the full path.
  Future<String> ensureAlbumDirectory({
    required String storagePath,
    required String deviceName,
    required String deviceId,
    required String albumName,
  }) async {
    final deviceDir = '${deviceName}_$deviceId';
    final albumDir = p.join(storagePath, deviceDir, albumName);
    await Directory(albumDir).create(recursive: true);
    return albumDir;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _persist(String path) async {
    final file = File(await _resolvedConfigPath());
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({_storagePathKey: path}),
      flush: true,
    );
  }
}
