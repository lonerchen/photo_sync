import 'package:flutter/foundation.dart';

import '../services/local_network_permission_service.dart';

class LocalNetworkPermissionProvider extends ChangeNotifier {
  LocalNetworkPermissionProvider({LocalNetworkPermissionService? service})
      : _service = service ?? LocalNetworkPermissionService();

  final LocalNetworkPermissionService _service;

  LocalNetworkPermissionStatus _status = LocalNetworkPermissionStatus.unknown;
  bool _requested = false;

  LocalNetworkPermissionStatus get status => _status;
  bool get isDenied => _status == LocalNetworkPermissionStatus.denied;
  bool get isRequesting => _status == LocalNetworkPermissionStatus.requesting;

  Future<void> ensureRequested() async {
    if (_requested) return;
    _requested = true;
    await requestNow();
  }

  Future<void> requestNow() async {
    _status = LocalNetworkPermissionStatus.requesting;
    notifyListeners();
    final result = await _service.requestPermission();
    _status = result;
    notifyListeners();
  }

  Future<void> openSettings() async {
    await _service.openSettings();
  }
}
