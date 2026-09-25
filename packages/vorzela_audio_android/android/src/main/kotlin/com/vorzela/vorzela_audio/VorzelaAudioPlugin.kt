package com.vorzela.vorzela_audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes as PlatformAudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.SoundPool
import android.media.Visualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.sqrt

@UnstableApi
class VorzelaAudioPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler {
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var context: Context

  private var eventSink: EventChannel.EventSink? = null
  private val players = ConcurrentHashMap<Int, PlayerSession>()
  private val nextId = AtomicInteger(1)
  private val mainHandler = Handler(Looper.getMainLooper())
  private lateinit var sfxPool: SfxPool

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    sfxPool = SfxPool(context)
    channel = MethodChannel(binding.binaryMessenger, "com.vorzela.vorzela_audio/player")
    channel.setMethodCallHandler(this)
    eventChannel = EventChannel(binding.binaryMessenger, "com.vorzela.vorzela_audio/events")
    eventChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    players.values.forEach { it.release() }
    players.clear()
    sfxPool.release()
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "create" -> {
        val id = nextId.getAndIncrement()
        val session = PlayerSession(id, context, mainHandler) { event ->
          mainHandler.post { eventSink?.success(event) }
        }
        players[id] = session
        result.success(id)
      }
      "load" -> {
        val id = call.argument<Int>("playerId") ?: return result.error("bad_args", "playerId", null)
        val uri = call.argument<String>("uri") ?: return result.error("bad_args", "uri", null)
        val session = players[id] ?: return result.error("missing", "player", null)
        val err = validateUri(uri)
        if (err != null) {
          return result.error("insecure_uri", err, null)
        }
        session.load(
          uri = uri,
          autoPlay = call.argument<Boolean>("autoPlay") ?: false,
          fastStart = call.argument<Boolean>("fastStart") ?: true,
        )
        result.success(null)
      }
      "play" -> {
        players[call.argId()]?.play()
        result.success(null)
      }
      "pause" -> {
        players[call.argId()]?.pause()
        result.success(null)
      }
      "seek" -> {
        val ms = call.argument<Int>("positionMs") ?: 0
        players[call.argId()]?.seek(ms.toLong())
        result.success(null)
      }
      "setVolume" -> {
        val v = (call.argument<Double>("volume") ?: 1.0).toFloat()
        players[call.argId()]?.setVolume(v)
        result.success(null)
      }
      "setBackgroundEnabled" -> {
        val enabled = call.argument<Boolean>("enabled") ?: false
        players[call.argId()]?.setBackgroundEnabled(enabled)
        result.success(null)
      }
      "updateNowPlaying" -> {
        val id = call.argId()
        val title = call.argument<String>("title") ?: ""
        val artist = call.argument<String>("artist") ?: ""
        val durationMs = call.argument<Int>("durationMs") ?: 0
        players[id]?.updateNowPlaying(title, artist, durationMs)
        result.success(null)
      }
      "enableSpectrum" -> {
        val enabled = call.argument<Boolean>("enabled") ?: false
        players[call.argId()]?.enableSpectrum(enabled)
        result.success(null)
      }
      "dispose" -> {
        val id = call.argId()
        players.remove(id)?.release()
        result.success(null)
      }
      "soundPoolLoad" -> {
        val uri = call.argument<String>("uri") ?: return result.error("bad_args", "uri", null)
        val err = validateUri(uri)
        if (err != null) {
          return result.error("insecure_uri", err, null)
        }
        try {
          sfxPool.load(uri)
          result.success(null)
        } catch (e: Exception) {
          result.error("sound_pool", e.message, null)
        }
      }
      "soundPoolPlay" -> {
        val uri = call.argument<String>("uri") ?: return result.error("bad_args", "uri", null)
        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
        try {
          sfxPool.play(uri, volume)
          result.success(null)
        } catch (e: Exception) {
          result.error("sound_pool", e.message, null)
        }
      }
      "soundPoolDispose" -> {
        sfxPool.release()
        sfxPool = SfxPool(context)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun MethodCall.argId(): Int = argument<Int>("playerId") ?: -1

  private fun validateUri(uri: String): String? {
    val scheme = Uri.parse(uri).scheme?.lowercase()
    return when (scheme) {
      "https", "file", "asset" -> null
      "http" -> "Only https:// URIs are allowed for network playback, got scheme=http"
      null -> "Missing URI scheme"
      else -> "Unsupported URI scheme: $scheme"
    }
  }
}

@UnstableApi
private class PlayerSession(
  private val id: Int,
  private val context: Context,
  private val handler: Handler,
  private val emit: (Map<String, Any?>) -> Unit,
) : Player.Listener {
  private val loadControl = DefaultLoadControl.Builder()
    .setBufferDurationsMs(2_000, 10_000, 500, 1_000)
    .build()

  private val mediaAudioAttributes = AudioAttributes.Builder()
    .setUsage(C.USAGE_MEDIA)
    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
    .build()

  private val player: ExoPlayer = ExoPlayer.Builder(context)
    .setLoadControl(loadControl)
    .setAudioAttributes(mediaAudioAttributes, false)
    .build()

  private val audioManager =
    context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

  private var mediaSession: MediaSessionCompat? = null
  private var backgroundEnabled = false
  private var spectrumEnabled = false
  private var visualizer: Visualizer? = null
  private var lastSpectrumEmit = 0L
  private var savedVolume = 1f
  private var nowTitle = ""
  private var nowArtist = ""
  private var nowDurationMs = 0

  private var lastPositionEmit = 0L
  private var fastStart = true
  private var released = false

  private val notificationId = 0x7A000000 or id
  private val channelId = "vorzela_audio_playback"

  private val focusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
    handler.post {
      when (focusChange) {
        AudioManager.AUDIOFOCUS_LOSS,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
        -> {
          pauseInternal()
          emit(mapOf("type" to "audioFocusLost", "playerId" to id))
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
          savedVolume = player.volume
          player.volume = (savedVolume * 0.25f).coerceAtLeast(0.05f)
        }
        AudioManager.AUDIOFOCUS_GAIN -> {
          player.volume = savedVolume
          emit(mapOf("type" to "audioFocusGained", "playerId" to id))
        }
      }
    }
  }

  private val tickRunnable = object : Runnable {
    override fun run() {
      if (released) return
      val active =
        player.playbackState != Player.STATE_IDLE &&
          player.playbackState != Player.STATE_ENDED
      if (!active) {
        // Stop polling while idle/ended — restarted by [ensureTicking] on load/play.
        return
      }
      val now = System.currentTimeMillis()
      if (now - lastPositionEmit >= 250) {
        lastPositionEmit = now
        val buffered = player.bufferedPosition.coerceAtLeast(0)
        emit(
          mapOf(
            "type" to "position",
            "playerId" to id,
            "positionMs" to player.currentPosition,
            "bufferedMs" to buffered,
          ),
        )
        updatePlaybackState()
      }
      if (spectrumEnabled && visualizer == null) {
        emitZeroSpectrum()
      }
      // Position is static while paused; avoid a 50ms busy-loop.
      val nextDelay = if (player.isPlaying) 50L else 500L
      handler.postDelayed(this, nextDelay)
    }
  }

  private fun ensureTicking() {
    if (released) return
    handler.removeCallbacks(tickRunnable)
    handler.post(tickRunnable)
  }

  init {
    player.addListener(this)
    ensureNotificationChannel()
    ensureTicking()
  }

  fun load(uri: String, autoPlay: Boolean, fastStart: Boolean) {
    this.fastStart = fastStart
    val mediaUri = resolvePlaybackUri(context, uri)
    val mediaItem = MediaItem.Builder()
      .setUri(mediaUri)
      .setLiveConfiguration(
        MediaItem.LiveConfiguration.Builder()
          .setTargetOffsetMs(3_000)
          .setMinPlaybackSpeed(0.97f)
          .setMaxPlaybackSpeed(1.03f)
          .build(),
      )
      .build()
    player.setMediaItem(mediaItem)
    player.prepare()
    player.playWhenReady = autoPlay
    if (autoPlay) requestAudioFocus()
    ensureTicking()
    handler.postDelayed({ maybeAttachVisualizer() }, 300)
  }

  fun play() {
    requestAudioFocus()
    player.playWhenReady = true
    player.play()
    ensureTicking()
    updatePlaybackState()
    refreshNotification()
  }

  fun pause() {
    pauseInternal()
  }

  private fun pauseInternal() {
    player.pause()
    updatePlaybackState()
    refreshNotification()
  }

  fun seek(ms: Long) {
    player.seekTo(ms)
    updatePlaybackState()
  }

  fun setVolume(v: Float) {
    savedVolume = v.coerceIn(0f, 1f)
    player.volume = savedVolume
  }

  fun setBackgroundEnabled(enabled: Boolean) {
    backgroundEnabled = enabled
    if (enabled) {
      ensureMediaSession()
      refreshNotification()
      startForegroundStub()
    } else {
      stopForegroundStub()
      refreshNotification()
    }
  }

  fun updateNowPlaying(title: String, artist: String, durationMs: Int) {
    nowTitle = title
    nowArtist = artist
    nowDurationMs = durationMs
    refreshNotification()
  }

  fun enableSpectrum(enabled: Boolean) {
    spectrumEnabled = enabled
    if (enabled) {
      maybeAttachVisualizer()
    } else {
      visualizer?.enabled = false
      visualizer?.release()
      visualizer = null
    }
  }

  override fun onPlaybackStateChanged(playbackState: Int) {
    when (playbackState) {
      Player.STATE_BUFFERING -> emit(mapOf("type" to "buffering", "playerId" to id, "isBuffering" to true))
      Player.STATE_READY -> {
        emit(mapOf("type" to "buffering", "playerId" to id, "isBuffering" to false))
        if (fastStart) {
          handler.postDelayed({ /* ABR climbs naturally */ }, 1_500)
        }
        emitReady()
        maybeAttachVisualizer()
      }
      Player.STATE_ENDED -> emit(mapOf("type" to "completed", "playerId" to id))
    }
    updatePlaybackState()
  }

  private fun emitReady() {
    emit(
      mapOf(
        "type" to "ready",
        "playerId" to id,
        "durationMs" to player.duration.coerceAtLeast(0),
      ),
    )
    nowDurationMs = player.duration.coerceAtLeast(0).toInt()
  }

  override fun onPlayerError(error: PlaybackException) {
    emit(mapOf("type" to "error", "playerId" to id, "message" to (error.message ?: "playback error")))
  }

  private fun requestAudioFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val attrs = PlatformAudioAttributes.Builder()
        .setUsage(PlatformAudioAttributes.USAGE_MEDIA)
        .setContentType(PlatformAudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
      val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(attrs)
        .setOnAudioFocusChangeListener(focusListener, handler)
        .build()
      audioManager.requestAudioFocus(request)
    } else {
      @Suppress("DEPRECATION")
      audioManager.requestAudioFocus(
        focusListener,
        AudioManager.STREAM_MUSIC,
        AudioManager.AUDIOFOCUS_GAIN,
      )
    }
  }

  private fun ensureMediaSession() {
    if (mediaSession != null) return
    mediaSession = MediaSessionCompat(context, "VorzelaAudio-$id").apply {
      setFlags(
        MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
          MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
      )
      setCallback(
        object : MediaSessionCompat.Callback() {
          override fun onPlay() {
            play()
            emitRemote("play")
          }

          override fun onPause() {
            pause()
            emitRemote("pause")
          }

          override fun onSeekTo(pos: Long) {
            seek(pos)
            emitRemote("seek", seekPositionMs = pos.toInt())
          }

          override fun onSkipToNext() {
            emitRemote("next")
          }

          override fun onSkipToPrevious() {
            emitRemote("previous")
          }
        },
      )
      isActive = true
    }
  }

  private fun updatePlaybackState() {
    val session = mediaSession ?: return
    val state = if (player.isPlaying) {
      PlaybackStateCompat.STATE_PLAYING
    } else {
      PlaybackStateCompat.STATE_PAUSED
    }
    session.setPlaybackState(
      PlaybackStateCompat.Builder()
        .setActions(
          PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS,
        )
        .setState(state, player.currentPosition, 1f)
        .build(),
    )
  }

  private fun refreshNotification() {
    if (!backgroundEnabled) return
    ensureMediaSession()
    val session = mediaSession ?: return
    val notification = buildNotification(session)
    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    nm.notify(notificationId, notification)
    startForegroundStub(notification)
  }

  private fun buildNotification(session: MediaSessionCompat): Notification {
    val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
    val contentIntent = PendingIntent.getActivity(
      context,
      id,
      launchIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    return NotificationCompat.Builder(context, channelId)
      .setContentTitle(nowTitle.ifEmpty { "Playing audio" })
      .setContentText(nowArtist)
      .setSmallIcon(android.R.drawable.ic_media_play)
      .setContentIntent(contentIntent)
      .setStyle(
        androidx.media.app.NotificationCompat.MediaStyle()
          .setMediaSession(session.sessionToken)
          .setShowActionsInCompactView(0, 1, 2),
      )
      .addAction(
        NotificationCompat.Action(
          android.R.drawable.ic_media_previous,
          "Previous",
          null,
        ),
      )
      .addAction(
        NotificationCompat.Action(
          if (player.isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
          "Play/Pause",
          null,
        ),
      )
      .addAction(
        NotificationCompat.Action(
          android.R.drawable.ic_media_next,
          "Next",
          null,
        ),
      )
      .setOngoing(player.isPlaying)
      .build()
  }

  private fun ensureNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val channel = NotificationChannel(
      channelId,
      "Audio playback",
      NotificationManager.IMPORTANCE_LOW,
    )
    nm.createNotificationChannel(channel)
  }

  private fun startForegroundStub(notification: Notification? = null) {
    val intent = Intent(context, VorzelaAudioPlaybackService::class.java)
    context.startForegroundService(intent)
    if (notification != null) {
      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.notify(notificationId, notification)
    }
  }

  private fun stopForegroundStub() {
    val intent = Intent(context, VorzelaAudioPlaybackService::class.java)
    context.stopService(intent)
  }

  private fun emitRemote(action: String, seekPositionMs: Int? = null) {
    val payload = mutableMapOf<String, Any?>(
      "type" to "remoteAction",
      "playerId" to id,
      "action" to action,
    )
    if (seekPositionMs != null) payload["seekPositionMs"] = seekPositionMs
    emit(payload)
  }

  private fun maybeAttachVisualizer() {
    if (!spectrumEnabled || visualizer != null) return
    val sessionId = player.audioSessionId
    if (sessionId == 0) return
    try {
      visualizer = Visualizer(sessionId).apply {
        captureSize = Visualizer.getCaptureSizeRange()[1]
        setDataCaptureListener(
          object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormCapture(
              visualizer: Visualizer?,
              waveform: ByteArray?,
              samplingRate: Int,
            ) {
            }

            override fun onFftDataCapture(
              visualizer: Visualizer?,
              fft: ByteArray?,
              samplingRate: Int,
            ) {
              if (fft == null || !spectrumEnabled) return
              val now = System.currentTimeMillis()
              if (now - lastSpectrumEmit < 50) return
              lastSpectrumEmit = now
              val bands = splitFft(fft)
              emit(
                mapOf(
                  "type" to "spectrum",
                  "playerId" to id,
                  "bass" to bands.first,
                  "mid" to bands.second,
                  "high" to bands.third,
                ),
              )
            }
          },
          Visualizer.getMaxCaptureRate() / 2,
          false,
          true,
        )
        enabled = true
      }
    } catch (_: Exception) {
      visualizer = null
    }
  }

  private fun emitZeroSpectrum() {
    val now = System.currentTimeMillis()
    if (now - lastSpectrumEmit < 50) return
    lastSpectrumEmit = now
    emit(
      mapOf(
        "type" to "spectrum",
        "playerId" to id,
        "bass" to 0.0,
        "mid" to 0.0,
        "high" to 0.0,
      ),
    )
  }

  private fun splitFft(fft: ByteArray): Triple<Double, Double, Double> {
    val n = fft.size / 2
    if (n <= 0) return Triple(0.0, 0.0, 0.0)
    var bass = 0.0
    var mid = 0.0
    var high = 0.0
    var bassCount = 0
    var midCount = 0
    var highCount = 0
    for (i in 0 until n) {
      val r = fft[2 * i].toInt()
      val im = fft[2 * i + 1].toInt()
      val mag = sqrt((r * r + im * im).toDouble())
      when {
        i < n / 3 -> {
          bass += mag
          bassCount++
        }
        i < 2 * n / 3 -> {
          mid += mag
          midCount++
        }
        else -> {
          high += mag
          highCount++
        }
      }
    }
    fun norm(sum: Double, count: Int): Double {
      if (count == 0) return 0.0
      return (sum / count / 128.0).coerceIn(0.0, 1.0)
    }
    return Triple(norm(bass, bassCount), norm(mid, midCount), norm(high, highCount))
  }

  fun release() {
    released = true
    handler.removeCallbacks(tickRunnable)
    visualizer?.release()
    visualizer = null
    stopForegroundStub()
    mediaSession?.isActive = false
    mediaSession?.release()
    mediaSession = null
    player.removeListener(this)
    player.release()
  }
}

private fun resolvePlaybackUri(context: Context, uri: String): Uri {
  val parsed = Uri.parse(uri)
  if (parsed.scheme?.lowercase() != "asset") return parsed
  val assetPath = uri.removePrefix("asset://").trimStart('/')
  val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
  return Uri.parse("asset:///$key")
}

@UnstableApi
private class SfxPool(private val context: Context) {
  private val pool: SoundPool = SoundPool.Builder()
    .setMaxStreams(12)
    .setAudioAttributes(
      PlatformAudioAttributes.Builder()
        .setUsage(PlatformAudioAttributes.USAGE_GAME)
        .setContentType(PlatformAudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build(),
    )
    .build()

  private val sampleIds = ConcurrentHashMap<String, Int>()
  private val oneShotPlayers = ConcurrentHashMap<String, ExoPlayer>()
  private val mainHandler = Handler(Looper.getMainLooper())

  fun load(uri: String) {
    if (sampleIds.containsKey(uri) || oneShotPlayers.containsKey(uri)) return
    when (Uri.parse(uri).scheme?.lowercase()) {
      "https" -> {
        oneShotPlayers[uri] = createOneShotPlayer(uri)
      }
      "file", "asset" -> {
        val sampleId = when (Uri.parse(uri).scheme?.lowercase()) {
          "file" -> {
            val path = Uri.parse(uri).path ?: throw IllegalArgumentException("bad file uri")
            pool.load(path, 1)
          }
          else -> {
            val assetPath = uri.removePrefix("asset://").trimStart('/')
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
            // SoundPool.load(AssetFileDescriptor, ...) dup()s the underlying fd
            // internally, so close our copy right after or we leak one fd per SFX.
            context.assets.openFd(key).use { afd -> pool.load(afd, 1) }
          }
        }
        if (sampleId == 0) throw IllegalStateException("SoundPool load failed for $uri")
        sampleIds[uri] = sampleId
      }
      else -> throw IllegalArgumentException("unsupported sfx uri")
    }
  }

  fun play(uri: String, volume: Float) {
    val scheme = Uri.parse(uri).scheme?.lowercase()
    if (scheme == "https") {
      val player = oneShotPlayers.getOrPut(uri) { createOneShotPlayer(uri) }
      val mediaUri = Uri.parse(uri)
      player.setMediaItem(MediaItem.fromUri(mediaUri))
      player.volume = volume.coerceIn(0f, 1f)
      player.prepare()
      player.playWhenReady = true
      return
    }
    val sampleId = sampleIds[uri] ?: run {
      load(uri)
      sampleIds[uri]!!
    }
    pool.play(sampleId, volume.coerceIn(0f, 1f), volume.coerceIn(0f, 1f), 1, 0, 1f)
  }

  private fun createOneShotPlayer(uri: String): ExoPlayer {
    return ExoPlayer.Builder(context).build().apply {
      addListener(
        object : Player.Listener {
          override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED) {
              // Never release ExoPlayer from inside its own listener callback.
              mainHandler.post { releaseOneShot(uri) }
            }
          }

          override fun onPlayerError(error: PlaybackException) {
            mainHandler.post { releaseOneShot(uri) }
          }
        },
      )
    }
  }

  private fun releaseOneShot(uri: String) {
    oneShotPlayers.remove(uri)?.release()
  }

  fun release() {
    sampleIds.clear()
    pool.release()
    oneShotPlayers.values.forEach { it.release() }
    oneShotPlayers.clear()
  }
}
