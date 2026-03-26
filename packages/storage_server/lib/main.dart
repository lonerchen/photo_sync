import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'database/server_database.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';
import 'server/http_server_service.dart';
import 'services/discovery_service.dart';
import 'services/i_thumbnail_queue.dart';
import 'services/storage_path_service.dart';
import 'services/thumbnail_queue_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialise database.
    final db = ServerDatabase();
    await db.init();

    // Initialise storage path service.
    final pathService = StoragePathService();

    // Resolve storage path: use persisted path or fall back to Documents dir.
    String storagePath = await pathService.getStoragePath() ??
        (await getApplicationDocumentsDirectory()).path;

    // Use a proxy queue so we can wire up the real queue after server starts.
    final proxyQueue = _ProxyThumbnailQueue();

    // Start HTTP + WebSocket server.
    final httpServer = HttpServerService(
      database: db,
      thumbnailQueue: proxyQueue,
      storagePath: storagePath,
      storagePathResolver: () async =>
          await pathService.getStoragePath() ?? storagePath,
    );
    await httpServer.start();

    // Start LAN discovery broadcast (UDP + mDNS) so mobile clients can find us.
    final discoveryService = DiscoveryService(
      serverId: 'photosync-server',
      serverName: 'PhotoSync 存储端',
      port: httpServer.port,
    );
    await discoveryService.start();

    // Start thumbnail queue service (needs wsServer reference from httpServer).
    final thumbnailQueue = ThumbnailQueueService(
      database: db,
      wsServer: httpServer.wsServer,
      storagePath: storagePath,
      storagePathResolver: () async =>
          await pathService.getStoragePath() ?? storagePath,
    );
    await thumbnailQueue.start();

    // Wire up the real queue.
    proxyQueue.delegate = thumbnailQueue;

    // 启动时把所有 pending 缩略图加入队列
    final pendingIds = await db.getPendingThumbnailIds();
    for (final id in pendingIds) {
      thumbnailQueue.enqueue(id);
    }

    // 创建 providers，在 runApp 之前挂上缩略图回调
    final mediaListProvider = MediaListProvider(database: db);
    final albumProvider = AlbumProvider(database: db);
    final deviceListProvider = DeviceListProvider(database: db);

    Timer? refreshDebounceTimer;
    bool refreshInFlight = false;
    bool refreshQueued = false;
    bool refreshDevicesRequested = false;

    Future<void> scheduleRefresh({required bool includeDevices}) async {
      refreshQueued = true;
      refreshDevicesRequested = refreshDevicesRequested || includeDevices;

      refreshDebounceTimer?.cancel();
      refreshDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
        if (refreshInFlight) return;
        refreshInFlight = true;
        try {
          while (refreshQueued) {
            final needDeviceRefresh = refreshDevicesRequested;
            refreshQueued = false;
            refreshDevicesRequested = false;

            await mediaListProvider.refresh();
            await albumProvider.refresh();
            if (needDeviceRefresh) {
              await deviceListProvider.refresh();
            }
          }
        } finally {
          refreshInFlight = false;
        }
      });
    }

    thumbnailQueue.onThumbnailReady = (_) {
      scheduleRefresh(includeDevices: false);
    };

    httpServer.onMediaInserted = (_) {
      scheduleRefresh(includeDevices: true);
    };

    runApp(StorageServerApp(
      database: db,
      pathService: pathService,
      httpServer: httpServer,
      mediaListProvider: mediaListProvider,
      albumProvider: albumProvider,
      deviceListProvider: deviceListProvider,
    ));
  } catch (e, st) {
    // Show error on screen instead of black screen.
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SelectableText(
              'Startup error:\n$e\n\n$st',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      ),
    ));
  }
}

class StorageServerApp extends StatelessWidget {
  const StorageServerApp({
    super.key,
    required this.database,
    required this.pathService,
    required this.httpServer,
    required this.mediaListProvider,
    required this.albumProvider,
    required this.deviceListProvider,
  });

  final ServerDatabase database;
  final StoragePathService pathService;
  final HttpServerService httpServer;
  final MediaListProvider mediaListProvider;
  final AlbumProvider albumProvider;
  final DeviceListProvider deviceListProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ServerStatusProvider()),
        ChangeNotifierProvider.value(value: deviceListProvider),
        ChangeNotifierProvider.value(value: albumProvider),
        ChangeNotifierProvider.value(value: mediaListProvider),
        ChangeNotifierProvider(create: (_) => ThumbnailQueueProvider()),
        ChangeNotifierProvider(
          create: (_) => StorageSettingsProvider(
            pathService: pathService,
            database: database,
          ),
        ),
        Provider<HttpServerService>.value(value: httpServer),
      ],
      child: MaterialApp(
        title: 'PhotoSync 存储端',
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('zh'),
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MainShell(),
      ),
    );
  }
}

/// Proxy queue that forwards calls to a delegate once it's available.
class _ProxyThumbnailQueue implements IThumbnailQueue {
  IThumbnailQueue? delegate;

  @override
  void enqueue(int mediaId) => delegate?.enqueue(mediaId);

  @override
  void enqueuePriority(int mediaId) => delegate?.enqueuePriority(mediaId);
}
