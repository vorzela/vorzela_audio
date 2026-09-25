import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannelVorzelaAudio create/load/dispose', () async {
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kVorzelaAudioPlayerChannel),
      (call) async {
        log.add(call);
        if (call.method == 'create') return 3;
        return null;
      },
    );

    final platform = MethodChannelVorzelaAudio();
    final id = await platform.create();
    expect(id, 3);
    await platform.load(id, uri: 'https://cdn.example/master.m3u8', fastStart: true);
    await platform.disposePlayer(id);

    expect(log.map((c) => c.method), ['create', 'load', 'dispose']);
    final loadArgs = log[1].arguments as Map;
    expect(loadArgs['uri'], 'https://cdn.example/master.m3u8');
    expect(loadArgs['fastStart'], true);
  });

  test('sound pool methods forward uri', () async {
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kVorzelaAudioPlayerChannel),
      (call) async {
        log.add(call);
        return null;
      },
    );

    final platform = MethodChannelVorzelaAudio();
    await platform.soundPoolLoad('asset://assets/sfx/click.wav');
    await platform.soundPoolPlay('asset://assets/sfx/click.wav', volume: 0.5);
    await platform.soundPoolDispose();

    expect(log.map((c) => c.method), ['soundPoolLoad', 'soundPoolPlay', 'soundPoolDispose']);
    expect((log[1].arguments as Map)['volume'], 0.5);
  });

  test('background and spectrum methods forward args', () async {
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kVorzelaAudioPlayerChannel),
      (call) async {
        log.add(call);
        if (call.method == 'create') return 1;
        return null;
      },
    );

    final platform = MethodChannelVorzelaAudio();
    final id = await platform.create();
    await platform.setBackgroundEnabled(id, enabled: true);
    await platform.enableSpectrum(id, enabled: true);
    await platform.updateNowPlaying(
      id,
      title: 'Track',
      artist: 'Artist',
      durationMs: 120000,
    );

    expect(log.map((c) => c.method), [
      'create',
      'setBackgroundEnabled',
      'enableSpectrum',
      'updateNowPlaying',
    ]);
  });

  test('uri policy rejects http', () {
    expect(isAllowedAudioUri('https://a.com/x.m3u8'), isTrue);
    expect(isAllowedAudioUri('file:///data/x.mp3'), isTrue);
    expect(isAllowedAudioUri('asset://assets/x.wav'), isTrue);
    expect(isAllowedAudioUri('http://a.com/x.mp3'), isFalse);
    expect(audioUriRejectionReason('http://a.com/x.mp3'), contains('https'));
  });
}
