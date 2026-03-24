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
/// - Right-side time scrubber for fast navigation.
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
  final String serverBaseUrl;
  final Set<int> selectedIds;

  @override
  State<MediaGridView> createState() => _MediaGridViewState();
}

class _MediaGridViewState extends State<MediaGridView> {
  final _scrollController = ScrollController();

  // Scrubber drag state
  bool _scrubbing = false;
  double _scrubFraction = 0.0; // 0.0 = top, 1.0 = bottom
  String? _scrubLabel;

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
    // Keep scrub fraction in sync when user scrolls manually
    if (!_scrubbing && pos.maxScrollExtent > 0) {
      setState(() {
        _scrubFraction = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
      });
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

  // ---------------------------------------------------------------------------
  // Scrubber helpers
  // ---------------------------------------------------------------------------

  /// Returns a label for the item at [fraction] position in the list.
  String _labelAt(double fraction) {
    if (widget.items.isEmpty) return '';
    final index = (fraction * (widget.items.length - 1)).round().clamp(0, widget.items.length - 1);
    final item = widget.items[index];
    if (item.takenAt != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(item.takenAt!);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    }
    return '';
  }

  void _onScrubStart(double localY, double trackHeight) {
    _scrubbing = true;
    _updateScrub(localY, trackHeight);
  }

  void _onScrubUpdate(double localY, double trackHeight) {
    _updateScrub(localY, trackHeight);
  }

  void _onScrubEnd() {
    setState(() => _scrubbing = false);
  }

  void _updateScrub(double localY, double trackHeight) {
    final fraction = (localY / trackHeight).clamp(0.0, 1.0);
    setState(() {
      _scrubFraction = fraction;
      _scrubLabel = _labelAt(fraction);
    });

    // Jump scroll position
    final pos = _scrollController.position;
    if (pos.maxScrollExtent > 0) {
      _scrollController.jumpTo(fraction * pos.maxScrollExtent);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = widget.viewMode == ViewMode.list
                  ? _buildListView()
                  : _buildGridView(constraints.maxWidth - _scrubberWidth);
              return Row(
                children: [
                  Expanded(child: content),
                  if (widget.items.isNotEmpty)
                    _TimeScrubber(
                      width: _scrubberWidth,
                      fraction: _scrubFraction,
                      label: _scrubbing ? _scrubLabel : null,
                      onDragStart: (y, h) => _onScrubStart(y, h),
                      onDragUpdate: (y, h) => _onScrubUpdate(y, h),
                      onDragEnd: _onScrubEnd,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static const double _scrubberWidth = 28.0;

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
                ? DateTime.fromMillisecondsSinceEpoch(item.takenAt!)
                    .toString()
                    .substring(0, 16)
                : item.albumName,
          ),
          onTap: () => widget.onItemTap?.call(item),
          onLongPress: () => widget.onItemLongPress?.call(item),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Time scrubber widget
// ---------------------------------------------------------------------------

class _TimeScrubber extends StatelessWidget {
  const _TimeScrubber({
    required this.width,
    required this.fraction,
    required this.label,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double width;
  final double fraction;
  final String? label; // shown while dragging
  final void Function(double localY, double trackHeight) onDragStart;
  final void Function(double localY, double trackHeight) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackHeight = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) =>
                onDragStart(d.localPosition.dy, trackHeight),
            onVerticalDragUpdate: (d) =>
                onDragUpdate(d.localPosition.dy, trackHeight),
            onVerticalDragEnd: (_) => onDragEnd(),
            onTapDown: (d) {
              onDragStart(d.localPosition.dy, trackHeight);
              onDragEnd();
            },
            child: Stack(
              children: [
                // Track line
                Center(
                  child: Container(
                    width: 2,
                    height: trackHeight,
                    color: colorScheme.outlineVariant,
                  ),
                ),
                // Thumb
                Positioned(
                  top: (fraction * trackHeight - 10).clamp(0.0, trackHeight - 20),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 20,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                // Label bubble (shown while dragging)
                if (label != null && label!.isNotEmpty)
                  Positioned(
                    top: (fraction * trackHeight - 14).clamp(0.0, trackHeight - 28),
                    right: width + 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label!,
                        style: TextStyle(
                          color: colorScheme.onInverseSurface,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
