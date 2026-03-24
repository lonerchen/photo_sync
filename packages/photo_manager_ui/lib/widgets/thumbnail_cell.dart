import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';

/// A grid cell that displays a single media thumbnail.
///
/// Shows a Live Photo badge when [mediaType] is [MediaType.livePhoto],
/// a loading placeholder while the image loads, and a broken-image icon on error.
class ThumbnailCell extends StatelessWidget {
  const ThumbnailCell({
    super.key,
    this.thumbnailUrl,
    this.localFilePath,
    required this.mediaType,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  final String? thumbnailUrl;

  /// Local file system path for desktop (bypasses HTTP).
  final String? localFilePath;

  final MediaType mediaType;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(),
          if (isSelected) _buildSelectionOverlay(),
          if (mediaType == MediaType.livePhoto) _buildLiveBadge(),
        ],
      ),
    );
  }

  Widget _buildImage() {
    // Local file path takes priority (desktop server).
    if (localFilePath != null && localFilePath!.isNotEmpty) {
      return Image.file(
        File(localFilePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(broken: true),
      );
    }

    if (thumbnailUrl == null || thumbnailUrl!.isEmpty) {
      return _placeholder();
    }

    return CachedNetworkImage(
      imageUrl: thumbnailUrl!,
      fit: BoxFit.cover,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(broken: true),
    );
  }

  Widget _placeholder({bool broken = false}) {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        broken
            ? Icons.broken_image
            : (mediaType == MediaType.video
                ? Icons.videocam
                : Icons.image),
        color: Colors.grey,
      ),
    );
  }

  Widget _buildSelectionOverlay() {
    return Container(
      color: Colors.blue.withOpacity(0.35),
      child: const Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.check_circle, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
