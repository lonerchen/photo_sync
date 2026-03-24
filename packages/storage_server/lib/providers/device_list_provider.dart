import 'package:common/common.dart';
import 'package:flutter/foundation.dart';

import '../services/i_server_database.dart';

/// Provides the list of known devices from the local database.
class DeviceListProvider extends ChangeNotifier {
  DeviceListProvider({required IServerDatabase database}) : _database = database;

  final IServerDatabase _database;

  List<DeviceInfo> _devices = [];
  bool _isLoading = false;

  List<DeviceInfo> get devices => _devices;
  bool get isLoading => _isLoading;

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    try {
      _devices = await _database.getAllDevices();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
