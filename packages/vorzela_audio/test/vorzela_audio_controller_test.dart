import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio/vorzela_audio.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

class FakeVorzelaAudioPlatform extends VorzelaAudioPlatform {
  final events = StreamController<AudioEvent>.broadcast();
  final disposed = <int>[];
  int nextId = 1;
  String? lastUri;
  Object? loadError;

  @override
  Future<int> create() async => nextId++;

  @override
  Future<void> load(
    int playerId, {
    required String uri,
    bool autoPlay = false,
    bool fastStart = true,
  }) async {
    if (loadError != null) throw loadError!;
    lastUri = uri;
    events.add(const AudioReadyEvent(durationMs: 60000));
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

  bool backgroundEnabled = false;
  bool spectrumEnabled = false;

  @override
  Future<void> setBackgroundEnabled(int playerId, {required bool enabled}) async {
    backgroundEnabled = enabled;
  }

  @override
  Future<void> updateNowPlaying(
    int playerId, {
    required String title,
    required String artist,
    required int durationMs,
  }) async {}

  @override
  Future<void> enableSpectrum(int playerId, {required bool enabled}) async {
    spectrumEnabled = enabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller load play dispose via fake platform', () async {
    final fake = FakeVorzelaAudioPlatform();
    VorzelaAudioPlatform.instance = fake;
    final c = VorzelaAudioController(platform: fake);

    await c.load('https://example.com/master.m3u8', autoPlay: true);
    await Future<void>.delayed(Duration.zero);
    expect(fake.lastUri, 'https://example.com/master.m3u8');
    expect(c.isReady, isTrue);
    expect(c.isPlaying, isTrue);
    expect(c.duration.inMilliseconds, 60000);

    await c.pause();
    expect(c.isPlaying, isFalse);

    await c.disposePlayer();
    expect(fake.disposed, isNotEmpty);
    c.dispose();
  });

  test('position and error events update controller', () async {
    final fake = FakeVorzelaAudioPlatform();
    final c = VorzelaAudioController(platform: fake);
    await c.load('https://example.com/a.m3u8');
    await Future<void>.delayed(Duration.zero);

    fake.events.add(const AudioPositionEvent(positionMs: 1500, bufferedMs: 3000));
    await Future<void>.delayed(Duration.zero);
    expect(c.position.inMilliseconds, 1500);
    expect(c.buffered.inMilliseconds, 3000);

    fake.events.add(const AudioErrorEvent('boom'));
    await Future<void>.delayed(Duration.zero);
    expect(c.error, 'boom');
    expect(c.isPlaying, isFalse);

    await c.disposePlayer();
    c.dispose();
  });

  test('http uri rejected before platform load', () async {
    final fake = FakeVorzelaAudioPlatform();
    final c = VorzelaAudioController(platform: fake);
    await c.load('http://example.com/a.m3u8');
    expect(c.error, contains('https'));
    expect(c.isReady, isFalse);
    expect(fake.lastUri, isNull);
    c.dispose();
  });

  test('spectrum and focus events update controller', () async {
    final fake = FakeVorzelaAudioPlatform();
    final c = VorzelaAudioController(platform: fake);
    await c.load('https://example.com/a.m3u8');
    await Future<void>.delayed(Duration.zero);

    fake.events.add(const AudioSpectrumEvent(bass: 0.8, mid: 0.4, high: 0.2));
    await Future<void>.delayed(Duration.zero);
    expect(c.spectrum?.bass, 0.8);
    expect(c.spectrum?.mid, 0.4);

    fake.events.add(const AudioFocusLostEvent());
    await Future<void>.delayed(Duration.zero);
    expect(c.isPlaying, isFalse);

    await c.disposePlayer();
    c.dispose();
  });

  test('enableBackground and enableSpectrum forward to platform', () async {
    final fake = FakeVorzelaAudioPlatform();
    final c = VorzelaAudioController(platform: fake);
    await c.enableBackground(true);
    await c.load('https://example.com/a.m3u8');
    expect(fake.backgroundEnabled, isTrue);
    await c.enableSpectrum(true);
    expect(fake.spectrumEnabled, isTrue);
    await c.disposePlayer();
    c.dispose();
  });

  test('reload disposes previous native player', () async {
    final fake = FakeVorzelaAudioPlatform();
    final c = VorzelaAudioController(platform: fake);
    await c.load('https://cdn.example.com/a.m3u8');
    await Future<void>.delayed(Duration.zero);
    final first = fake.nextId - 1;

    await c.load('https://cdn.example.com/b.m3u8');
    await Future<void>.delayed(Duration.zero);
    expect(fake.disposed, contains(first));

    await c.disposePlayer();
    c.dispose();
  });
}
