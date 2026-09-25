import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio/vorzela_audio.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

class PlaylistRaceFake extends VorzelaAudioPlatform {
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

  test('completed racing manual next advances once', () async {
    final fake = PlaylistRaceFake();
    final audio = VorzelaAudioController(platform: fake);
    final playlist = VorzelaPlaylistController(audio: audio);

    await playlist.setQueue([
      const VorzelaMediaItem(uri: 'https://a.com/1.m3u8'),
      const VorzelaMediaItem(uri: 'https://a.com/2.m3u8'),
      const VorzelaMediaItem(uri: 'https://a.com/3.m3u8'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(playlist.currentIndex, 0);

    fake.events.add(const AudioCompletedEvent());
    unawaited(playlist.next());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(playlist.currentIndex, 1);
    expect(fake.lastUri, 'https://a.com/2.m3u8');

    playlist.dispose();
    await fake.events.close();
  });

  test('rapid next/prev does not corrupt index', () async {
    final fake = PlaylistRaceFake();
    final audio = VorzelaAudioController(platform: fake);
    final playlist = VorzelaPlaylistController(audio: audio);

    await playlist.setQueue([
      const VorzelaMediaItem(uri: 'https://a.com/1.m3u8'),
      const VorzelaMediaItem(uri: 'https://a.com/2.m3u8'),
      const VorzelaMediaItem(uri: 'https://a.com/3.m3u8'),
    ]);
    await Future<void>.delayed(Duration.zero);

    await Future.wait([
      playlist.next(),
      playlist.next(),
      playlist.previous(),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(playlist.currentIndex, inInclusiveRange(0, 2));

    playlist.dispose();
    await fake.events.close();
  });
}
