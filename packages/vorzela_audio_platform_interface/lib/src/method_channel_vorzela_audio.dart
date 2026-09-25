import 'package:flutter/services.dart';

import 'audio_event.dart';
import 'audio_platform.dart';

class MethodChannelVorzelaAudio extends VorzelaAudioPlatform {
  MethodChannelVorzelaAudio({
    MethodChannel? channel,
    EventChannel? events,
  })  : _channel = channel ?? const MethodChannel(kVorzelaAudioPlayerChannel),
        _events = events ?? const EventChannel(kVorzelaAudioEventsChannel);

  final MethodChannel _channel;
  final EventChannel _events;

  /// Flutter's [EventChannel] allows only **one** active native sink. Share one
  /// native subscription and fan-out by `playerId`.
  static Stream<Map<Object?, Object?>>? _sharedRaw;

  static Stream<Map<Object?, Object?>> _rawEventStream(EventChannel events) {
    return _sharedRaw ??= events.receiveBroadcastStream().map((raw) {
      if (raw is Map) return Map<Object?, Object?>.from(raw);
      return <Object?, Object?>{};
    });
  }

  static void registerWith() {
    VorzelaAudioPlatform.instance = MethodChannelVorzelaAudio();
  }

  @override
  Future<int> create() async {
    final id = await _channel.invokeMethod<int>('create');
    return id ?? (throw StateError('create returned null'));
  }

  @override
  Future<void> load(
    int playerId, {
    required String uri,
    bool autoPlay = false,
    bool fastStart = true,
  }) {
    return _channel.invokeMethod<void>('load', {
      'playerId': playerId,
      'uri': uri,
      'autoPlay': autoPlay,
      'fastStart': fastStart,
    });
  }

  @override
  Future<void> play(int playerId) =>
      _channel.invokeMethod<void>('play', {'playerId': playerId});

  @override
  Future<void> pause(int playerId) =>
      _channel.invokeMethod<void>('pause', {'playerId': playerId});

  @override
  Future<void> seek(int playerId, int positionMs) => _channel.invokeMethod<void>(
        'seek',
        {'playerId': playerId, 'positionMs': positionMs},
      );

  @override
  Future<void> setVolume(int playerId, double volume) =>
      _channel.invokeMethod<void>('setVolume', {
        'playerId': playerId,
        'volume': volume,
      });

  @override
  Future<void> disposePlayer(int playerId) =>
      _channel.invokeMethod<void>('dispose', {'playerId': playerId});

  @override
  Future<void> setBackgroundEnabled(
    int playerId, {
    required bool enabled,
  }) =>
      _channel.invokeMethod<void>('setBackgroundEnabled', {
        'playerId': playerId,
        'enabled': enabled,
      });

  @override
  Future<void> updateNowPlaying(
    int playerId, {
    required String title,
    required String artist,
    required int durationMs,
  }) =>
      _channel.invokeMethod<void>('updateNowPlaying', {
        'playerId': playerId,
        'title': title,
        'artist': artist,
        'durationMs': durationMs,
      });

  @override
  Future<void> enableSpectrum(
    int playerId, {
    required bool enabled,
  }) =>
      _channel.invokeMethod<void>('enableSpectrum', {
        'playerId': playerId,
        'enabled': enabled,
      });

  @override
  Stream<AudioEvent> eventsFor(int playerId) {
    return _rawEventStream(_events).where((e) {
      final id = e['playerId'];
      return id == playerId || (id is num && id.toInt() == playerId);
    }).map(_decodeEvent);
  }

  AudioEvent _decodeEvent(Map<Object?, Object?> map) {
    final type = '${map['type']}';
    switch (type) {
      case 'ready':
        return AudioReadyEvent(
          durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        );
      case 'buffering':
        return AudioBufferingEvent(map['isBuffering'] == true);
      case 'position':
        return AudioPositionEvent(
          positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
          bufferedMs: (map['bufferedMs'] as num?)?.toInt() ?? 0,
        );
      case 'error':
        return AudioErrorEvent('${map['message'] ?? 'unknown'}');
      case 'completed':
        return const AudioCompletedEvent();
      case 'spectrum':
        return AudioSpectrumEvent(
          bass: (map['bass'] as num?)?.toDouble() ?? 0,
          mid: (map['mid'] as num?)?.toDouble() ?? 0,
          high: (map['high'] as num?)?.toDouble() ?? 0,
          bands: (map['bands'] as List<Object?>?)
              ?.map((e) => (e as num).toDouble())
              .toList(),
        );
      case 'audioFocusLost':
        return const AudioFocusLostEvent();
      case 'audioFocusGained':
        return const AudioFocusGainedEvent();
      case 'remoteAction':
        return AudioRemoteActionEvent(
          '${map['action'] ?? 'unknown'}',
          seekPositionMs: (map['seekPositionMs'] as num?)?.toInt(),
        );
      default:
        return AudioErrorEvent('Unknown event $type');
    }
  }

  @override
  Future<void> soundPoolLoad(String uri) =>
      _channel.invokeMethod<void>('soundPoolLoad', {'uri': uri});

  @override
  Future<void> soundPoolPlay(String uri, {double volume = 1.0}) =>
      _channel.invokeMethod<void>('soundPoolPlay', {
        'uri': uri,
        'volume': volume,
      });

  @override
  Future<void> soundPoolDispose() =>
      _channel.invokeMethod<void>('soundPoolDispose');
}
