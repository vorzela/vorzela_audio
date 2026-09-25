package com.vorzela.vorzela_audio

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Foreground playback service stub — declare in the **app** manifest when using
 * [PlayerSession.setBackgroundEnabled]. See package README for permissions.
 */
class VorzelaAudioPlaybackService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    return START_STICKY
  }
}
