import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio/vorzela_audio.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

class TrackingFakePlatform extends VorzelaAudioPlatform {
  final events = StreamController<AudioEvent>.broadcast();
  final created = <int>[];
  final disposed = <int>[];
  int nextId = 1;

  int get activeCount => created.length - disposed.length;

  @override
  Future<int> create() async {
    final id = nextId++;
    created.add(id);
    return id;
  }

  @override
  Future<void> load(
    int playerId, {
    required String uri,
    bool autoPlay = false,
    bool fastStart = true,
  }) async {
    events.add(const AudioReadyEvent(durationMs: 10000));
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

  late TrackingFakePlatform fake;

  setUp(() {
    fake = TrackingFakePlatform();
    VorzelaAudioPlatform.instance = fake;
  });

  tearDown(() async {
    await fake.events.close();
  });

  test('disposePlayer tears down native id', () async {
    final c = VorzelaAudioController(platform: fake);
    await c.load('https://cdn.example.com/a.m3u8');
    await Future<void>.delayed(Duration.zero);
    expect(fake.activeCount, 1);
    await c.disposePlayer();
    expect(fake.activeCount, 0);
    c.dispose();
  });

  test('README memory knobs stay documented in platform constants', () {
    expect(kPositionEventThrottleMs, 250);
  });
}
