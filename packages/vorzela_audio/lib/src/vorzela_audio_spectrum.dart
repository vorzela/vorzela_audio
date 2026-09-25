/// Latest spectrum snapshot from native visualizer (bass / mid / high in 0–1).
class VorzelaAudioSpectrum {
  const VorzelaAudioSpectrum({
    this.bass = 0,
    this.mid = 0,
    this.high = 0,
    this.bands,
  });

  final double bass;
  final double mid;
  final double high;
  final List<double>? bands;

  VorzelaAudioSpectrum copyWith({
    double? bass,
    double? mid,
    double? high,
    List<double>? bands,
  }) {
    return VorzelaAudioSpectrum(
      bass: bass ?? this.bass,
      mid: mid ?? this.mid,
      high: high ?? this.high,
      bands: bands ?? this.bands,
    );
  }
}
