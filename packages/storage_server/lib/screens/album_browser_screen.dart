import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager_ui/photo_manager_ui.dart';
import 'package:provider/provider.dart';

import '../providers/providers.dart';

// 存储端 HTTP server 固定跑在 localhost:8765
const _kServerBaseUrl = 'http://localhost:8765';

/// Album browser: left panel (device list + album tree), right panel (MediaGridView).
class AlbumBrowserScreen extends StatefulWidget {
  const AlbumBrowserScreen({super.key});

  @override
  State<AlbumBrowserScreen> createState() => _AlbumBrowserScreenState();
}

class _AlbumBrowserScreenState extends State<AlbumBrowserScreen> {
  ViewMode _viewMode = ViewMode.grid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final albumProvider = context.read<AlbumProvider>();
      // 当相册自动选中时，加载照片列表
      albumProvider.onAutoSelectAlbum = (album) {
        final device = albumProvider.selectedDevice;
        if (device != null) {
          context.read<MediaListProvider>().load(
                deviceId: device.deviceId,
                albumName: album.albumName,
              );
        }
      };

      final deviceProvider = context.read<DeviceListProvider>();
      deviceProvider.refresh().then((_) {
        // 如果只有一个设备，自动选中
        if (deviceProvider.devices.length == 1) {
          albumProvider.selectDevice(deviceProvider.devices.first);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 240,
          child: _LeftPanel(
            onDeviceSelected: (device) {
              context.read<AlbumProvider>().selectDevice(device);
            },
            onAlbumSelected: (album) {
              final albumProvider = context.read<AlbumProvider>();
              albumProvider.selectAlbum(album);
              final device = albumProvider.selectedDevice;
              if (device != null) {
                context.read<MediaListProvider>().load(
                      deviceId: device.deviceId,
                      albumName: album.albumName,
                    );
              }
            },
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: _RightPanel(
          viewMode: _viewMode,
          onViewModeChanged: (mode) => setState(() => _viewMode = mode),
        )),
      ],
    );
  }
}

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({required this.onDeviceSelected, required this.onAlbumSelected});

  final ValueChanged<dynamic> onDeviceSelected;
  final ValueChanged<dynamic> onAlbumSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(l.devices, style: Theme.of(context).textTheme.titleSmall),
        ),
        Consumer<DeviceListProvider>(
          builder: (context, deviceProvider, _) {
            if (deviceProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (deviceProvider.devices.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Text(l.noDevices, style: const TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              children: deviceProvider.devices.map((device) {
                return Consumer<AlbumProvider>(
                  builder: (context, albumProvider, _) {
                    final isSelected =
                        albumProvider.selectedDevice?.deviceId == device.deviceId;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      leading: Icon(
                        device.platform.toLowerCase() == 'ios'
                            ? Icons.phone_iphone
                            : Icons.phone_android,
                        size: 20,
                      ),
                      title: Text(device.deviceName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                      onTap: () => onDeviceSelected(device),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(l.navAlbums, style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(
          child: Consumer<AlbumProvider>(
            builder: (context, albumProvider, _) {
              if (albumProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              return AlbumListView(
                albums: albumProvider.albums,
                selectedAlbum: albumProvider.selectedAlbum,
                onAlbumTap: onAlbumSelected,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({required this.viewMode, required this.onViewModeChanged});

  final ViewMode viewMode;
  final ValueChanged<ViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer<AlbumProvider>(
          builder: (context, albumProvider, _) {
            final album = albumProvider.selectedAlbum;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album?.albumName ?? AppLocalizations.of(context).selectAnAlbum,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  DateRangePicker(
                    onChanged: (range) =>
                        context.read<MediaListProvider>().applyFilter(range),
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: Consumer<MediaListProvider>(
            builder: (context, mediaProvider, _) {
              if (mediaProvider.items.isEmpty && !mediaProvider.isLoading) {
                return Center(child: Text(AppLocalizations.of(context).noMedia));
              }
              return MediaGridView(
                items: mediaProvider.items,
                hasMore: mediaProvider.hasMore,
                onLoadMore: mediaProvider.loadMore,
                viewMode: viewMode,
                onViewModeChanged: onViewModeChanged,
                onItemTap: (item) => MediaViewer.show(
                  context,
                  item: item,
                  serverBaseUrl: _kServerBaseUrl,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
