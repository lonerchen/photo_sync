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
    _loadAlbums();
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
    _filePathCache.clear();

    final now = DateTime.now().millisecondsSinceEpoch;
    final albumName = _selectedAlbum!.name;
    final serverId = server.serverId; // e.g. "192.168.1.1:8765"

    // file sizes resolved alongside paths
    final fileSizes = <String, int>{}; // fileName → bytes

    // Collect all path-resolution futures so we can await them all.
    final pathFutures = <Future<void>>[];

    for (final asset in assets) {
      if (asset.isLivePhoto) {
        final baseName = asset.id;
        final heicName = '$baseName.HEIC';
        final movName = '$baseName.MOV';

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

        pathFutures.add(
          _photoService.getLivePhotoFiles(asset).then((paths) {
            if (paths != null) {
              _filePathCache[heicName] = paths.heicPath;
              _filePathCache[movName] = paths.movPath;
              fileSizes[heicName] = File(paths.heicPath).lengthSync();
              fileSizes[movName] = File(paths.movPath).lengthSync();
            }
          }),
        );
      } else {
        final ext = asset.mimeType?.split('/').last.toUpperCase() ?? 'JPG';
        final fileName = '${asset.id}.$ext';
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

        pathFutures.add(
          _photoService.getAssetFilePath(asset).then((path) {
            if (path != null) {
              _filePathCache[fileName] = path;
              fileSizes[fileName] = File(path).lengthSync();
            }
          }),
        );
      }
    }

    // Wait for all file paths to be resolved before starting upload.
    await Future.wait(pathFutures);

    // Patch totalSize into each task now that we have real file sizes.
    for (var i = 0; i < tasks.length; i++) {
      final size = fileSizes[tasks[i].fileName];
      if (size != null && size > 0) {
        tasks[i] = tasks[i].copyWith(totalSize: size);
      }
    }

    if (!mounted) return;

    final baseUrl = 'http://${server.ipAddress}:${server.port}';

    await queueProvider.startUpload(
      tasks: tasks,
      baseUrl: baseUrl,
      deviceId: 'android_device',
      resolveFilePath: (task) => _filePathCache[task.fileName] ?? '',
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
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (!isConnected || isActive) ? null : _startUpload,
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
