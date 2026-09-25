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
    final rejection = audioUriRejectionReason(uri);
    if (rejection != null) {
      error = rejection;
      isReady = false;
      notifyListeners();
      return;
    }

    await disposePlayer();
    error = null;
    isReady = false;
    spectrum = null;
    notifyListeners();

    final id = await _platform.create();
    _playerId = id;
    _events = _platform.eventsFor(id).listen(_onEvent);

    try {
      await _platform.load(
        id,
        uri: uri,
        autoPlay: autoPlay,
        fastStart: fastStart,
      );
      if (autoPlay) isPlaying = true;
      await _platform.setVolume(id, volume.clamp(0.0, 1.0));
      if (backgroundEnabled) {
        await _platform.setBackgroundEnabled(id, enabled: true);
      }
      if (spectrumEnabled) {
        await _platform.enableSpectrum(id, enabled: true);
      }
    } on PlatformException catch (e) {
      error = '${e.code}: ${e.message ?? e.details}';
      isPlaying = false;
    } catch (e) {
      error = '$e';
      isPlaying = false;
    }
    notifyListeners();
  }

  void _onEvent(AudioEvent event) {
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
    notifyListeners();
  }

  Future<void> enableBackground(bool enabled) async {
    backgroundEnabled = enabled;
    final id = _playerId;
    if (id != null) {
      await _platform.setBackgroundEnabled(id, enabled: enabled);
    }
    notifyListeners();
  }

  Future<void> enableSpectrum(bool enabled) async {
    spectrumEnabled = enabled;
    if (!enabled) spectrum = null;
    final id = _playerId;
    if (id != null) {
      await _platform.enableSpectrum(id, enabled: enabled);
    }
    notifyListeners();
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
    final id = _playerId;
    if (id == null) return;
    await _platform.play(id);
    isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    final id = _playerId;
    if (id == null) return;
    await _platform.pause(id);
    isPlaying = false;
    notifyListeners();
  }

  Future<void> seek(Duration to) async {
    final id = _playerId;
    if (id == null) return;
    await _platform.seek(id, to.inMilliseconds);
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    final id = _playerId;
    if (id == null) {
      notifyListeners();
      return;
    }
    await _platform.setVolume(id, volume);
    notifyListeners();
  }

  Future<void> disposePlayer() async {
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
    unawaited(disposePlayer());
    super.dispose();
  }
}
