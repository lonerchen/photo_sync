import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/common.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/i_server_database.dart';
import '../services/i_thumbnail_queue.dart';
import 'websocket_server.dart';

/// HTTP + WebSocket server for the storage end.
///
/// Starts on [port] (default 8765) and exposes all REST endpoints under
/// `/api/v1` plus a WebSocket upgrade endpoint at `/ws`.
class HttpServerService {
  HttpServerService({
    this.port = 8765,
    required IServerDatabase database,
    required IThumbnailQueue thumbnailQueue,
    required String storagePath,
    Future<String> Function()? storagePathResolver,
  })  : _database = database,
        _thumbnailQueue = thumbnailQueue,
        _initialStoragePath = storagePath,
        _storagePathResolver = storagePathResolver,
        _wsServer = WebSocketServer(
          database: database,
          thumbnailQueue: thumbnailQueue,
        );

  final int port;
  final IServerDatabase _database;
  final IThumbnailQueue _thumbnailQueue;
  final String _initialStoragePath;
  final Future<String> Function()? _storagePathResolver;
  final WebSocketServer _wsServer;

  /// Called on the main isolate after a media item is inserted into the DB.
  /// Receives the inserted [MediaItem] so the UI can refresh immediately.
  void Function(MediaItem item)? onMediaInserted;

  /// Exposes the WebSocket server so callers can wire up the thumbnail queue.
  WebSocketServer get wsServer => _wsServer;

  HttpServer? _server;

  Future<String> _currentStoragePath() async {
    final resolved = await _storagePathResolver?.call();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return _initialStoragePath;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(_buildRouter());

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _wsServer.start();
  }

  Future<void> stop() async {
    _wsServer.stop();
    await _server?.close(force: true);
    _server = null;
  }

  // ---------------------------------------------------------------------------
  // Router
  // ---------------------------------------------------------------------------

  Handler _buildRouter() {
    final router = Router();

    // WebSocket upgrade
    router.get('/ws', _handleWebSocket);

    // Devices
    router.post('/api/v1/devices/register', _registerDevice);
    router.get('/api/v1/devices', _getDevices);
    router.get('/api/v1/devices/<deviceId>/status', _getDeviceStatus);

    // Albums & media
    router.get('/api/v1/devices/<deviceId>/albums', _getAlbums);
    router.get(
      '/api/v1/devices/<deviceId>/albums/<albumName>/media',
      _getMedia,
    );

    // Thumbnail & original
    router.get('/api/v1/media/<mediaId>/thumbnail', _getThumbnail);
    router.get('/api/v1/media/<mediaId>/original', _getOriginal);

    // Upload
    router.post('/api/v1/upload/check-exists', _checkExists);
    router.post('/api/v1/upload/init', _uploadInit);
    router.post('/api/v1/upload/chunk', _uploadChunk);
    router.post('/api/v1/upload/complete', _uploadComplete);

    return router;
  }

  // ---------------------------------------------------------------------------
  // CORS middleware
  // ---------------------------------------------------------------------------

  Middleware _corsMiddleware() => (Handler inner) {
        return (Request request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: _corsHeaders);
          }
          final response = await inner(request);
          return response.change(headers: _corsHeaders);
        };
      };

  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Range, X-Device-Id, X-File-Name, X-Album-Name, X-Offset',
  };

  // ---------------------------------------------------------------------------
  // WebSocket handler
  // ---------------------------------------------------------------------------

  Future<Response> _handleWebSocket(Request request) async {
    final deviceId = request.url.queryParameters['device_id'];
    if (deviceId == null || deviceId.isEmpty) {
      return _badRequest('Missing device_id query parameter');
    }

    final wsHandler = webSocketHandler((WebSocketChannel channel) {
      _wsServer.handleConnect(deviceId, channel);
    });

    return wsHandler(request);
  }

  // ---------------------------------------------------------------------------
  // 5.2 Device registration
  // ---------------------------------------------------------------------------

  Future<Response> _registerDevice(Request request) async {
    try {
      final body = await _parseJson(request);
      final req = DeviceRegisterRequest.fromJson(body);
      final storagePath = await _currentStoragePath();

      // Build a storage sub-path for this device (use deviceId as directory name).
      final deviceStoragePath =
          '$storagePath${Platform.pathSeparator}${req.deviceId}';

      final device = await _database.registerDevice(
        deviceId: req.deviceId,
        deviceName: req.deviceName,
        platform: req.platform,
        storagePath: deviceStoragePath,
      );

      return _ok(device.toJson());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.3 Device query
  // ---------------------------------------------------------------------------

  Future<Response> _getDevices(Request request) async {
    try {
      final devices = await _database.getAllDevices();
      return _ok(devices.map((d) => d.toJson()).toList());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  Future<Response> _getDeviceStatus(Request request, String deviceId) async {
    try {
      final device = await _database.getDevice(deviceId);
      if (device == null) return _notFound('Device not found');
      return _ok(device.toJson());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.4 Album query
  // ---------------------------------------------------------------------------

  Future<Response> _getAlbums(Request request, String deviceId) async {
    try {
      final albums = await _database.getAlbums(deviceId);
      return _ok(albums.map((a) => a.toJson()).toList());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.5 Media list with pagination
  // ---------------------------------------------------------------------------

  Future<Response> _getMedia(
    Request request,
    String deviceId,
    String albumName,
  ) async {
    try {
      final params = request.url.queryParameters;
      final page = int.tryParse(params['page'] ?? '1') ?? 1;
      final pageSize = int.tryParse(params['page_size'] ?? '50') ?? 50;
      final startDate = int.tryParse(params['start_date'] ?? '');
      final endDate = int.tryParse(params['end_date'] ?? '');
      final sortOrder = params['sort_order'] ?? 'desc';

      final result = await _database.getMediaItems(
        deviceId: deviceId,
        albumName: Uri.decodeComponent(albumName),
        page: page,
        pageSize: pageSize,
        startDate: startDate,
        endDate: endDate,
        sortOrder: sortOrder,
      );

      final response = MediaListResponse(
        total: result.total,
        page: page,
        pageSize: pageSize,
        items: result.items,
      );

      return _ok(response.toJson());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.6 Thumbnail
  // ---------------------------------------------------------------------------

  Future<Response> _getThumbnail(Request request, String mediaId) async {
    try {
      final id = int.tryParse(mediaId);
      if (id == null) return _badRequest('Invalid media_id');

      final item = await _database.getMediaItem(id);
      if (item == null) return _notFound('Media not found');

      if (item.thumbnailPath == null ||
          item.thumbnailStatus != ThumbnailStatus.ready) {
        return Response(204); // No content yet
      }

      final file = File(item.thumbnailPath!);
      if (!await file.exists()) return _notFound('Thumbnail file not found');

      final bytes = await file.readAsBytes();
      return Response.ok(
        bytes,
        headers: {
          'Content-Type': 'image/jpeg',
          'Cache-Control': 'public, max-age=86400',
        },
      );
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.7 Original file download (Range support)
  // ---------------------------------------------------------------------------

  Future<Response> _getOriginal(Request request, String mediaId) async {
    try {
      final id = int.tryParse(mediaId);
      if (id == null) return _badRequest('Invalid media_id');

      final item = await _database.getMediaItem(id);
      if (item == null) return _notFound('Media not found');

      final file = File(item.filePath);
      if (!await file.exists()) return _notFound('File not found');

      final fileSize = await file.length();
      final rangeHeader = request.headers['range'];

      if (rangeHeader != null) {
        return _serveRange(file, fileSize, rangeHeader, item.fileName);
      }

      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': _mimeType(item.fileName),
          'Content-Length': fileSize.toString(),
          'Accept-Ranges': 'bytes',
          'Content-Disposition':
              'attachment; filename="${item.fileName}"',
        },
      );
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  Future<Response> _serveRange(
    File file,
    int fileSize,
    String rangeHeader,
    String fileName,
  ) async {
    // Parse "bytes=start-end"
    final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
    if (match == null) {
      return Response(416, headers: {
        'Content-Range': 'bytes */$fileSize',
      });
    }

    final startStr = match.group(1)!;
    final endStr = match.group(2)!;

    final start = startStr.isEmpty ? 0 : int.parse(startStr);
    final end = endStr.isEmpty ? fileSize - 1 : int.parse(endStr);

    if (start >= fileSize || end >= fileSize || start > end) {
      return Response(416, headers: {
        'Content-Range': 'bytes */$fileSize',
      });
    }

    final length = end - start + 1;
    return Response(
      206,
      body: file.openRead(start, end + 1),
      headers: {
        'Content-Type': _mimeType(fileName),
        'Content-Length': length.toString(),
        'Content-Range': 'bytes $start-$end/$fileSize',
        'Accept-Ranges': 'bytes',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 5.8 File dedup check
  // ---------------------------------------------------------------------------

  Future<Response> _checkExists(Request request) async {
    try {
      final body = await _parseJson(request);
      final req = CheckExistsRequest.fromJson(body);

      // Sanitize all fileNames before querying DB.
      final safeFileNames = req.fileNames.map(_safeFileName).toList();

      final existing = await _database.getExistingFileNames(
        deviceId: req.deviceId,
        albumName: req.albumName,
        fileNames: safeFileNames,
      );

      final existingSet = existing.toSet();
      final notExists =
          safeFileNames.where((f) => !existingSet.contains(f)).toList();

      return _ok(CheckExistsResponse(
        exists: existing,
        notExists: notExists,
      ).toJson());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.9 Upload init
  // ---------------------------------------------------------------------------

  /// Sanitizes a fileName so it can be safely used as a flat file name.
  /// Replaces '/' and '\' with '_' to avoid accidental sub-directory creation.
  String _safeFileName(String fileName) => fileName.replaceAll('/', '_').replaceAll('\\', '_');

  Future<Response> _uploadInit(Request request) async {
    try {
      final body = await _parseJson(request);
      final req = UploadInitRequest.fromJson(body);
      final safeFileName = _safeFileName(req.fileName);
      final storagePath = await _currentStoragePath();

      final uploadedBytes = await _database.getUploadedBytes(
        deviceId: req.deviceId,
        fileName: safeFileName,
        albumName: req.albumName,
      );

      // Ensure transfer task record exists.
      final deviceDir =
          '$storagePath${Platform.pathSeparator}${req.deviceId}';
      final tempPath =
          '$deviceDir${Platform.pathSeparator}.tmp_${req.albumName}_$safeFileName';

      await _database.upsertTransferTask(
        deviceId: req.deviceId,
        fileName: safeFileName,
        albumName: req.albumName,
        totalSize: req.totalSize,
        uploadedBytes: uploadedBytes,
        tempFilePath: tempPath,
        taskStatus: 'uploading',
        mediaType: req.mediaType,
        livePhotoPairName: req.livePhotoPairName != null ? _safeFileName(req.livePhotoPairName!) : null,
      );

      return _ok(UploadInitResponse(
        uploadedBytes: uploadedBytes,
        chunkSize: 4 * 1024 * 1024, // 4 MB
      ).toJson());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.10 Chunk upload
  // ---------------------------------------------------------------------------

  Future<Response> _uploadChunk(Request request) async {
    try {
      final contentType = request.headers['content-type'] ?? '';

      String? deviceId, rawFileName, albumName, offsetStr;
      List<int> chunkBytes;

      if (contentType.contains('application/octet-stream')) {
        // 新协议：元数据通过 header 传递，body 是纯二进制 chunk
        deviceId = request.headers['x-device-id'];
        final encodedFileName = request.headers['x-file-name'];
        final encodedAlbumName = request.headers['x-album-name'];
        rawFileName = encodedFileName != null ? Uri.decodeComponent(encodedFileName) : null;
        albumName = encodedAlbumName != null ? Uri.decodeComponent(encodedAlbumName) : null;
        offsetStr = request.headers['x-offset'];
        chunkBytes = await request.read().expand((b) => b).toList();
      } else if (contentType.contains('multipart/form-data')) {
        // 兼容旧协议
        final boundary = _extractBoundary(contentType);
        if (boundary == null) return _badRequest('Missing boundary');
        final bodyBytes = await request.read().expand((b) => b).toList();
        final parts = _parseMultipart(bodyBytes, boundary);
        deviceId = parts['device_id'] as String?;
        rawFileName = parts['file_name'] as String?;
        albumName = parts['album_name'] as String?;
        offsetStr = parts['offset'] as String?;
        chunkBytes = (parts['chunk_bytes'] as List<int>?) ?? [];
      } else {
        return _badRequest('Expected application/octet-stream or multipart/form-data');
      }

      if (deviceId == null || rawFileName == null || albumName == null || offsetStr == null) {
        return _badRequest('Missing required fields');
      }

      final fileName = _safeFileName(rawFileName);
      final offset = int.tryParse(offsetStr);
      if (offset == null) return _badRequest('Invalid offset');
      final storagePath = await _currentStoragePath();

      // Determine temp file path.
      final deviceDir = '$storagePath${Platform.pathSeparator}$deviceId';
      final tempPath = '$deviceDir${Platform.pathSeparator}.tmp_${albumName}_$fileName';

      final tempFile = File(tempPath);
      await tempFile.parent.create(recursive: true);

      // Open for random-access write.
      final raf = await tempFile.open(mode: FileMode.append);
      try {
        await raf.setPosition(offset);
        await raf.writeFrom(chunkBytes);
      } finally {
        await raf.close();
      }

      final newUploaded = offset + chunkBytes.length;
      await _database.updateUploadedBytes(
        deviceId: deviceId,
        fileName: fileName,
        albumName: albumName,
        uploadedBytes: newUploaded,
      );

      return _ok({'uploaded_bytes': newUploaded});
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // 5.11 Upload complete
  // ---------------------------------------------------------------------------

  Future<Response> _uploadComplete(Request request) async {
    try {
      final body = await _parseJson(request);
      final req = UploadCompleteRequest.fromJson(body);
      final safeFileName = _safeFileName(req.fileName);
      final storagePath = await _currentStoragePath();

      final deviceDir =
          '$storagePath${Platform.pathSeparator}${req.deviceId}';
      final tempPath =
          '$deviceDir${Platform.pathSeparator}.tmp_${req.albumName}_$safeFileName';

      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        return _badRequest('Temp file not found');
      }

      final actualSize = await tempFile.length();
      if (actualSize != req.totalSize) {
        return Response(
          422,
          body: jsonEncode({
            'code': 1,
            'message':
                'Size mismatch: expected ${req.totalSize}, got $actualSize',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Move temp file to final location.
      final albumDir =
          '$deviceDir${Platform.pathSeparator}${req.albumName}';
      final finalPath =
          '$albumDir${Platform.pathSeparator}$safeFileName';
      // 创建所有中间目录（fileName 可能含子路径）
      await File(finalPath).parent.create(recursive: true);
      await tempFile.rename(finalPath);

      // Read actual media_type and live_photo_pair_name from transfer_tasks.
      final taskMeta = await _database.getTransferTaskMeta(
        deviceId: req.deviceId,
        fileName: safeFileName,
        albumName: req.albumName,
      );
      final actualMediaType = taskMeta?.mediaType ?? MediaType.image;
      final actualPairName = taskMeta?.livePhotoPairName;

      // Insert media item with correct media type from transfer task.
      final mediaItem = await _database.insertMediaItem(
        deviceId: req.deviceId,
        fileName: safeFileName,
        albumName: req.albumName,
        filePath: finalPath,
        fileSize: req.totalSize,
        mediaType: actualMediaType,
        livePhotoPairName: actualPairName,
      );

      // Mark transfer task complete.
      await _database.completeTransferTask(
        deviceId: req.deviceId,
        fileName: safeFileName,
        albumName: req.albumName,
      );

      // Notify UI immediately so the photo appears without waiting for thumbnail.
      onMediaInserted?.call(mediaItem);

      // Notify connected mobile clients via WebSocket.
      _wsServer.broadcastAll(WsMessage(
        type: WsEventType.mediaInserted,
        data: {
          'media_id': mediaItem.id,
          'album_name': req.albumName,
          'device_id': req.deviceId,
        },
      ));

      // Enqueue thumbnail generation.
      _thumbnailQueue.enqueue(mediaItem.id);

      return _ok(mediaItem.toJson());
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _parseJson(Request request) async {
    final body = await request.readAsString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Response _ok(dynamic data) => Response.ok(
        jsonEncode({'code': 0, 'message': 'ok', 'data': data}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _badRequest(String message) => Response(
        400,
        body: jsonEncode({'code': 1, 'message': message}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _notFound(String message) => Response.notFound(
        jsonEncode({'code': 1, 'message': message}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _serverError(String message) => Response.internalServerError(
        body: jsonEncode({'code': 1, 'message': message}),
        headers: {'Content-Type': 'application/json'},
      );

  String _mimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'heic' || 'heif' => 'image/heic',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mov' => 'video/quicktime',
      'mp4' => 'video/mp4',
      _ => 'application/octet-stream',
    };
  }

  String? _extractBoundary(String contentType) {
    final match = RegExp(r'boundary=([^\s;]+)').firstMatch(contentType);
    return match?.group(1);
  }

  /// Binary-safe multipart parser.
  ///
  /// Returns a map of field name → String value, plus a special key
  /// `chunk_bytes` → List<int> for the binary chunk field.
  Map<String, dynamic> _parseMultipart(List<int> body, String boundary) {
    final result = <String, dynamic>{};
    final boundaryBytes = '--$boundary'.codeUnits;
    final crlf = '\r\n'.codeUnits;
    final crlfcrlf = '\r\n\r\n'.codeUnits;

    // Find all boundary positions
    final positions = <int>[];
    for (var i = 0; i <= body.length - boundaryBytes.length; i++) {
      if (_matchBytes(body, i, boundaryBytes)) {
        positions.add(i);
      }
    }

    for (var pi = 0; pi < positions.length; pi++) {
      final partStart = positions[pi] + boundaryBytes.length;
      // Skip the \r\n after boundary line
      var cursor = partStart;
      if (cursor + 1 < body.length &&
          body[cursor] == 13 && body[cursor + 1] == 10) {
        cursor += 2;
      } else if (cursor < body.length && body[cursor] == 45) {
        // '--' means final boundary
        break;
      } else {
        continue;
      }

      // Find header/body separator \r\n\r\n
      final headerEnd = _indexOfBytes(body, crlfcrlf, cursor);
      if (headerEnd == -1) continue;

      final headerBytes = body.sublist(cursor, headerEnd);
      final headers = String.fromCharCodes(headerBytes);

      final bodyStart = headerEnd + 4;
      // Body ends at next boundary (preceded by \r\n)
      final bodyEnd = pi + 1 < positions.length
          ? positions[pi + 1] - 2 // strip \r\n before boundary
          : body.length;

      if (bodyStart > bodyEnd) continue;

      final nameMatch = RegExp(r'name="([^"]+)"').firstMatch(headers);
      if (nameMatch == null) continue;
      final name = nameMatch.group(1)!;

      if (name == 'chunk') {
        result['chunk_bytes'] = body.sublist(bodyStart, bodyEnd);
      } else {
        result[name] = String.fromCharCodes(body.sublist(bodyStart, bodyEnd));
      }
    }

    return result;
  }

  bool _matchBytes(List<int> haystack, int start, List<int> needle) {
    if (start + needle.length > haystack.length) return false;
    for (var i = 0; i < needle.length; i++) {
      if (haystack[start + i] != needle[i]) return false;
    }
    return true;
  }

  int _indexOfBytes(List<int> haystack, List<int> needle, int start) {
    outer:
    for (var i = start; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
