import 'package:flutter_test/flutter_test.dart';
import 'package:vorzela_audio_platform_interface/vorzela_audio_platform_interface.dart';

void main() {
  test('spectrum focus and remote event types', () {
    const spectrumEvent = AudioSpectrumEvent(bass: 1, mid: 0.5, high: 0.1, bands: [0.2]);
    expect(spectrumEvent.bass, 1);
    expect(const AudioFocusLostEvent(), isA<AudioEvent>());
    expect(const AudioFocusGainedEvent(), isA<AudioEvent>());
    expect(const AudioRemoteActionEvent('next').action, 'next');
  });
}
