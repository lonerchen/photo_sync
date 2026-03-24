import 'package:cached_network_image/cached_network_image.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';

/// A list of albums grouped by device.
class AlbumListView extends StatelessWidget {
  const AlbumListView({
    super.key,
    required this.albums,
    this.selectedAlbum,
    this.onAlbumTap,
    this.serverBaseUrl = '',
  });

  final List<Album> albums;
  final Album? selectedAlbum;
  final ValueChanged<Album>? onAlbumTap;
  final String serverBaseUrl;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const Center(child: Text('No albums'));
    }
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final isSelected = selectedAlbum?.albumName == album.albumName;
        return ListTile(
          selected: isSelected,
          leading: _AlbumCover(
            coverUrl: album.coverThumbnailUrl != null
                ? '$serverBaseUrl${album.coverThumbnailUrl}'
                : null,
          ),
          title: Text(album.albumName, overflow: TextOverflow.ellipsis),
          subtitle: Text('${album.mediaCount} photos'),
          onTap: () => onAlbumTap?.call(album),
        );
      },
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({this.coverUrl});
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null) {
      return Container(
        width: 40,
        height: 40,
        color: Colors.grey[200],
        child: const Icon(Icons.photo_album, color: Colors.grey),
      );
    }
    return CachedNetworkImage(
      imageUrl: coverUrl!,
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(width: 40, height: 40, color: Colors.grey[200]),
      errorWidget: (_, __, ___) => Container(
        width: 40,
        height: 40,
        color: Colors.grey[200],
        child: const Icon(Icons.photo_album, color: Colors.grey),
      ),
    );
  }
}
