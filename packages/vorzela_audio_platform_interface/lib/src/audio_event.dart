sealed class AudioEvent {
  const AudioEvent();
}

class AudioReadyEvent extends AudioEvent {
  const AudioReadyEvent({required this.durationMs});

  final int durationMs;
}

class AudioBufferingEvent extends AudioEvent {
  const AudioBufferingEvent(this.isBuffering);
  final bool isBuffering;
}

class AudioPositionEvent extends AudioEvent {
  const AudioPositionEvent({
    required this.positionMs,
    required this.bufferedMs,
  });

  final int positionMs;
  final int bufferedMs;
}

class AudioErrorEvent extends AudioEvent {
  const AudioErrorEvent(this.message);
  final String message;
}

class AudioCompletedEvent extends AudioEvent {
  const AudioCompletedEvent();
}

/// FFT-style bands for visualizers (native throttled ~50ms).
class AudioSpectrumEvent extends AudioEvent {
  const AudioSpectrumEvent({
    required this.bass,
    required this.mid,
    required this.high,
    this.bands,
  });

  final double bass;
  final double mid;
  final double high;
  final List<double>? bands;
}

class AudioFocusLostEvent extends AudioEvent {
  const AudioFocusLostEvent();
}

class AudioFocusGainedEvent extends AudioEvent {
  const AudioFocusGainedEvent();
}

/// Lock-screen / notification / headset media key actions.
class AudioRemoteActionEvent extends AudioEvent {
  const AudioRemoteActionEvent(this.action, {this.seekPositionMs});

  /// `play`, `pause`, `next`, `previous`, or `seek`.
  final String action;
  final int? seekPositionMs;
}
