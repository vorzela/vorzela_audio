import 'package:flutter/material.dart';

import '../vorzela_media_item.dart';
import '../vorzela_playlist_controller.dart';

class VorzelaPlaylistList extends StatelessWidget {
  const VorzelaPlaylistList({
    super.key,
    required this.playlist,
  });

  final VorzelaPlaylistController playlist;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playlist,
      builder: (context, _) {
        return ListView.builder(
          itemCount: playlist.items.length,
          itemBuilder: (context, index) {
            final item = playlist.items[index];
            final selected = index == playlist.currentIndex;
            return ListTile(
              selected: selected,
              title: Text(item.title ?? item.uri),
              subtitle: item.artist != null ? Text(item.artist!) : null,
              onTap: () => playlist.playIndex(index),
            );
          },
        );
      },
    );
  }
}
