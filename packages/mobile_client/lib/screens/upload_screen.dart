import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_ui/photo_manager_ui.dart';
import 'package:provider/provider.dart';

import '../providers/upload_queue_provider.dart';
import '../database/mobile_database.dart';
import '../services/connection_service.dart';
import '../services/device_identity_service.dart';
import '../services/photo_library_service.dart';

/// Screen for selecting photos and uploading them to the connected server.
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _photoService = PhotoLibraryService();

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  DateTimeRange? _dateRange;
  bool _loadingAlbums = false;

  // 照片网格分页状态
  final List<AssetEntity> _assets = [];
  int _currentPage = 0;
  int _totalAssetCount = 0;
  bool _loadingAssets = false;
  bool _hasMoreAssets = true;
  static const int _pageSize = 80;

  // 已上传的 asset id 集合（用于右上角标识）
  final Set<String> _uploadedAssetIds = {};

  // 缩略图 LRU 缓存，限制最多 200 张在内存中
  final _thumbCache = _LruCache<String, Uint8List>(200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissionAndLoad());
  }

  Future<void> _requestPermissionAndLoad() async {
    // 从数据库恢复已上传的 asset id 集合
    final db = MobileDatabase();
    final savedIds = await db.uploadRecordsDao.getUploadedAssetIds();
    if (mounted) {
      setState(() => _uploadedAssetIds.addAll(savedIds));
    }

    final result = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (result.isAuth || result == PermissionState.limited) {
      _loadAlbums();
    } else {
      setState(() => _loadingAlbums = false);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.photoPermissionRequired),
            action: SnackBarAction(
              label: l.goToSettings,
              onPressed: () => PhotoManager.openSetting(),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => _loadingAlbums = true);
    final albums = await _photoService.getAlbums();
    if (mounted) {
      setState(() {
        _albums = albums;
        _selectedAlbum = albums.isNotEmpty ? albums.first : null;
        _loadingAlbums = false;
      });
      _resetAndLoadAssets();
    }
  }

  /// 重置照片列表并加载第一页
  Future<void> _resetAndLoadAssets() async {
    _assets.clear();
    _currentPage = 0;
    _hasMoreAssets = true;
    _thumbCache.clear();
    if (_selectedAlbum == null) {
      setState(() => _totalAssetCount = 0);
      return;
    }
    _totalAssetCount = await _photoService.getAssetCount(
      _selectedAlbum!,
      dateRange: _dateRange,
    );
    setState(() {});
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loadingAssets || !_hasMoreAssets || _selectedAlbum == null) return;
    _loadingAssets = true;

    final page = await _photoService.getAssetsPage(
      _selectedAlbum!,
      page: _currentPage,
      pageSize: _pageSize,
      dateRange: _dateRange,
    );

    if (!mounted) return;
    setState(() {
      _assets.addAll(page);
      _currentPage++;
      _hasMoreAssets = page.length >= _pageSize;
      _loadingAssets = false;
    });
  }

  Future<void> _startUpload() async {
    final connectionService = context.read<ConnectionService>();
    final queueProvider = context.read<UploadQueueProvider>();
    final server = connectionService.currentServer;

    if (server == null || _selectedAlbum == null) return;

    final assets = await _photoService.getAssets(
      _selectedAlbum!,
      dateRange: _dateRange,
    );

    if (assets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).noPhotosInRange)),
        );
      }
      return;
    }

    final tasks = <UploadTask>[];
    final assetMap = <String, AssetEntity>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    final albumName = _selectedAlbum!.name;
    final serverId = server.serverId;

    for (final asset in assets) {
      final safeId = asset.id.replaceAll('/', '_');
      if (asset.isLivePhoto) {
        final heicName = '$safeId.HEIC';
        final movName = '$safeId.MOV';
        tasks.add(UploadTask(
          serverId: serverId, fileName: heicName, albumName: albumName,
          localAssetId: asset.id, totalSize: 0, chunkSize: 524288,
          taskStatus: TaskStatus.pending, mediaType: MediaType.livePhoto,
          livePhotoPairName: movName, createdAt: now, updatedAt: now,
        ));
        tasks.add(UploadTask(
          serverId: serverId, fileName: movName, albumName: albumName,
          localAssetId: asset.id, totalSize: 0, chunkSize: 524288,
          taskStatus: TaskStatus.pending, mediaType: MediaType.livePhoto,
          livePhotoPairName: heicName, createdAt: now, updatedAt: now,
        ));
        assetMap[heicName] = asset;
        assetMap[movName] = asset;
      } else {
        final ext = asset.mimeType?.split('/').last.toUpperCase() ?? 'JPG';
        final fileName = '$safeId.$ext';
        final mediaType =
            asset.type == AssetType.video ? MediaType.video : MediaType.image;
        tasks.add(UploadTask(
          serverId: serverId, fileName: fileName, albumName: albumName,
          localAssetId: asset.id, totalSize: 0, chunkSize: 524288,
          taskStatus: TaskStatus.pending, mediaType: mediaType,
          createdAt: now, updatedAt: now,
        ));
        assetMap[fileName] = asset;
      }
    }

    if (!mounted) return;

    final baseUrl = 'http://${server.ipAddress}:${server.port}';
    final deviceId = await DeviceIdentityService.instance.getDeviceId();

    // 注册回调，上传完成时更新 badge
    queueProvider.onAssetUploaded = (assetId) {
      if (mounted) setState(() => _uploadedAssetIds.add(assetId));
    };

    await queueProvider.startUpload(
      tasks: tasks,
      baseUrl: baseUrl,
      deviceId: deviceId,
      resolveFilePath: (task) async {
        final asset = assetMap[task.fileName];
        if (asset == null) return '';
        if (asset.isLivePhoto) {
          final paths = await _photoService.getLivePhotoFiles(asset);
          if (paths == null) return '';
          return task.fileName.endsWith('.MOV') ? paths.movPath : paths.heicPath;
        } else {
          return await _photoService.getAssetFilePath(asset) ?? '';
        }
      },
      resolveThumbnailBytes: (task) async {
        final isLiveHeic = task.mediaType == MediaType.livePhoto &&
            task.fileName.toLowerCase().endsWith('.heic');
        if (!isLiveHeic) return null;
        final asset = assetMap[task.fileName];
        if (asset == null) return null;
        return asset.thumbnailDataWithSize(
          const ThumbnailSize(1080, 1080),
          quality: 90,
        );
      },
    );
  }

  /// 单张照片上传（点击缩略图触发）
  Future<void> _uploadSingleAsset(AssetEntity asset) async {
    final connectionService = context.read<ConnectionService>();
    final queueProvider = context.read<UploadQueueProvider>();
    final server = connectionService.currentServer;

    if (server == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).connectServerFirst)),
      );
      return;
    }

    // 已上传则提示
    if (_uploadedAssetIds.contains(asset.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).alreadyUploaded),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final albumName = _selectedAlbum?.name ?? 'Default';
    final serverId = server.serverId;
    final baseUrl = 'http://${server.ipAddress}:${server.port}';
    final deviceId = await DeviceIdentityService.instance.getDeviceId();
    final safeId = asset.id.replaceAll('/', '_');

    final tasks = <UploadTask>[];
    final assetMap = <String, AssetEntity>{};

    if (asset.isLivePhoto) {
      final heicName = '$safeId.HEIC';
      final movName = '$safeId.MOV';
      tasks.add(UploadTask(
        serverId: serverId, fileName: heicName, albumName: albumName,
        localAssetId: asset.id, totalSize: 0, chunkSize: 524288,
        taskStatus: TaskStatus.pending, mediaType: MediaType.livePhoto,
        livePhotoPairName: movName, createdAt: now, updatedAt: now,
      ));
      tasks.add(UploadTask(
        serverId: serverId, fileName: movName, albumName: albumName,
        localAssetId: asset.id, totalSize: 0, chunkSize: 524288,
        taskStatus: TaskStatus.pending, mediaType: MediaType.livePhoto,
        livePhotoPairName: heicName, createdAt: now, updatedAt: now,
      ));
      assetMap[heicName] = asset;
      assetMap[movName] = asset;
    } else {
      final ext = asset.mimeType?.split('/').last.toUpperCase() ?? 'JPG';
      final fileName = '$safeId.$ext';
      final mediaType = asset.type == AssetType.video ? MediaType.video : MediaType.image;
      tasks.add(UploadTask(
        serverId: serverId, fileName: fileName, albumName: albumName,
        localAssetId: asset.id, totalSize: 0, chunkSize: 524288,
        taskStatus: TaskStatus.pending, mediaType: mediaType,
        createdAt: now, updatedAt: now,
      ));
      assetMap[fileName] = asset;
    }

    queueProvider.onAssetUploaded = (assetId) {
      if (mounted) setState(() => _uploadedAssetIds.add(assetId));
    };

    await queueProvider.enqueueTask(
      tasks: tasks,
      baseUrl: baseUrl,
      deviceId: deviceId,
      resolveFilePath: (task) async {
        final a = assetMap[task.fileName];
        if (a == null) return '';
        if (a.isLivePhoto) {
          final paths = await _photoService.getLivePhotoFiles(a);
          if (paths == null) return '';
          return task.fileName.endsWith('.MOV') ? paths.movPath : paths.heicPath;
        } else {
          return await _photoService.getAssetFilePath(a) ?? '';
        }
      },
      resolveThumbnailBytes: (task) async {
        final isLiveHeic = task.mediaType == MediaType.livePhoto &&
            task.fileName.toLowerCase().endsWith('.heic');
        if (!isLiveHeic) return null;
        final a = assetMap[task.fileName];
        if (a == null) return null;
        return a.thumbnailDataWithSize(
          const ThumbnailSize(1080, 1080),
          quality: 90,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionService = context.watch<ConnectionService>();
    final queueProvider = context.watch<UploadQueueProvider>();
    final l = AppLocalizations.of(context);

    final isConnected = connectionService.status == ConnectionStatus.connected;
    final isUploading = queueProvider.status == QueueStatus.running;
    final isPaused = queueProvider.status == QueueStatus.paused;
    final isActive = isUploading || isPaused;

    return Scaffold(
      appBar: AppBar(title: Text(l.uploadTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 顶部控制区 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isConnected)
                  Card(
                    color: Colors.orange,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(l.notConnectedWarning,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                if (_loadingAlbums)
                  const Center(child: CircularProgressIndicator())
                else if (_albums.isNotEmpty)
                  DropdownButtonFormField<AssetPathEntity>(
                    decoration: InputDecoration(
                      labelText: l.album,
                      border: const OutlineInputBorder(),
                    ),
                    value: _selectedAlbum,
                    items: _albums
                        .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                        .toList(),
                    onChanged: isActive
                        ? null
                        : (v) {
                            setState(() => _selectedAlbum = v);
                            _resetAndLoadAssets();
                          },
                  )
                else
                  Text(l.noAlbumsFound),
                const SizedBox(height: 12),
                DateRangePicker(
                  onChanged: (range) {
                    setState(() => _dateRange = range);
                    _resetAndLoadAssets();
                  },
                ),
                const SizedBox(height: 12),
                if (isActive) ...[
                  UploadProgressBar(
                    uploadedCount: queueProvider.completedCount,
                    totalCount: queueProvider.totalCount,
                    bytesPerSecond: queueProvider.bytesPerSecond,
                    failedCount: queueProvider.failedCount,
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (!isConnected || isActive || _selectedAlbum == null)
                            ? null
                            : _startUpload,
                        child: Text(l.startUpload),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: isUploading
                            ? () => queueProvider.pause()
                            : () => queueProvider.resume(),
                        child: Text(isUploading ? l.pause : l.resume),
                      ),
                    ],
                  ],
                ),
                if (queueProvider.status == QueueStatus.idle &&
                    queueProvider.totalCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(l.uploadSummary(
                    queueProvider.completedCount,
                    queueProvider.totalCount,
                    queueProvider.failedCount,
                  )),
                ],
                if (_totalAssetCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(AppLocalizations.of(context).photoCount(_totalAssetCount),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 底部照片网格 ──
          Expanded(child: _buildPhotoGrid()),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    if (_assets.isEmpty && _loadingAssets) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_assets.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noPhotos));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 500) {
          _loadNextPage();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: _assets.length + (_hasMoreAssets ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _assets.length) {
            // 加载更多指示器
            _loadNextPage();
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _AssetThumbTile(
            asset: _assets[index],
            cache: _thumbCache,
            isUploaded: _uploadedAssetIds.contains(_assets[index].id),
            onTap: () => _uploadSingleAsset(_assets[index]),
          );
        },
      ),
    );
  }
}

/// 单个照片缩略图 tile，带上传状态 badge 和完成动画。
class _AssetThumbTile extends StatefulWidget {
  const _AssetThumbTile({
    required this.asset,
    required this.cache,
    required this.isUploaded,
    this.onTap,
  });

  final AssetEntity asset;
  final _LruCache<String, Uint8List> cache;
  final bool isUploaded;
  final VoidCallback? onTap;

  @override
  State<_AssetThumbTile> createState() => _AssetThumbTileState();
}

class _AssetThumbTileState extends State<_AssetThumbTile> {
  Uint8List? _thumbData;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_AssetThumbTile old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) _loadThumb();
  }

  Future<void> _loadThumb() async {
    final cached = widget.cache.get(widget.asset.id);
    if (cached != null) {
      _thumbData = cached;
      return;
    }
    if (_loading) return;
    _loading = true;

    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(150, 150),
      quality: 70,
    );

    if (data != null) {
      widget.cache.put(widget.asset.id, data);
    }
    if (mounted) {
      setState(() {
        _thumbData = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图
          if (_thumbData != null)
            Image.memory(
              _thumbData!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else
            Container(color: Colors.grey[300]),

          // 视频标识
          if (widget.asset.type == AssetType.video)
            const Positioned(
              left: 4,
              bottom: 4,
              child: Icon(Icons.videocam, color: Colors.white, size: 16),
            ),

          // 右上角上传状态 badge
          Positioned(
            right: 3,
            top: 3,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: widget.isUploaded
                  ? const Icon(
                      Icons.check_circle,
                      key: ValueKey('done'),
                      color: Colors.green,
                      size: 20,
                    )
                  : const Icon(
                      Icons.cloud_upload_outlined,
                      key: ValueKey('pending'),
                      color: Colors.white70,
                      size: 18,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 简单的 LRU 缓存，限制最大条目数，超出时淘汰最久未访问的。
class _LruCache<K, V> {
  _LruCache(this.maxSize);
  final int maxSize;
  final _map = <K, V>{};
  final _order = <K>[];

  V? get(K key) {
    final value = _map[key];
    if (value != null) {
      _order.remove(key);
      _order.add(key);
    }
    return value;
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) {
      _order.remove(key);
    } else if (_map.length >= maxSize) {
      final evict = _order.removeAt(0);
      _map.remove(evict);
    }
    _map[key] = value;
    _order.add(key);
  }

  void clear() {
    _map.clear();
    _order.clear();
  }
}
