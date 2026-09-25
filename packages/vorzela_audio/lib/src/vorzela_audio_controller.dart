import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

import 'vorzela_audio_spectrum.dart';

typedef VorzelaRemoteActionHandler = void Function(
  String action, {
  int? seekPositionMs,
});

/// Streaming audio controller (HLS, progressive HTTPS, local file, Flutter asset).
class VorzelaAudioController extends ChangeNotifier {
  VorzelaAudioController({VorzelaAudioPlatform? platform})
      : _platform = platform ?? VorzelaAudioPlatform.instance;

  final VorzelaAudioPlatform _platform;

  int? _playerId;
  int _loadGeneration = 0;
  bool _disposed = false;
  bool isReady = false;
  bool isBuffering = false;
  bool isPlaying = false;
  bool backgroundEnabled = false;
  bool spectrumEnabled = false;
  double volume = 1.0;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration buffered = Duration.zero;
  String? error;
  VorzelaAudioSpectrum? spectrum;

  /// Lock-screen / notification media keys (also used by [VorzelaPlaylistController]).
  VorzelaRemoteActionHandler? onRemoteAction;

  /// Fired when native emits [AudioCompletedEvent].
  VoidCallback? onTrackCompleted;

  int? get playerId => _playerId;

  StreamSubscription<AudioEvent>? _events;

  Future<void> load(
    String uri, {
    bool autoPlay = false,
    bool fastStart = true,
  }) async {
    if (_disposed) return;
    final rejection = audioUriRejectionReason(uri);
    if (rejection != null) {
      error = rejection;
      isReady = false;
      _safeNotify();
      return;
    }

    await disposePlayer();
    if (_disposed) return;
    final generation = _loadGeneration;
    error = null;
    isReady = false;
    spectrum = null;
    _safeNotify();

    final id = await _platform.create();
    if (_disposed || generation != _loadGeneration) {
      await _platform.disposePlayer(id);
      return;
    }
    _playerId = id;
    final listenPlayerId = id;
    _events = _platform.eventsFor(id).listen(
          (event) => _onEvent(event, generation, listenPlayerId),
        );

    try {
      await _platform.load(
        id,
        uri: uri,
        autoPlay: autoPlay,
        fastStart: fastStart,
      );
      if (_disposed || generation != _loadGeneration) return;
      if (autoPlay) isPlaying = true;
      await _platform.setVolume(id, volume.clamp(0.0, 1.0));
      if (backgroundEnabled) {
        await _platform.setBackgroundEnabled(id, enabled: true);
      }
      if (spectrumEnabled) {
        await _platform.enableSpectrum(id, enabled: true);
      }
    } on PlatformException catch (e) {
      if (_disposed || generation != _loadGeneration) return;
      error = '${e.code}: ${e.message ?? e.details}';
      isPlaying = false;
      await disposePlayer();
    } catch (e) {
      if (_disposed || generation != _loadGeneration) return;
      error = '$e';
      isPlaying = false;
      await disposePlayer();
    }
    if (!_disposed && generation == _loadGeneration) _safeNotify();
  }

  void _onEvent(AudioEvent event, int generation, int listenPlayerId) {
    if (_disposed ||
        generation != _loadGeneration ||
        _playerId == null ||
        _playerId != listenPlayerId) {
      return;
    }
    switch (event) {
      case AudioReadyEvent(:final durationMs):
        duration = Duration(milliseconds: durationMs);
        isReady = true;
        error = null;
      case AudioBufferingEvent(:final isBuffering):
        this.isBuffering = isBuffering;
      case AudioPositionEvent(:final positionMs, :final bufferedMs):
        position = Duration(milliseconds: positionMs);
        buffered = Duration(milliseconds: bufferedMs);
      case AudioErrorEvent(:final message):
        error = message;
        isPlaying = false;
      case AudioCompletedEvent():
        isPlaying = false;
        if (duration > Duration.zero) {
          position = duration;
        }
        onTrackCompleted?.call();
      case AudioSpectrumEvent(:final bass, :final mid, :final high, :final bands):
        spectrum = VorzelaAudioSpectrum(
          bass: bass,
          mid: mid,
          high: high,
          bands: bands,
        );
      case AudioFocusLostEvent():
        isPlaying = false;
      case AudioFocusGainedEvent():
        break;
      case AudioRemoteActionEvent(:final action, :final seekPositionMs):
        onRemoteAction?.call(action, seekPositionMs: seekPositionMs);
    }
    _safeNotify();
  }

  /// Guards against the dispose race: [dispose] tears down the native player
  /// asynchronously, so a native event can still arrive after this
  /// [ChangeNotifier] is disposed but before its event subscription finishes
  /// cancelling.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> enableBackground(bool enabled) async {
    if (_disposed) return;
    backgroundEnabled = enabled;
    final id = _playerId;
    if (id != null) {
      await _platform.setBackgroundEnabled(id, enabled: enabled);
    }
    _safeNotify();
  }

  Future<void> enableSpectrum(bool enabled) async {
    if (_disposed) return;
    spectrumEnabled = enabled;
    if (!enabled) spectrum = null;
    final id = _playerId;
    if (id != null) {
      await _platform.enableSpectrum(id, enabled: enabled);
    }
    _safeNotify();
  }

  Future<void> syncNowPlaying({
    required String title,
    required String artist,
  }) async {
    final id = _playerId;
    if (id == null) return;
    await _platform.updateNowPlaying(
      id,
      title: title,
      artist: artist,
      durationMs: duration.inMilliseconds,
    );
  }

  Future<void> play() async {
    if (_disposed) return;
    final id = _playerId;
    if (id == null) return;
    await _platform.play(id);
    if (_disposed) return;
    isPlaying = true;
    _safeNotify();
  }

  Future<void> pause() async {
    if (_disposed) return;
    final id = _playerId;
    if (id == null) return;
    await _platform.pause(id);
    if (_disposed) return;
    isPlaying = false;
    _safeNotify();
  }

  Future<void> seek(Duration to) async {
    if (_disposed) return;
    final id = _playerId;
    if (id == null) return;
    await _platform.seek(id, to.inMilliseconds);
  }

  Future<void> setVolume(double value) async {
    if (_disposed) return;
    volume = value.clamp(0.0, 1.0);
    final id = _playerId;
    if (id == null) {
      _safeNotify();
      return;
    }
    await _platform.setVolume(id, volume);
    if (_disposed) return;
    _safeNotify();
  }

  Future<void> disposePlayer() async {
    _loadGeneration++;
    await _events?.cancel();
    _events = null;
    final id = _playerId;
    _playerId = null;
    isReady = false;
    isBuffering = false;
    isPlaying = false;
    spectrum = null;
    if (id != null) {
      await _platform.disposePlayer(id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disposePlayer());
    super.dispose();
  }
}
