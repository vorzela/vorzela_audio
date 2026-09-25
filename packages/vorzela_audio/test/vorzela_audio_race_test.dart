import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio/vorzela_audio.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

class SlowFakeAudioPlatform extends VorzelaAudioPlatform {
  SlowFakeAudioPlatform({this.loadDelay = Duration.zero});

  final Duration loadDelay;
  final _eventsByPlayer = <int, StreamController<AudioEvent>>{};
  final disposed = <int>[];
  final created = <int>[];
  int nextId = 1;
  Object? loadError;

  StreamController<AudioEvent> _eventsForPlayer(int playerId) {
    return _eventsByPlayer.putIfAbsent(
      playerId,
      () => StreamController<AudioEvent>.broadcast(),
    );
  }

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
    await Future<void>.delayed(loadDelay);
    if (loadError != null) throw loadError!;
    _eventsForPlayer(playerId).add(const AudioReadyEvent(durationMs: 1000));
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
  Stream<AudioEvent> eventsFor(int playerId) => _eventsForPlayer(playerId).stream;

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

  test('overlapping loads leave one active player and dispose orphans', () async {
    final fake = SlowFakeAudioPlatform(
      loadDelay: const Duration(milliseconds: 30),
    );
    final c = VorzelaAudioController(platform: fake);

    final first = c.load('https://example.com/a.m3u8');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = c.load('https://example.com/b.m3u8');
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);

    expect(c.playerId, isNotNull);
    expect(fake.disposed.length, greaterThanOrEqualTo(1));
    expect(fake.created.length - fake.disposed.length, lessThanOrEqualTo(1));

    await c.disposePlayer();
    c.dispose();
    for (final c in fake._eventsByPlayer.values) {
      await c.close();
    }
  });

  test('load failure disposes native player (no leak)', () async {
    final fake = SlowFakeAudioPlatform();
    fake.loadError = PlatformException(code: 'fail', message: 'nope');
    final c = VorzelaAudioController(platform: fake);

    await c.load('https://example.com/bad.m3u8');
    expect(c.error, contains('fail'));
    expect(c.playerId, isNull);
    expect(fake.created.length, fake.disposed.length);

    c.dispose();
    for (final c in fake._eventsByPlayer.values) {
      await c.close();
    }
  });

  test('stale ready events from disposed player id are ignored', () async {
    final fake = SlowFakeAudioPlatform(
      loadDelay: const Duration(milliseconds: 50),
    );
    final c = VorzelaAudioController(platform: fake);

    final first = c.load('https://example.com/a.m3u8');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final staleId = fake.created.last;
    await c.load('https://example.com/b.m3u8');
    await first;
    await Future<void>.delayed(Duration.zero);

    fake._eventsForPlayer(staleId).add(
          const AudioReadyEvent(durationMs: 999999),
        );
    await Future<void>.delayed(Duration.zero);
    expect(c.duration.inMilliseconds, isNot(999999));
    expect(fake.disposed, contains(staleId));

    await c.disposePlayer();
    c.dispose();
    for (final c in fake._eventsByPlayer.values) {
      await c.close();
    }
  });

  test('dispose during in-flight load does not throw', () async {
    final fake = SlowFakeAudioPlatform(
      loadDelay: const Duration(milliseconds: 50),
    );
    final c = VorzelaAudioController(platform: fake);

    unawaited(c.load('https://example.com/slow.m3u8'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fake.created.length, fake.disposed.length);
    for (final c in fake._eventsByPlayer.values) {
      await c.close();
    }
  });

  test('late native event after dispose does not throw', () async {
    final fake = SlowFakeAudioPlatform();
    final c = VorzelaAudioController(platform: fake);
    await c.load('https://example.com/a.mp3');
    final id = c.playerId!;
    c.dispose();
    // Event arrives after ChangeNotifier.dispose but before/during cancel.
    fake._eventsByPlayer[id]?.add(
      const AudioPositionEvent(positionMs: 1000, bufferedMs: 2000),
    );
    await Future<void>.delayed(Duration.zero);
    for (final c in fake._eventsByPlayer.values) {
      await c.close();
    }
  });
}
