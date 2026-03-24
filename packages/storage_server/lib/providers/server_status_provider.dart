import 'package:flutter/foundation.dart';

/// Tracks the running state of the HTTP/WebSocket server.
class ServerStatusProvider extends ChangeNotifier {
  bool _isRunning = false;
  int _port = 8765;
  int _connectedDeviceCount = 0;
  double? _indexRebuildProgress; // null = not rebuilding, 0.0–1.0 = in progress

  bool get isRunning => _isRunning;
  int get port => _port;
  int get connectedDeviceCount => _connectedDeviceCount;
  double? get indexRebuildProgress => _indexRebuildProgress;

  void setRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    notifyListeners();
  }

  void setPort(int value) {
    if (_port == value) return;
    _port = value;
    notifyListeners();
  }

  void setConnectedDeviceCount(int count) {
    if (_connectedDeviceCount == count) return;
    _connectedDeviceCount = count;
    notifyListeners();
  }

  void setIndexRebuildProgress(double? progress) {
    _indexRebuildProgress = progress;
    notifyListeners();
  }
}
