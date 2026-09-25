import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio/vorzela_audio.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

class PlaylistFakePlatform extends VorzelaAudioPlatform {
  final events = StreamController<AudioEvent>.broadcast();
  final disposed = <int>[];
  int nextId = 1;
  String? lastUri;

  @override
  Future<int> create() async => nextId++;

  @override
  Future<void> load(
    int playerId, {
    required String uri,
    bool autoPlay = false,
    bool fastStart = true,
  }) async {
    lastUri = uri;
    events.add(const AudioReadyEvent(durationMs: 1000));
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seek(int playerId, int positionMs) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> disposePlayer(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Stream<AudioEvent> eventsFor(int playerId) => events.stream;

  @override
  Future<void> soundPoolLoad(String uri) async {}

  @override
  Future<void> soundPoolPlay(String uri, {double volume = 1.0}) async {}

  @override
  Future<void> soundPoolDispose() async {}

  @override
  Future<void> setBackgroundEnabled(int playerId, {required bool enabled}) async {}

  @override
  Future<void> updateNowPlaying(
    int playerId, {
    required String title,
    required String artist,
    required int durationMs,
  }) async {}

  @override
  Future<void> enableSpectrum(int playerId, {required bool enabled}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playlist auto-advances on completed', () async {
    final fake = PlaylistFakePlatform();
    VorzelaAudioPlatform.instance = fake;
    final audio = VorzelaAudioController(platform: fake);
    final playlist = VorzelaPlaylistController(audio: audio);

    await playlist.setQueue([
      const VorzelaMediaItem(uri: 'https://a.com/1.m3u8', title: 'One'),
      const VorzelaMediaItem(uri: 'https://a.com/2.m3u8', title: 'Two'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(playlist.currentIndex, 0);
    expect(fake.lastUri, 'https://a.com/1.m3u8');

    fake.events.add(const AudioCompletedEvent());
    await Future<void>.delayed(Duration.zero);
    expect(playlist.currentIndex, 1);
    expect(fake.lastUri, 'https://a.com/2.m3u8');

    playlist.dispose();
    expect(fake.disposed, isNotEmpty);
  });

  test('remote next action advances playlist', () async {
    final fake = PlaylistFakePlatform();
    final audio = VorzelaAudioController(platform: fake);
    final playlist = VorzelaPlaylistController(audio: audio);

    await playlist.setQueue([
      const VorzelaMediaItem(uri: 'https://a.com/1.m3u8'),
      const VorzelaMediaItem(uri: 'https://a.com/2.m3u8'),
    ]);
    await Future<void>.delayed(Duration.zero);

    fake.events.add(const AudioRemoteActionEvent('next'));
    await Future<void>.delayed(Duration.zero);
    expect(playlist.currentIndex, 1);

    playlist.dispose();
  });

  test('next wraps with repeatMode.all', () async {
    final fake = PlaylistFakePlatform();
    VorzelaAudioPlatform.instance = fake;
    final audio = VorzelaAudioController(platform: fake);
    final playlist = VorzelaPlaylistController(audio: audio)
      ..repeatMode = VorzelaRepeatMode.all;

    await playlist.setQueue([
      const VorzelaMediaItem(uri: 'https://a.com/1.m3u8'),
      const VorzelaMediaItem(uri: 'https://a.com/2.m3u8'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await playlist.playAt(1);
    await Future<void>.delayed(Duration.zero);
    await playlist.next();
    await Future<void>.delayed(Duration.zero);
    expect(playlist.currentIndex, 0);
    playlist.dispose();
  });
}
