import 'package:flutter/foundation.dart';

/// Exposes thumbnail generation queue statistics to the UI.
class ThumbnailQueueProvider extends ChangeNotifier {
  int _pendingCount = 0;
  int _completedCount = 0;
  bool _isProcessing = false;

  int get pendingCount => _pendingCount;
  int get completedCount => _completedCount;
  bool get isProcessing => _isProcessing;

  void update({
    required int pendingCount,
    required int completedCount,
    required bool isProcessing,
  }) {
    _pendingCount = pendingCount;
    _completedCount = completedCount;
    _isProcessing = isProcessing;
    notifyListeners();
  }

  void incrementCompleted() {
    if (_pendingCount > 0) _pendingCount--;
    _completedCount++;
    notifyListeners();
  }
}
