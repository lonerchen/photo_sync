import 'package:common/common.dart';
import 'package:flutter/material.dart';

import 'thumbnail_cell.dart';

/// Display mode for [MediaGridView].
enum ViewMode { grid, list }

/// A virtual-list media browser supporting grid and list modes.
///
/// - Mobile / narrow: 3 columns
/// - Desktop / wide: 5–8 columns adaptive (based on window width)
/// - Triggers [onLoadMore] when the user scrolls near the bottom.
/// - Calls [onVisibleIdsChanged] with the currently visible media IDs so the
///   caller can send `thumbnail_priority` events.
class MediaGridView extends StatefulWidget {
  const MediaGridView({
    super.key,
    required this.items,
    required this.hasMore,
    required this.onLoadMore,
    this.viewMode = ViewMode.grid,
    this.onViewModeChanged,
    this.onItemTap,
    this.onItemLongPress,
    this.onVisibleIdsChanged,
    this.serverBaseUrl = '',
    this.selectedIds = const {},
  });

  final List<MediaItem> items;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final ViewMode viewMode;
  final ValueChanged<ViewMode>? onViewModeChanged;
  final ValueChanged<MediaItem>? onItemTap;
  final ValueChanged<MediaItem>? onItemLongPress;
  final ValueChanged<List<int>>? onVisibleIdsChanged;

  /// Base URL used to build thumbnail URLs, e.g. `http://192.168.1.1:8765`.
  final String serverBaseUrl;

  /// IDs of currently selected items (for restore/multi-select mode).
  final Set<int> selectedIds;

  @override
  State<MediaGridView> createState() => _MediaGridViewState();
}

class _MediaGridViewState extends State<MediaGridView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300 && widget.hasMore) {
      widget.onLoadMore();
    }
  }

  int _columnCount(double width) {
    if (width >= 1400) return 8;
    if (width >= 1200) return 7;
    if (width >= 1000) return 6;
    if (width >= 800) return 5;
    return 3;
  }

  String _thumbnailUrl(MediaItem item) {
    if (widget.serverBaseUrl.isEmpty) return '';
    if (item.thumbnailStatus == ThumbnailStatus.ready) {
      return '${widget.serverBaseUrl}/api/v1/media/${item.id}/thumbnail';
    }
    return '';
  }

  String? _localThumbnailPath(MediaItem item) {
    if (widget.serverBaseUrl.isNotEmpty) return null;
    if (item.thumbnailStatus == ThumbnailStatus.ready) {
      return item.thumbnailPath;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (widget.viewMode == ViewMode.list) {
                return _buildListView();
              }
              return _buildGridView(constraints.maxWidth);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.grid_view),
            isSelected: widget.viewMode == ViewMode.grid,
            onPressed: () => widget.onViewModeChanged?.call(ViewMode.grid),
            tooltip: 'Grid view',
          ),
          IconButton(
            icon: const Icon(Icons.view_list),
            isSelected: widget.viewMode == ViewMode.list,
            onPressed: () => widget.onViewModeChanged?.call(ViewMode.list),
            tooltip: 'List view',
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(double width) {
    final cols = _columnCount(width);
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index >= widget.items.length) return null;
              final item = widget.items[index];
              return ThumbnailCell(
                thumbnailUrl: _thumbnailUrl(item).isEmpty ? null : _thumbnailUrl(item),
                localFilePath: _localThumbnailPath(item),
                mediaType: item.mediaType,
                isSelected: widget.selectedIds.contains(item.id),
                onTap: () => widget.onItemTap?.call(item),
                onLongPress: () => widget.onItemLongPress?.call(item),
              );
            },
            childCount: widget.items.length,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
        ),
        if (widget.hasMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= widget.items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = widget.items[index];
        final url = _thumbnailUrl(item);
        return ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: ThumbnailCell(
              thumbnailUrl: url.isEmpty ? null : url,
              localFilePath: _localThumbnailPath(item),
              mediaType: item.mediaType,
            ),
          ),
          title: Text(item.fileName, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.takenAt != null
                ? DateTime.fromMillisecondsSinceEpoch(item.takenAt!).toString().substring(0, 16)
                : item.albumName,
          ),
          onTap: () => widget.onItemTap?.call(item),
          onLongPress: () => widget.onItemLongPress?.call(item),
        );
      },
    );
  }
}
