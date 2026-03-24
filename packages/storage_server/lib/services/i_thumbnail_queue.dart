/// Interface for the thumbnail generation queue.
///
/// Concrete implementation lives in the thumbnail service (task 8).
abstract interface class IThumbnailQueue {
  /// Enqueues a normal-priority thumbnail generation task.
  void enqueue(int mediaId);

  /// Moves [mediaId] to the front of the priority queue.
  void enqueuePriority(int mediaId);
}
