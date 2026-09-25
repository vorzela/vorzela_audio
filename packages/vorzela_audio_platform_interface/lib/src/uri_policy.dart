/// Allowed URI schemes for [VorzelaAudioController.load] and sound pool loads.
///
/// Network playback is **https only** (cleartext `http://` is rejected, same as
/// vorzela video). Local `file://` and Flutter `asset://` keys are allowed.
bool isAllowedAudioUri(String uri) {
  final scheme = _scheme(uri);
  if (scheme == null || scheme.isEmpty) return false;
  switch (scheme) {
    case 'https':
    case 'file':
    case 'asset':
      return true;
    case 'http':
      return false;
    default:
      return false;
  }
}

String? audioUriRejectionReason(String uri) {
  final scheme = _scheme(uri);
  if (scheme == null || scheme.isEmpty) {
    return 'Missing URI scheme';
  }
  if (scheme == 'http') {
    return 'Only https:// URIs are allowed for network playback';
  }
  if (!isAllowedAudioUri(uri)) {
    return 'Unsupported URI scheme: $scheme';
  }
  return null;
}

String? _scheme(String uri) {
  final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(uri);
  return match?.group(1)?.toLowerCase();
}
