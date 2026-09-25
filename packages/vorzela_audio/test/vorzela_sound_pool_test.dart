import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio/vorzela_audio.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

class RecordingPoolPlatform extends VorzelaAudioPlatform {
  final loaded = <String>[];
  final played = <({String uri, double volume})>[];
  var disposeCalls = 0;

  @override
  Future<int> create() async => 1;

  @override
  Future<void> load(
    int playerId, {
    required String uri,
    bool autoPlay = false,
    bool fastStart = true,
  }) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seek(int playerId, int positionMs) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> disposePlayer(int playerId) async {}

  @override
  Stream<AudioEvent> eventsFor(int playerId) => const Stream.empty();

  @override
  Future<void> soundPoolLoad(String uri) async {
    loaded.add(uri);
  }

  @override
  Future<void> soundPoolPlay(String uri, {double volume = 1.0}) async {
    played.add((uri: uri, volume: volume));
  }

  @override
  Future<void> soundPoolDispose() async {
    disposeCalls++;
  }

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
  test('sound pool load play dispose smoke', () async {
    final platform = RecordingPoolPlatform();
    final pool = VorzelaSoundPool(platform: platform);
    const uri = 'file:///tmp/click.wav';

    await pool.load(uri);
    expect(pool.isLoaded(uri), isTrue);
    expect(platform.loaded, [uri]);

    await pool.play(uri, volume: 0.75);
    expect(platform.played.single.uri, uri);
    expect(platform.played.single.volume, 0.75);

    await pool.dispose();
    expect(platform.disposeCalls, 1);
    expect(pool.isLoaded(uri), isFalse);
  });

  test('play auto-loads when not preloaded', () async {
    final platform = RecordingPoolPlatform();
    final pool = VorzelaSoundPool(platform: platform);
    const uri = 'https://cdn.example/sfx.wav';

    await pool.play(uri);
    expect(platform.loaded, [uri]);
    expect(platform.played, isNotEmpty);
  });
}
