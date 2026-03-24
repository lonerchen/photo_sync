import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Full-screen media viewer.
///
/// - Images / Live Photos: gesture zoom/pan via [PhotoView]
/// - Videos: shows thumbnail + play button; tapping opens the video in the
///   system default player via [Process.run] (desktop) or shows a message
///   (mobile — video playback not supported in-app on mobile yet).
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

  String get _thumbnailUrl =>
      '$serverBaseUrl/api/v1/media/${item.id}/thumbnail';

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
          item.mediaType == MediaType.video
              ? _buildVideoPlaceholder(context)
              : _buildPhotoView(),
          _buildCloseButton(context),
          _buildBottomOverlay(),
          if (item.mediaType == MediaType.livePhoto) _buildLiveBadge(),
        ],
      ),
    );
  }

  // ── Video ──────────────────────────────────────────────────────────────────

  Widget _buildVideoPlaceholder(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVideoInSystemPlayer(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Show thumbnail as background if available
          CachedNetworkImage(
            imageUrl: _thumbnailUrl,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
          // Dark overlay
          Container(color: Colors.black54),
          // Play button
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '点击用系统播放器打开',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openVideoInSystemPlayer(BuildContext context) async {
    // On desktop, download URL is accessible via localhost.
    // Use platform-specific open command.
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', _originalUrl]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_originalUrl]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [_originalUrl]);
      } else {
        // Mobile: show snackbar
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('移动端暂不支持视频播放')),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开系统播放器')),
        );
      }
    }
  }

  // ── Image ──────────────────────────────────────────────────────────────────

  Widget _buildPhotoView() {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(_originalUrl),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, __, ___) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.broken_image, color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text('Failed to load image',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  // ── Common overlays ────────────────────────────────────────────────────────

  Widget _buildCloseButton(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
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
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
              if (takenAt != null) ...[
                const SizedBox(height: 2),
                Text(takenAt,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
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
                  letterSpacing: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}
