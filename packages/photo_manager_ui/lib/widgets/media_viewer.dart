import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

/// Full-screen media viewer.
///
/// - Images / Live Photos: gesture zoom/pan via [PhotoView]
/// - Videos: in-app playback via [VideoPlayer]
/// - Live Photos: optional playback of paired MOV preview via top-right button
/// - Optional per-item download callback via top-right button
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.item,
    required this.serverBaseUrl,
    this.onDownload,
  });

  final MediaItem item;
  final String serverBaseUrl;
  final Future<void> Function(MediaItem item)? onDownload;

  String get _originalUrl => '$serverBaseUrl/api/v1/media/${item.id}/original';

  String get _thumbnailUrl =>
      '$serverBaseUrl/api/v1/media/${item.id}/thumbnail';

  static Future<void> show(
    BuildContext context, {
    required MediaItem item,
    required String serverBaseUrl,
    Future<void> Function(MediaItem item)? onDownload,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MediaViewer(
          item: item,
          serverBaseUrl: serverBaseUrl,
          onDownload: onDownload,
        ),
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;

  VideoPlayerController? _liveVideoController;
  Future<void>? _liveVideoInitFuture;
  bool _showLiveVideoPreview = false;
  bool _loadingLiveVideo = false;
  String? _liveVideoError;

  bool _downloading = false;

  bool get _useExternalPlayerOnDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (widget.item.mediaType == MediaType.video && !_useExternalPlayerOnDesktop) {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget._originalUrl));
      _videoController = controller;
      _videoInitFuture = controller.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _liveVideoController?.dispose();
    super.dispose();
  }

  bool get _isLivePhoto => widget.item.mediaType == MediaType.livePhoto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          widget.item.mediaType == MediaType.video
              ? _buildVideoPlayer()
              : _buildPhotoView(useThumbnailAsSource: _isLivePhoto),
          if (_isLivePhoto && _showLiveVideoPreview) _buildLiveVideoOverlay(),
          _buildTopActions(context),
          _buildBottomOverlay(),
          if (_isLivePhoto) _buildLiveBadge(),
        ],
      ),
    );
  }

  // ── Video ──────────────────────────────────────────────────────────────────

  Widget _buildVideoPlayer() {
    if (_useExternalPlayerOnDesktop) {
      return _buildExternalVideoPlaceholder(widget._originalUrl);
    }

    final controller = _videoController;
    if (controller == null) {
      return const Center(
        child: Text(
          '无法初始化视频播放器',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return FutureBuilder<void>(
      future: _videoInitFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: widget._thumbnailUrl,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
              ),
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ],
          );
        }

        if (snapshot.hasError || !controller.value.isInitialized) {
          return const Center(
            child: Text(
              '视频加载失败',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return _buildVideoSurface(controller, progressBottomPadding: 88);
      },
    );
  }

  Widget _buildLiveVideoOverlay() {
    if (_loadingLiveVideo) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_liveVideoError != null) {
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          _liveVideoError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    final controller = _liveVideoController;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Text(
          '实况视频不可用',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Container(
      color: Colors.black87,
      child: _buildVideoSurface(controller, progressBottomPadding: 88),
    );
  }

  Widget _buildExternalVideoPlaceholder(String url) {
    return GestureDetector(
      onTap: () => _openInSystemPlayer(url),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: widget._thumbnailUrl,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
          Container(color: Colors.black54),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.open_in_new, color: Colors.white, size: 64),
                SizedBox(height: 12),
                Text(
                  '点击使用系统播放器打开',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSurface(
    VideoPlayerController controller, {
    required double progressBottomPadding,
  }) {
    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio:
                  controller.value.aspectRatio <= 0 ? 16 / 9 : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 88,
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: EdgeInsets.only(bottom: progressBottomPadding),
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Image ──────────────────────────────────────────────────────────────────

  Widget _buildPhotoView({bool useThumbnailAsSource = false}) {
    final imageUrl = useThumbnailAsSource ? widget._thumbnailUrl : widget._originalUrl;
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(imageUrl),
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
            Text('Failed to load image', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  // ── Common overlays ────────────────────────────────────────────────────────

  Widget _buildTopActions(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onDownload != null)
                _actionButton(
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download, color: Colors.white),
                  tooltip: '下载到本机',
                  onPressed: _downloading ? null : _handleDownload,
                ),
              if (_isLivePhoto)
                _actionButton(
                  icon: Icon(
                    _showLiveVideoPreview ? Icons.pause_circle : Icons.play_circle,
                    color: Colors.white,
                  ),
                  tooltip: _useExternalPlayerOnDesktop
                      ? '用系统播放器打开实况视频'
                      : (_showLiveVideoPreview ? '停止实况预览' : '播放实况预览'),
                  onPressed: _toggleLivePreview,
                ),
              _actionButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        icon: icon,
        style: IconButton.styleFrom(backgroundColor: Colors.black45),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  Future<void> _handleDownload() async {
    final callback = widget.onDownload;
    if (callback == null) return;

    setState(() => _downloading = true);
    try {
      await callback(widget.item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始回拉并保存到本机')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _toggleLivePreview() async {
    if (_useExternalPlayerOnDesktop) {
      try {
        final pair = await _fetchLivePhotoPair(widget.item.id);
        if (pair == null) throw Exception('Live pair not found');
        final url = '${widget.serverBaseUrl}/api/v1/media/${pair.id}/original';
        await _openInSystemPlayer(url);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('实况视频打开失败')),
        );
      }
      return;
    }

    if (!_showLiveVideoPreview) {
      setState(() {
        _showLiveVideoPreview = true;
        _loadingLiveVideo = true;
        _liveVideoError = null;
      });

      try {
        await _ensureLiveVideoInitialized();
        await _liveVideoController?.play();
      } catch (e) {
        _liveVideoError = '实况视频加载失败';
      } finally {
        if (mounted) {
          setState(() => _loadingLiveVideo = false);
        }
      }
      return;
    }

    await _liveVideoController?.pause();
    if (mounted) {
      setState(() {
        _showLiveVideoPreview = false;
      });
    }
  }

  Future<void> _ensureLiveVideoInitialized() async {
    if (_liveVideoController != null && _liveVideoController!.value.isInitialized) {
      return;
    }

    final pair = await _fetchLivePhotoPair(widget.item.id);
    if (pair == null) {
      throw Exception('Live pair not found');
    }

    final url = '${widget.serverBaseUrl}/api/v1/media/${pair.id}/original';
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _liveVideoController = controller;
    _liveVideoInitFuture = controller.initialize();
    await _liveVideoInitFuture;
  }

  Future<MediaItem?> _fetchLivePhotoPair(int mediaId) async {
    final uri = Uri.parse('${widget.serverBaseUrl}/api/v1/media/$mediaId/pair');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    return MediaItem.fromJson(data);
  }

  Future<void> _openInSystemPlayer(String url) async {
    if (kIsWeb) return;
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
      return;
    }
  }

  Widget _buildBottomOverlay() {
    final takenAt = widget.item.takenAt != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.item.takenAt!).toString().substring(0, 16)
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
                widget.item.fileName,
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
