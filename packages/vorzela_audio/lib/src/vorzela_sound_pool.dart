import 'package:flutter/services.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

/// Short overlapping sound effects (native pool — not for long-form streaming).
class VorzelaSoundPool {
  VorzelaSoundPool({VorzelaAudioPlatform? platform})
      : _platform = platform ?? VorzelaAudioPlatform.instance;

  final VorzelaAudioPlatform _platform;
  final Set<String> _loaded = {};

  bool isLoaded(String uri) => _loaded.contains(uri);

  Future<void> load(String uri) async {
    final rejection = audioUriRejectionReason(uri);
    if (rejection != null) {
      throw PlatformException(code: 'insecure_uri', message: rejection);
    }
    await _platform.soundPoolLoad(uri);
    _loaded.add(uri);
  }

  Future<void> play(String uri, {double volume = 1.0}) async {
    if (!_loaded.contains(uri)) {
      await load(uri);
    }
    await _platform.soundPoolPlay(uri, volume: volume.clamp(0.0, 1.0));
  }

  Future<void> dispose() async {
    _loaded.clear();
    await _platform.soundPoolDispose();
  }
}
