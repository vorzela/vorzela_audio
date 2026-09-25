# vorzela_audio

Federated Flutter **audio-only** player (no Texture, no video surface).

| Platform | Engine | Notes |
|----------|--------|--------|
| Android | AndroidX **Media3 ExoPlayer** + HLS | Tight `DefaultLoadControl` (2–10s buffers) |
| iOS | **AVPlayer** (no `AVPlayerLayer`) | HLS + progressive HTTPS |
| Web / desktop | — | **Not shipped** |

- **Sources:** HLS (`*.m3u8`), progressive **https**, local **file://**, Flutter **asset://** keys
- Cleartext **http://** is rejected (same policy as [video_player_flutter](https://github.com/vorzela/video_player_flutter))
- Position / buffer events throttled to **250ms** (`kPositionEventThrottleMs`)
- `VorzelaAudioController` — load, play, pause, seek, volume, **background**, **spectrum**, dispose
- `VorzelaPlaylistController` + `VorzelaMediaItem` — queue, auto-advance, lock-screen next/previous
- UI chrome — `VorzelaAudioVisualizer`, `VorzelaWaveSeekBar`, `VorzelaAudioPlayerChrome`, `VorzelaPlaylistList`
- `VorzelaSoundPool` — preload short SFX, overlapping one-shots

**License:** MIT  
**Homepage:** https://github.com/vorzela/vorzela_audio

---

## Install

```yaml
dependencies:
  vorzela_audio:
    git:
      url: https://github.com/vorzela/vorzela_audio.git
      path: packages/vorzela_audio
    # or local:
    # path: ../vorzela_audio/packages/vorzela_audio
```

```dart
import 'package:vorzela_audio/vorzela_audio.dart';
```

---

## Streaming audio

```dart
class PodcastPage extends StatefulWidget {
  const PodcastPage({super.key, required this.url});
  final String url;

  @override
  State<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends State<PodcastPage> {
  final controller = VorzelaAudioController();

  @override
  void initState() {
    super.initState();
    controller.load(widget.url, autoPlay: true, fastStart: true);
  }

  @override
  void dispose() {
    controller.dispose(); // releases native ExoPlayer / AVPlayer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        children: [
          if (controller.isBuffering) const LinearProgressIndicator(),
          Text('${controller.position} / ${controller.duration}'),
          if (controller.error != null) Text(controller.error!),
          IconButton(
            onPressed: controller.isPlaying ? controller.pause : controller.play,
            icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}
```

Always call `controller.dispose()` (or `disposePlayer()`) when leaving the screen.

### URI schemes

| Scheme | Example | Use |
|--------|---------|-----|
| `https` | `https://cdn.example/master.m3u8` | HLS or MP3/AAC stream |
| `file` | `file:///data/user/0/.../track.mp3` | Local file |
| `asset` | `asset://assets/sfx/intro.mp3` | Flutter asset key (native resolves via Flutter loader) |

---

## Sound pool (SFX)

```dart
final pool = VorzelaSoundPool();
await pool.load('asset://assets/sfx/click.wav');
await pool.play('asset://assets/sfx/click.wav'); // overlapping OK
await pool.dispose();
```

Keep clips short; the pool is not for long-form playback.

---

## Background playback & media controls

Enable background mode on the controller after load (or before — it is applied on the next `load()`):

```dart
await controller.enableBackground(true);
await controller.syncNowPlaying(
  title: 'Episode 12',
  artist: 'Show Name',
);
```

**Android (app manifest)** — merge these into your app (the plugin ships a foreground service stub):

- `INTERNET` (plugin)
- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `POST_NOTIFICATIONS` (API 33+)
- Optional: declare `com.vorzela.vorzela_audio.VorzelaAudioPlaybackService` with `foregroundServiceType="mediaPlayback"` if not merged from the plugin

**iOS (`Info.plist`)** — add background audio:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Lock-screen / notification actions emit `AudioRemoteActionEvent` on the event stream; `VorzelaPlaylistController` wires **next** / **previous** automatically.

---

## Spectrum visualizer

```dart
await controller.enableSpectrum(true);
// controller.spectrum -> VorzelaAudioSpectrum(bass, mid, high, bands?)
VorzelaAudioVisualizer(controller: controller);
```

Native engines emit throttled spectrum events (~50ms). Android uses `android.media.Visualizer` on the ExoPlayer audio session (zeros when unavailable). iOS uses a lightweight amplitude-based split when a full tap is too heavy.

---

## Playlist

```dart
final playlist = VorzelaPlaylistController();
await playlist.setQueue([
  VorzelaMediaItem(uri: 'https://cdn.example/a.m3u8', title: 'A', artist: 'Band'),
  VorzelaMediaItem(uri: 'https://cdn.example/b.m3u8', title: 'B', artist: 'Band'),
], startIndex: 0);
await playlist.playIndex(0, autoPlay: true);

// UI
VorzelaPlaylistList(playlist: playlist);
VorzelaAudioPlayerChrome(controller: playlist.audio, showVisualizer: true);
```

Tracks auto-advance on `AudioCompletedEvent`. Hook optional analytics:

```dart
playlist.onSkipNext = () => analytics.log('skip_next');
```

---

## Memory contract

1. **One native player per controller** — `load()` disposes any previous player before creating a new one. Overlapping loads are generation-guarded (orphans disposed).
2. **Explicit dispose** — Prefer `await disposePlayer()` before dropping references; `dispose()` still schedules teardown.
3. **Tight buffering (Android)** — `DefaultLoadControl` uses **2s** min / **10s** max buffer, **500ms** playback start, **1000ms** after rebuffer.
4. **Position events** — at most ~**4/s** (`kPositionEventThrottleMs == 250`).
5. **No video pipeline** — no Surface / Texture RAM.

---

## API reference

### Controllers

| API | When |
|-----|------|
| `VorzelaAudioController({platform?})` | One long-form stream / podcast / song engine |
| `load(uri, {autoPlay, fastStart})` | Start or replace media (`https` / `file` / `asset`; **http rejected**) |
| `play` / `pause` / `seek` / `setVolume` | Transport |
| `enableBackground(bool)` | Lock-screen / notification / FGS — call before or after load (re-applied on load) |
| `enableSpectrum(bool)` | Drive `VorzelaAudioVisualizer` / wave seek |
| `syncNowPlaying({title, artist})` | Update MediaSession / MPNowPlaying metadata |
| `disposePlayer()` / `dispose()` | Leave screen / tear down |
| Fields: `isReady`, `isPlaying`, `isBuffering`, `position`, `duration`, `buffered`, `error`, `spectrum`, `backgroundEnabled` | Bind with `ListenableBuilder` |
| `onRemoteAction` / `onTrackCompleted` | Hooks; playlist sets these |

| API | When |
|-----|------|
| `VorzelaPlaylistController({audio?})` | Queue of tracks on **one** controller |
| `setQueue(items, {startIndex})` | Replace queue |
| `playAt` / `playIndex` / `next` / `previous` | Navigation (mutex vs auto-advance) |
| `repeatMode` (`off` / `one` / `all`) / `shuffle` | Loop / shuffle |
| `items` / `current` / `currentIndex` / `audio` | State |
| `onSkipNext` / `onSkipPrevious` | Analytics hooks |
| `dispose()` | Disposes owned audio controller |

| API | When |
|-----|------|
| `VorzelaMediaItem({uri, title?, artist?})` | Playlist entry |
| `VorzelaRepeatMode` | `off`, `one`, `all` |
| `VorzelaSoundPool` → `load` / `play` / `dispose` | Short overlapping SFX only |
| `VorzelaAudioSpectrum({bass, mid, high, bands?})` | Latest visualizer sample |

### Widgets

| API | When |
|-----|------|
| `VorzelaAudioPlayerChrome` | Default chrome shell (visualizer + seek + time); replace pieces via your own `Stack` |
| `VorzelaAudioVisualizer` | Bass/mid/high bars while spectrum enabled |
| `VorzelaAudioSeekBar` | Linear scrubber |
| `VorzelaWaveSeekBar` | Band envelope + scrubber; falls back to linear seek |
| `VorzelaAudioTimeLabel` | `mm:ss` clock |
| `VorzelaPlaylistList` | Simple tappable queue list |

### Events (platform interface)

| Type | When |
|------|------|
| `AudioSpectrumEvent` | ~50ms band levels |
| `AudioFocusLostEvent` / `AudioFocusGainedEvent` | Other apps took / returned audio focus |
| `AudioRemoteActionEvent` | Notification / lock-screen play/pause/seek/next/prev |
| `kPositionEventThrottleMs` | `250` |

---

## Workspace

```bash
cd vorzela_audio
dart pub get
dart run melos bootstrap
cd packages/vorzela_audio && flutter test
```
