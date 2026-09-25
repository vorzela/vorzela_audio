import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'audio_event.dart';

/// MethodChannel / EventChannel names for the streaming player.
const String kVorzelaAudioPlayerChannel = 'com.vorzela.vorzela_audio/player';
const String kVorzelaAudioEventsChannel = 'com.vorzela.vorzela_audio/events';

/// Minimum gap between position events (ms) — keeps Dart isolate light.
const int kPositionEventThrottleMs = 250;

abstract class VorzelaAudioPlatform extends PlatformInterface {
  VorzelaAudioPlatform() : super(token: _token);

  static final Object _token = Object();
  static VorzelaAudioPlatform _instance = _UnimplementedVorzelaAudioPlatform();

  static VorzelaAudioPlatform get instance => _instance;

  static set instance(VorzelaAudioPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int> create() {
    throw UnimplementedError('create() has not been implemented.');
  }

  Future<void> load(
    int playerId, {
    required String uri,
    bool autoPlay = false,
    bool fastStart = true,
  }) {
    throw UnimplementedError('load() has not been implemented.');
  }

  Future<void> play(int playerId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  Future<void> pause(int playerId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  Future<void> seek(int playerId, int positionMs) {
    throw UnimplementedError('seek() has not been implemented.');
  }

  Future<void> setVolume(int playerId, double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  Future<void> disposePlayer(int playerId) {
    throw UnimplementedError('disposePlayer() has not been implemented.');
  }

  /// Foreground playback, media session, and lock-screen controls.
  Future<void> setBackgroundEnabled(
    int playerId, {
    required bool enabled,
  }) {
    throw UnimplementedError('setBackgroundEnabled() has not been implemented.');
  }

  Future<void> updateNowPlaying(
    int playerId, {
    required String title,
    required String artist,
    required int durationMs,
  }) {
    throw UnimplementedError('updateNowPlaying() has not been implemented.');
  }

  Future<void> enableSpectrum(
    int playerId, {
    required bool enabled,
  }) {
    throw UnimplementedError('enableSpectrum() has not been implemented.');
  }

  Stream<AudioEvent> eventsFor(int playerId) {
    throw UnimplementedError('eventsFor() has not been implemented.');
  }

  /// Preload a short sound for overlapping one-shot playback ([VorzelaSoundPool]).
  Future<void> soundPoolLoad(String uri) {
    throw UnimplementedError('soundPoolLoad() has not been implemented.');
  }

  Future<void> soundPoolPlay(String uri, {double volume = 1.0}) {
    throw UnimplementedError('soundPoolPlay() has not been implemented.');
  }

  Future<void> soundPoolDispose() {
    throw UnimplementedError('soundPoolDispose() has not been implemented.');
  }
}

class _UnimplementedVorzelaAudioPlatform extends VorzelaAudioPlatform {}
