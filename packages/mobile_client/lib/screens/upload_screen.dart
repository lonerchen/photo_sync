import 'dart:io';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_ui/photo_manager_ui.dart';
import 'package:provider/provider.dart';

import '../providers/upload_queue_provider.dart';
import '../services/connection_service.dart';
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

  // Maps localAssetId+fileName → local file path (populated at upload time).
  final Map<String, String> _filePathCache = {};

  @override
  void initState() {
    super.initState();
    // Delay until after first frame so the permission dialog can render properly on iOS
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissionAndLoad());
  }

  Future<void> _requestPermissionAndLoad() async {
    final result = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (result.isAuth || result == PermissionState.limited) {
      _loadAlbums();
    } else {
      // Permission denied — show a prompt to open Settings
      setState(() => _loadingAlbums = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('需要相册权限才能上传照片，请在设置中开启'),
            action: SnackBarAction(
              label: '去设置',
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
    }
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
    // Map from fileName → AssetEntity for lazy path resolution at upload time
    final assetMap = <String, AssetEntity>{};

    final now = DateTime.now().millisecondsSinceEpoch;
    final albumName = _selectedAlbum!.name;
    final serverId = server.serverId;

    for (final asset in assets) {
      // iOS asset.id 可能包含 '/'（如 "UUID/L0/001"），需要替换成 '_' 避免路径问题
      final safeId = asset.id.replaceAll('/', '_');
      if (asset.isLivePhoto) {
        final heicName = '$safeId.HEIC';
        final movName = '$safeId.MOV';

        tasks.add(UploadTask(
          serverId: serverId,
          fileName: heicName,
          albumName: albumName,
          localAssetId: asset.id,
          totalSize: 0,
          chunkSize: 524288,
          taskStatus: TaskStatus.pending,
          mediaType: MediaType.livePhoto,
          livePhotoPairName: movName,
          createdAt: now,
          updatedAt: now,
        ));
        tasks.add(UploadTask(
          serverId: serverId,
          fileName: movName,
          albumName: albumName,
          localAssetId: asset.id,
          totalSize: 0,
          chunkSize: 524288,
          taskStatus: TaskStatus.pending,
          mediaType: MediaType.livePhoto,
          livePhotoPairName: heicName,
          createdAt: now,
          updatedAt: now,
        ));
        assetMap[heicName] = asset;
        assetMap[movName] = asset;
      } else {
        final ext = asset.mimeType?.split('/').last.toUpperCase() ?? 'JPG';
        final fileName = '$safeId.$ext';
        final mediaType =
            asset.type == AssetType.video ? MediaType.video : MediaType.image;

        tasks.add(UploadTask(
          serverId: serverId,
          fileName: fileName,
          albumName: albumName,
          localAssetId: asset.id,
          totalSize: 0,
          chunkSize: 524288,
          taskStatus: TaskStatus.pending,
          mediaType: mediaType,
          createdAt: now,
          updatedAt: now,
        ));
        assetMap[fileName] = asset;
      }
    }

    if (!mounted) return;

    final baseUrl = 'http://${server.ipAddress}:${server.port}';

    // Resolve file path lazily at upload time (one at a time), not all upfront
    await queueProvider.startUpload(
      tasks: tasks,
      baseUrl: baseUrl,
      deviceId: 'android_device',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionService = context.watch<ConnectionService>();
    final queueProvider = context.watch<UploadQueueProvider>();
    final l = AppLocalizations.of(context);

    final isConnected =
        connectionService.status == ConnectionStatus.connected;
    final isUploading = queueProvider.status == QueueStatus.running;
    final isPaused = queueProvider.status == QueueStatus.paused;
    final isActive = isUploading || isPaused;

    return Scaffold(
      appBar: AppBar(title: Text(l.uploadTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isConnected)
              Card(
                color: Colors.orange,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l.notConnectedWarning,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),

            const SizedBox(height: 12),

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
                    .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(a.name),
                        ))
                    .toList(),
                onChanged: isActive
                    ? null
                    : (v) => setState(() => _selectedAlbum = v),
              )
            else
              Text(l.noAlbumsFound),

            const SizedBox(height: 16),

            DateRangePicker(
              onChanged: (range) => setState(() => _dateRange = range),
            ),

            const SizedBox(height: 24),

            if (isActive) ...[
              UploadProgressBar(
                uploadedCount: queueProvider.completedCount,
                totalCount: queueProvider.totalCount,
                bytesPerSecond: queueProvider.bytesPerSecond,
                failedCount: queueProvider.failedCount,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
              Text(l.uploadSummary(
                queueProvider.completedCount,
                queueProvider.totalCount,
                queueProvider.failedCount,
              )),
            ],
          ],
        ),
      ),
    );
  }
}
