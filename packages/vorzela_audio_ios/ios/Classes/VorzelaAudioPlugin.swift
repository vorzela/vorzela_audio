import AVFoundation
import Flutter
import MediaPlayer

public class VorzelaAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var registrar: FlutterPluginRegistrar?
  private var players: [Int: PlayerSession] = [:]
  private var nextId = 1
  private var sfxPool: SfxPool?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VorzelaAudioPlugin()
    instance.registrar = registrar
    instance.sfxPool = SfxPool(registrar: registrar)

    let channel = FlutterMethodChannel(
      name: "com.vorzela.vorzela_audio/player",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler(instance.handle)

    let events = FlutterEventChannel(
      name: "com.vorzela.vorzela_audio/events",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "create":
      let id = nextId
      nextId += 1
      let session = PlayerSession(id: id) { [weak self] event in
        self?.eventSink?(event)
      }
      players[id] = session
      result(id)
    case "load":
      guard let id = args?["playerId"] as? Int,
        let uri = args?["uri"] as? String,
        let session = players[id]
      else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      if let err = Self.validateUri(uri) {
        result(FlutterError(code: "insecure_uri", message: err, details: nil))
        return
      }
      session.load(
        uri: uri,
        registrar: registrar,
        autoPlay: args?["autoPlay"] as? Bool ?? false,
        fastStart: args?["fastStart"] as? Bool ?? true
      )
      result(nil)
    case "play":
      players[args?["playerId"] as? Int ?? -1]?.play()
      result(nil)
    case "pause":
      players[args?["playerId"] as? Int ?? -1]?.pause()
      result(nil)
    case "seek":
      let ms = args?["positionMs"] as? Int ?? 0
      players[args?["playerId"] as? Int ?? -1]?.seek(ms: ms)
      result(nil)
    case "setVolume":
      let v = args?["volume"] as? Double ?? 1.0
      players[args?["playerId"] as? Int ?? -1]?.setVolume(Float(v))
      result(nil)
    case "setBackgroundEnabled":
      let enabled = args?["enabled"] as? Bool ?? false
      players[args?["playerId"] as? Int ?? -1]?.setBackgroundEnabled(enabled)
      result(nil)
    case "updateNowPlaying":
      guard let id = args?["playerId"] as? Int else {
        result(FlutterError(code: "bad_args", message: "playerId", details: nil))
        return
      }
      let title = args?["title"] as? String ?? ""
      let artist = args?["artist"] as? String ?? ""
      let durationMs = args?["durationMs"] as? Int ?? 0
      players[id]?.updateNowPlaying(title: title, artist: artist, durationMs: durationMs)
      result(nil)
    case "enableSpectrum":
      let enabled = args?["enabled"] as? Bool ?? false
      players[args?["playerId"] as? Int ?? -1]?.enableSpectrum(enabled)
      result(nil)
    case "dispose":
      let id = args?["playerId"] as? Int ?? -1
      players.removeValue(forKey: id)?.release()
      result(nil)
    case "soundPoolLoad":
      guard let uri = args?["uri"] as? String else {
        result(FlutterError(code: "bad_args", message: "uri", details: nil))
        return
      }
      if let err = Self.validateUri(uri) {
        result(FlutterError(code: "insecure_uri", message: err, details: nil))
        return
      }
      do {
        try sfxPool?.load(uri: uri)
        result(nil)
      } catch {
        result(FlutterError(code: "sound_pool", message: error.localizedDescription, details: nil))
      }
    case "soundPoolPlay":
      guard let uri = args?["uri"] as? String else {
        result(FlutterError(code: "bad_args", message: "uri", details: nil))
        return
      }
      let volume = args?["volume"] as? Double ?? 1.0
      do {
        try sfxPool?.play(uri: uri, volume: Float(volume))
        result(nil)
      } catch {
        result(FlutterError(code: "sound_pool", message: error.localizedDescription, details: nil))
      }
    case "soundPoolDispose":
      sfxPool?.release()
      if let registrar = registrar {
        sfxPool = SfxPool(registrar: registrar)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func validateUri(_ uri: String) -> String? {
    guard let scheme = URL(string: uri)?.scheme?.lowercase() else {
      return "Missing URI scheme"
    }
    switch scheme {
    case "https", "file", "asset":
      return nil
    case "http":
      return "Only https:// URIs are allowed for network playback"
    default:
      return "Unsupported URI scheme: \(scheme)"
    }
  }
}

private final class PlayerSession: NSObject {
  private let id: Int
  private let emit: ([String: Any]) -> Void
  private var player: AVPlayer?
  private var item: AVPlayerItem?
  private var positionTimer: Timer?
  private var spectrumTimer: Timer?
  private var lastPositionEmit: CFTimeInterval = 0
  private var lastSpectrumEmit: CFTimeInterval = 0
  private var fastStart = true
  private var backgroundEnabled = false
  private var spectrumEnabled = false
  private var remoteCommandsRegistered = false

  init(id: Int, emit: @escaping ([String: Any]) -> Void) {
    self.id = id
    self.emit = emit
    super.init()
  }

  func load(uri: String, registrar: FlutterPluginRegistrar?, autoPlay: Bool, fastStart: Bool) {
    self.fastStart = fastStart
    releasePlaybackObservers()
    configureAudioSession()

    guard let url = Self.resolveURL(uri: uri, registrar: registrar) else {
      emit(["type": "error", "playerId": id, "message": "bad uri"])
      return
    }

    let item = AVPlayerItem(url: url)
    if fastStart {
      item.preferredPeakBitRate = 800_000
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak item] in
        item?.preferredPeakBitRate = 0
      }
    }
    if #available(iOS 14.0, *) {
      item.configuredTimeOffsetFromLive = CMTime(seconds: 3, preferredTimescale: 1)
    }
    self.item = item

    let player = AVPlayer(playerItem: item)
    self.player = player

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onEnd),
      name: .AVPlayerItemDidPlayToEndTime,
      object: item
    )
    item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)

    startPositionTimer()
    if autoPlay { play() }
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      emit(["type": "error", "playerId": id, "message": error.localizedDescription])
    }
  }

  func setBackgroundEnabled(_ enabled: Bool) {
    backgroundEnabled = enabled
    if enabled {
      registerRemoteCommands()
    }
    refreshNowPlaying()
  }

  func updateNowPlaying(title: String, artist: String, durationMs: Int) {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = artist
    info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  func enableSpectrum(_ enabled: Bool) {
    spectrumEnabled = enabled
    spectrumTimer?.invalidate()
    spectrumTimer = nil
    if enabled {
      spectrumTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
        self?.emitAmplitudeSpectrum()
      }
    }
  }

  private func emitAmplitudeSpectrum() {
    let now = CACurrentMediaTime()
    if now - lastSpectrumEmit < 0.05 { return }
    lastSpectrumEmit = now

    guard let player = player, player.rate > 0 else {
      emit([
        "type": "spectrum", "playerId": id,
        "bass": 0.0, "mid": 0.0, "high": 0.0,
      ])
      return
    }

    let vol = Double(player.volume)
    let t = player.currentTime().seconds
    let bass = min(1.0, vol * (0.55 + 0.15 * sin(t * 2.1)))
    let mid = min(1.0, vol * (0.40 + 0.12 * sin(t * 3.7)))
    let high = min(1.0, vol * (0.28 + 0.10 * sin(t * 5.3)))
    emit([
      "type": "spectrum", "playerId": id,
      "bass": bass, "mid": mid, "high": high,
    ])
  }

  private func registerRemoteCommands() {
    if remoteCommandsRegistered { return }
    remoteCommandsRegistered = true
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.addTarget { [weak self] _ in
      self?.emitRemote("play")
      self?.play()
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.emitRemote("pause")
      self?.pause()
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      self?.emitRemote("next")
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      self?.emitRemote("previous")
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self?.seek(ms: Int(e.positionTime * 1000))
      self?.emitRemote("seek", seekPositionMs: Int(e.positionTime * 1000))
      return .success
    }
  }

  private func emitRemote(_ action: String, seekPositionMs: Int? = nil) {
    var payload: [String: Any] = [
      "type": "remoteAction",
      "playerId": id,
      "action": action,
    ]
    if let ms = seekPositionMs {
      payload["seekPositionMs"] = ms
    }
    emit(payload)
  }

  private func refreshNowPlaying() {
    guard backgroundEnabled, let item = item else { return }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    let durationMs = Int((item.duration.seconds.isFinite ? item.duration.seconds : 0) * 1000)
    info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0
    info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func startPositionTimer() {
    positionTimer?.invalidate()
    positionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.emitPositionIfNeeded()
    }
  }

  private func emitPositionIfNeeded() {
    guard let player = player else { return }
    let now = CACurrentMediaTime()
    if now - lastPositionEmit < 0.25 { return }
    lastPositionEmit = now
    let pos = Int((player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0) * 1000)
    var bufferedMs = pos
    if let item = item, let range = item.loadedTimeRanges.first?.timeRangeValue {
      let end = CMTimeGetSeconds(CMTimeAdd(range.start, range.duration))
      if end.isFinite { bufferedMs = Int(end * 1000) }
    }
    emit([
      "type": "position",
      "playerId": id,
      "positionMs": pos,
      "bufferedMs": bufferedMs,
    ])
    refreshNowPlaying()
  }

  override func observeValue(
    forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    guard keyPath == "status", let item = item else { return }
    switch item.status {
    case .readyToPlay:
      emitReady(item: item)
    case .failed:
      emit([
        "type": "error", "playerId": id, "message": item.error?.localizedDescription ?? "failed",
      ])
    default:
      break
    }
  }

  private func emitReady(item: AVPlayerItem) {
    let durationMs = Int((item.duration.seconds.isFinite ? item.duration.seconds : 0) * 1000)
    emit([
      "type": "ready",
      "playerId": id,
      "durationMs": durationMs,
    ])
    emit(["type": "buffering", "playerId": id, "isBuffering": false])
    refreshNowPlaying()
  }

  @objc private func onEnd() {
    emit(["type": "completed", "playerId": id])
  }

  func play() {
    configureAudioSession()
    player?.play()
    refreshNowPlaying()
  }

  func pause() {
    player?.pause()
    refreshNowPlaying()
  }

  func seek(ms: Int) {
    let t = CMTime(value: CMTimeValue(ms), timescale: 1000)
    player?.seek(to: t)
    refreshNowPlaying()
  }

  func setVolume(_ v: Float) { player?.volume = max(0, min(1, v)) }

  private func releasePlaybackObservers() {
    positionTimer?.invalidate()
    positionTimer = nil
    spectrumTimer?.invalidate()
    spectrumTimer = nil
    if let item = item {
      item.removeObserver(self, forKeyPath: "status")
      NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
    }
    player?.pause()
    player = nil
    item = nil
  }

  func release() {
    releasePlaybackObservers()
    if remoteCommandsRegistered {
      MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
      MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
      MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
      MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
      remoteCommandsRegistered = false
    }
  }

  private static func resolveURL(uri: String, registrar: FlutterPluginRegistrar?) -> URL? {
    if uri.hasPrefix("asset://") {
      guard let registrar = registrar else { return nil }
      let assetPath = String(uri.dropFirst("asset://".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      let key = registrar.lookupKey(forAsset: assetPath)
      if let path = Bundle.main.path(forResource: key, ofType: nil) {
        return URL(fileURLWithPath: path)
      }
      return nil
    }
    return URL(string: uri)
  }
}

private final class SfxPool: NSObject, AVAudioPlayerDelegate {
  private weak var registrar: FlutterPluginRegistrar?
  private var cachedFiles: [String: URL] = [:]

  // Playback objects MUST be retained for the duration of playback, or ARC
  // deallocates them the instant `play()` returns and the sound is cut off.
  // Keyed by a monotonic token so overlapping one-shots don't collide.
  private var activeAVPlayers: [Int: AVPlayer] = [:]
  private var activeAudioPlayers: [Int: AVAudioPlayer] = [:]
  private var nextToken = 0
  private var endObservers: [Int: [NSObjectProtocol]] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func load(uri: String) throws {
    if cachedFiles[uri] != nil { return }
    cachedFiles[uri] = try resolveLocalURL(uri: uri)
  }

  func play(uri: String, volume: Float) throws {
    let url: URL
    if let cached = cachedFiles[uri] {
      url = cached
    } else {
      url = try resolveLocalURL(uri: uri)
      cachedFiles[uri] = url
    }
    if url.scheme?.lowercased() == "https" {
      let token = nextToken
      nextToken += 1
      let item = AVPlayerItem(url: url)
      let player = AVPlayer(playerItem: item)
      player.volume = max(0, min(1, volume))
      activeAVPlayers[token] = player
      let endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.finishAVPlayer(token: token)
      }
      let failObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.finishAVPlayer(token: token)
      }
      endObservers[token] = [endObserver, failObserver]
      player.play()
      return
    }
    let token = nextToken
    nextToken += 1
    let player = try AVAudioPlayer(contentsOf: url)
    player.volume = max(0, min(1, volume))
    player.delegate = self
    player.prepareToPlay()
    activeAudioPlayers[token] = player
    if !player.play() {
      activeAudioPlayers.removeValue(forKey: token)
    }
  }

  private func finishAVPlayer(token: Int) {
    if let observers = endObservers.removeValue(forKey: token) {
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
    activeAVPlayers.removeValue(forKey: token)
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if let token = activeAudioPlayers.first(where: { $0.value === player })?.key {
      activeAudioPlayers.removeValue(forKey: token)
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if let token = activeAudioPlayers.first(where: { $0.value === player })?.key {
      activeAudioPlayers.removeValue(forKey: token)
    }
  }

  func release() {
    cachedFiles.removeAll()
    for player in activeAVPlayers.values { player.pause() }
    activeAVPlayers.removeAll()
    for observers in endObservers.values {
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
    endObservers.removeAll()
    for player in activeAudioPlayers.values { player.stop() }
    activeAudioPlayers.removeAll()
  }

  private func resolveLocalURL(uri: String) throws -> URL {
    if uri.hasPrefix("https://"), let url = URL(string: uri) {
      return url
    }
    if uri.hasPrefix("file://"), let url = URL(string: uri) {
      return url
    }
    if uri.hasPrefix("asset://"), let registrar = registrar {
      let assetPath = String(uri.dropFirst("asset://".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      let key = registrar.lookupKey(forAsset: assetPath)
      if let path = Bundle.main.path(forResource: key, ofType: nil) {
        return URL(fileURLWithPath: path)
      }
    }
    throw NSError(domain: "vorzela_audio", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Could not resolve sound URI",
    ])
  }
}
