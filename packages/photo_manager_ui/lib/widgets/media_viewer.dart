import 'package:cached_network_image/cached_network_image.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Full-screen media viewer with gesture zoom/pan via [PhotoView].
///
/// - Loads the original image from `$serverBaseUrl/api/v1/media/${item.id}/original`
/// - Shows a LIVE badge for Live Photos
/// - Shows loading indicator while the image loads
/// - Shows an error state on failure
/// - Has a close button (×) in the top-right corner
/// - Shows file name and taken_at in a bottom overlay
class MediaViewer extends StatelessWidget {
  const MediaViewer({
    super.key,
    required this.item,
    required this.serverBaseUrl,
  });

  final MediaItem item;
  final String serverBaseUrl;

  String get _originalUrl =>
      '$serverBaseUrl/api/v1/media/${item.id}/original';

  /// Push this viewer as a full-screen route.
  static Future<void> show(
    BuildContext context, {
    required MediaItem item,
    required String serverBaseUrl,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MediaViewer(item: item, serverBaseUrl: serverBaseUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildPhotoView(),
          _buildCloseButton(context),
          _buildBottomOverlay(context),
          if (item.mediaType == MediaType.livePhoto) _buildLiveBadge(),
        ],
      ),
    );
  }

  Widget _buildPhotoView() {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(_originalUrl),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorBuilder: (_, __, ___) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.broken_image, color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text(
              'Failed to load image',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black45,
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay(BuildContext context) {
    final takenAt = item.takenAt != null
        ? DateTime.fromMillisecondsSinceEpoch(item.takenAt!)
            .toString()
            .substring(0, 16)
        : null;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (takenAt != null) ...[
                const SizedBox(height: 2),
                Text(
                  takenAt,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
