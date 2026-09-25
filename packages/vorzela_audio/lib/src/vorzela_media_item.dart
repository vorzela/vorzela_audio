/// Playlist entry (mirrors vorzela video media metadata shape).
class VorzelaMediaItem {
  const VorzelaMediaItem({
    required this.uri,
    this.title,
    this.artist,
  });

  final String uri;
  final String? title;
  final String? artist;
}
