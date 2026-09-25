import 'package:flutter/material.dart';
import 'package:vorzela_audio/vorzela_audio.dart';

/// Playlist + chrome demo. Replace sample URLs with your HTTPS / HLS audio.
void main() => runApp(const AudioExampleApp());

class AudioExampleApp extends StatelessWidget {
  const AudioExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: AudioPlaylistPage(),
    );
  }
}

class AudioPlaylistPage extends StatefulWidget {
  const AudioPlaylistPage({super.key});

  @override
  State<AudioPlaylistPage> createState() => _AudioPlaylistPageState();
}

class _AudioPlaylistPageState extends State<AudioPlaylistPage> {
  late final VorzelaPlaylistController playlist;

  @override
  void initState() {
    super.initState();
    playlist = VorzelaPlaylistController()
      ..repeatMode = VorzelaRepeatMode.all;
    // Background + spectrum: call after first load on a real device.
    playlist.audio.enableBackground(true);
    playlist.audio.enableSpectrum(true);
    playlist.setQueue(const [
      VorzelaMediaItem(
        uri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        title: 'SoundHelix 1',
        artist: 'SoundHelix',
      ),
      VorzelaMediaItem(
        uri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        title: 'SoundHelix 2',
        artist: 'SoundHelix',
      ),
    ]);
  }

  @override
  void dispose() {
    playlist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('vorzela_audio playlist')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: VorzelaAudioPlayerChrome(controller: playlist.audio),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: playlist.previous,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: playlist.next,
              ),
            ],
          ),
          Expanded(child: VorzelaPlaylistList(playlist: playlist)),
        ],
      ),
    );
  }
}
