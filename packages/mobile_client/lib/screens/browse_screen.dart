import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager_ui/photo_manager_ui.dart';
import 'package:provider/provider.dart';

import '../database/mobile_database.dart';
import '../providers/album_provider.dart';
import '../providers/media_list_provider.dart';
import '../providers/restore_provider.dart';
import '../services/connection_service.dart';
import '../services/discovery_service.dart';
import 'restore_screen.dart';

/// Main browse screen for the mobile client.
///
/// - Shows a "not connected" page when disconnected (15.7)
/// - Shows album list + media grid when connected (15.1, 15.2)
/// - Handles thumbnail_ready WebSocket events (15.4)
/// - Opens MediaViewer on thumbnail tap (15.5)
/// - Uses two-panel layout on tablet, navigation-based on phone
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.db});

  final MobileDatabase db;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  StreamSubscription<WsMessage>? _wsSub;
  ViewMode _viewMode = ViewMode.grid;
  bool _restoreMode = false;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    final connectionService = context.read<ConnectionService>();
    final discoveryService = context.read<DiscoveryService>();
    _subscribeToWsMessages(connectionService);

    // Start server discovery
    discoveryService.startDiscovery();

    // Try auto-connect from last known server
    connectionService.tryAutoConnect(widget.db, _deviceId()).then((_) {
      if (connectionService.status == ConnectionStatus.connected) {
        _loadAlbums(connectionService);
      }
    });
  }

  String _deviceId() {
    // Use a stable device identifier
    return 'android_device';
  }

  void _subscribeToWsMessages(ConnectionService connectionService) {
    _wsSub?.cancel();
    _wsSub = connectionService.messageStream.listen((msg) {
      if (msg.type == WsEventType.thumbnailReady) {
        final mediaId = msg.data['media_id'] as int?;
        final thumbnailUrl = msg.data['thumbnail_url'] as String?;
        if (mediaId != null && thumbnailUrl != null) {
          context.read<MediaListProvider>().refreshItem(mediaId, thumbnailUrl);
        }
      } else if (msg.type == WsEventType.mediaInserted) {
        // 新照片上传完成，防抖 1 秒后刷新（避免批量上传时频繁请求）
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(seconds: 1), () {
          if (!mounted) return;
          context.read<MediaListProvider>().reload();
          context.read<AlbumProvider>().refreshAlbums();
        });
      }
    });
  }

  void _loadAlbums(ConnectionService connectionService) {
    final server = connectionService.currentServer;
    if (server == null) return;
    final baseUrl = 'http://${server.ipAddress}:${server.port}';
    context.read<AlbumProvider>().loadAlbums(baseUrl, _deviceId());
  }

  void _onAlbumSelected(Album album) {
    final connectionService = context.read<ConnectionService>();
    final server = connectionService.currentServer;
    if (server == null) return;

    final albumProvider = context.read<AlbumProvider>();
    albumProvider.selectAlbum(album);

    final baseUrl = 'http://${server.ipAddress}:${server.port}';
    context
        .read<MediaListProvider>()
        .load(baseUrl, _deviceId(), album.albumName);
  }

  void _onItemTap(MediaItem item) {
    final restoreProvider = context.read<RestoreProvider>();
    if (_restoreMode) {
      restoreProvider.toggleSelection(item.id);
      return;
    }
    final server = context.read<ConnectionService>().currentServer;
    if (server == null) return;
    final baseUrl = 'http://${server.ipAddress}:${server.port}';
    MediaViewer.show(context, item: item, serverBaseUrl: baseUrl);
  }

  void _onItemLongPress(MediaItem item) {
    if (!_restoreMode) {
      setState(() => _restoreMode = true);
      context.read<RestoreProvider>().toggleSelection(item.id);
    }
  }

  void _exitRestoreMode() {
    setState(() => _restoreMode = false);
    context.read<RestoreProvider>().clearSelection();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionService = context.watch<ConnectionService>();
    final isConnected = connectionService.status == ConnectionStatus.connected;
    final l = AppLocalizations.of(context);

    if (!isConnected) {
      return _NotConnectedPage(
        onConnected: () => _loadAlbums(connectionService),
      );
    }

    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(_restoreMode ? l.selectToRestore : l.browseTitle),
        actions: [
          if (!_restoreMode)
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: l.restorePhotos,
              onPressed: () => setState(() => _restoreMode = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l.exitRestoreMode,
              onPressed: _exitRestoreMode,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isTablet
                ? _TwoPanelLayout(
                    onAlbumSelected: _onAlbumSelected,
                    onItemTap: _onItemTap,
                    onItemLongPress: _onItemLongPress,
                    viewMode: _viewMode,
                    onViewModeChanged: (m) => setState(() => _viewMode = m),
                    restoreMode: _restoreMode,
                  )
                : _PhoneLayout(
                    onAlbumSelected: _onAlbumSelected,
                    onItemTap: _onItemTap,
                    onItemLongPress: _onItemLongPress,
                    viewMode: _viewMode,
                    onViewModeChanged: (m) => setState(() => _viewMode = m),
                    restoreMode: _restoreMode,
                  ),
          ),
          if (_restoreMode)
            Builder(
              builder: (ctx) {
                final server =
                    context.read<ConnectionService>().currentServer;
                final baseUrl = server != null
                    ? 'http://${server.ipAddress}:${server.port}'
                    : '';
                final items = context.read<MediaListProvider>().items;
                return RestoreBottomBar(
                  allItems: items,
                  serverBaseUrl: baseUrl,
                  onExitRestoreMode: _exitRestoreMode,
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Not-connected page (15.7)
// ---------------------------------------------------------------------------

class _NotConnectedPage extends StatefulWidget {
  const _NotConnectedPage({required this.onConnected});
  final VoidCallback onConnected;

  @override
  State<_NotConnectedPage> createState() => _NotConnectedPageState();
}

class _NotConnectedPageState extends State<_NotConnectedPage> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8765');
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLastServer());
  }

  /// 从数据库读取上次连接的服务器，填入输入框（不自动重连，_init 已经尝试过了）
  Future<void> _loadLastServer() async {
    final db = context.findAncestorWidgetOfExactType<BrowseScreen>()?.db;
    if (db == null) return;
    final last = await db.connectedServersDao.getLastConnectedServer();
    if (last == null || !mounted) return;

    setState(() {
      _ipController.text = last.ipAddress;
      _portController.text = last.port.toString();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8765;
    final l = AppLocalizations.of(context);
    if (ip.isEmpty) {
      setState(() => _error = l.enterIpError);
      return;
    }

    setState(() { _connecting = true; _error = null; });

    final server = ServerInfo(
      serverId: '$ip:$port',
      serverName: 'Storage Server',
      ipAddress: ip,
      port: port,
    );

    final connectionService = context.read<ConnectionService>();
    final ok = await connectionService.connect(server, 'android_device');

    if (!mounted) return;
    setState(() => _connecting = false);

    if (ok) {
      final db = context.findAncestorWidgetOfExactType<BrowseScreen>()?.db;
      await db?.connectedServersDao.upsertServer(server);
      widget.onConnected();
    } else {
      setState(() => _error = l.connectionFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final discoveryService = context.watch<DiscoveryService>();
    final servers = discoveryService.servers;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 72, color: Colors.grey),
              const SizedBox(height: 24),
              Text(
                l.notConnectedToStorage,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              if (servers.isNotEmpty) ...[
                Text(l.discoveredServers, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...servers.map((s) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.storage),
                    title: Text(s.serverName),
                    subtitle: Text('${s.ipAddress}:${s.port}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _connecting ? null : () {
                      _ipController.text = s.ipAddress;
                      _portController.text = s.port.toString();
                      _connect();
                    },
                  ),
                )),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
              ],

              Text(l.manualInputAddress, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: l.serverIpAddress,
                  hintText: l.serverIpHint,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                enabled: !_connecting,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: l.port,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: !_connecting,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _connecting ? null : _connect,
                  child: _connecting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.connect),
                ),
              ),
              const SizedBox(height: 16),
              if (servers.isEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(l.scanningLan, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Two-panel layout (tablet)
// ---------------------------------------------------------------------------

class _TwoPanelLayout extends StatelessWidget {
  const _TwoPanelLayout({
    required this.onAlbumSelected,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.restoreMode,
  });

  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<MediaItem> onItemTap;
  final ValueChanged<MediaItem> onItemLongPress;
  final ViewMode viewMode;
  final ValueChanged<ViewMode> onViewModeChanged;
  final bool restoreMode;

  @override
  Widget build(BuildContext context) {
    final albumProvider = context.watch<AlbumProvider>();
    final mediaProvider = context.watch<MediaListProvider>();
    final connectionService = context.read<ConnectionService>();
    final server = connectionService.currentServer;
    final baseUrl =
        server != null ? 'http://${server.ipAddress}:${server.port}' : '';

    return Row(
      children: [
        // Left panel: album list
        SizedBox(
          width: 260,
          child: Column(
            children: [
              if (albumProvider.isLoading)
                const LinearProgressIndicator()
              else
                const SizedBox(height: 4),
              Expanded(
                child: AlbumListView(
                  albums: albumProvider.albums,
                  selectedAlbum: albumProvider.selectedAlbum,
                  onAlbumTap: onAlbumSelected,
                  serverBaseUrl: baseUrl,
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right panel: media grid
        Expanded(
          child: _MediaPanel(
            mediaProvider: mediaProvider,
            baseUrl: baseUrl,
            onItemTap: onItemTap,
            onItemLongPress: onItemLongPress,
            viewMode: viewMode,
            onViewModeChanged: onViewModeChanged,
            restoreMode: restoreMode,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Phone layout (navigation-based)
// ---------------------------------------------------------------------------

class _PhoneLayout extends StatefulWidget {
  const _PhoneLayout({
    required this.onAlbumSelected,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.restoreMode,
  });

  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<MediaItem> onItemTap;
  final ValueChanged<MediaItem> onItemLongPress;
  final ViewMode viewMode;
  final ValueChanged<ViewMode> onViewModeChanged;
  final bool restoreMode;

  @override
  State<_PhoneLayout> createState() => _PhoneLayoutState();
}

class _PhoneLayoutState extends State<_PhoneLayout> {
  bool _showingMedia = false;

  void _selectAlbum(Album album) {
    widget.onAlbumSelected(album);
    setState(() => _showingMedia = true);
  }

  @override
  Widget build(BuildContext context) {
    final albumProvider = context.watch<AlbumProvider>();
    final mediaProvider = context.watch<MediaListProvider>();
    final connectionService = context.read<ConnectionService>();
    final server = connectionService.currentServer;
    final baseUrl =
        server != null ? 'http://${server.ipAddress}:${server.port}' : '';

    if (!_showingMedia) {
      return Column(
        children: [
          if (albumProvider.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: AlbumListView(
              albums: albumProvider.albums,
              selectedAlbum: albumProvider.selectedAlbum,
              onAlbumTap: _selectAlbum,
              serverBaseUrl: baseUrl,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Back button row
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: Text(AppLocalizations.of(context).back),
              onPressed: () => setState(() => _showingMedia = false),
            ),
            if (albumProvider.selectedAlbum != null)
              Expanded(
                child: Text(
                  albumProvider.selectedAlbum!.albumName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        Expanded(
          child: _MediaPanel(
            mediaProvider: mediaProvider,
            baseUrl: baseUrl,
            onItemTap: widget.onItemTap,
            onItemLongPress: widget.onItemLongPress,
            viewMode: widget.viewMode,
            onViewModeChanged: widget.onViewModeChanged,
            restoreMode: widget.restoreMode,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared media panel (grid + date filter)
// ---------------------------------------------------------------------------

class _MediaPanel extends StatelessWidget {
  const _MediaPanel({
    required this.mediaProvider,
    required this.baseUrl,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.restoreMode,
  });

  final MediaListProvider mediaProvider;
  final String baseUrl;
  final ValueChanged<MediaItem> onItemTap;
  final ValueChanged<MediaItem> onItemLongPress;
  final ViewMode viewMode;
  final ValueChanged<ViewMode> onViewModeChanged;
  final bool restoreMode;

  @override
  Widget build(BuildContext context) {
    if (mediaProvider.isLoading && mediaProvider.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!mediaProvider.isLoading && mediaProvider.items.isEmpty) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DateRangePicker(
                  onChanged: (range) =>
                      context.read<MediaListProvider>().applyFilter(range),
                ),
              ),
              Consumer<MediaListProvider>(
                builder: (context, provider, _) => IconButton(
                  icon: Icon(
                    provider.sortOrder == 'desc'
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                  ),
                  tooltip: provider.sortOrder == 'desc'
                      ? AppLocalizations.of(context).sortNewestFirst
                      : AppLocalizations.of(context).sortOldestFirst,
                  onPressed: () =>
                      context.read<MediaListProvider>().toggleSortOrder(),
                ),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => context.read<MediaListProvider>().reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 200,
                    child: Center(child: Text(AppLocalizations.of(context).noPhotosInAlbum)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DateRangePicker(
                onChanged: (range) =>
                    context.read<MediaListProvider>().applyFilter(range),
              ),
            ),
            // 排序按钮
            Consumer<MediaListProvider>(
              builder: (context, provider, _) => IconButton(
                icon: Icon(
                  provider.sortOrder == 'desc'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                tooltip: provider.sortOrder == 'desc'
                    ? AppLocalizations.of(context).sortNewestFirst
                    : AppLocalizations.of(context).sortOldestFirst,
                onPressed: () =>
                    context.read<MediaListProvider>().toggleSortOrder(),
              ),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => context.read<MediaListProvider>().reload(),
            child: Consumer<RestoreProvider>(
              builder: (context, restoreProvider, _) => MediaGridView(
                items: mediaProvider.items,
                hasMore: mediaProvider.hasMore,
                onLoadMore: () => context.read<MediaListProvider>().loadMore(),
                viewMode: viewMode,
                onViewModeChanged: onViewModeChanged,
                onItemTap: onItemTap,
                onItemLongPress: onItemLongPress,
                serverBaseUrl: baseUrl,
                selectedIds: restoreMode ? restoreProvider.selectedIds : const {},
              ),
            ),
          ),
        ),
      ],
    );
  }
}
