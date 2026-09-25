import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'vorzela_audio_controller.dart';
import 'vorzela_media_item.dart';

enum VorzelaRepeatMode { off, one, all }

/// Queue playback with auto-advance, repeat/shuffle, and lock-screen next/prev.
class VorzelaPlaylistController extends ChangeNotifier {
  VorzelaPlaylistController({VorzelaAudioController? audio})
      : audio = audio ?? VorzelaAudioController() {
    _prevCompleted = this.audio.onTrackCompleted;
    this.audio.onTrackCompleted = _onTrackCompleted;
    _prevRemote = this.audio.onRemoteAction;
    this.audio.onRemoteAction = _onRemoteAction;
  }

  final VorzelaAudioController audio;

  final List<VorzelaMediaItem> _items = [];
  List<int> _order = [];
  int _orderIndex = 0;
  VorzelaRepeatMode repeatMode = VorzelaRepeatMode.off;
  bool _shuffle = false;
  bool _advancing = false;

  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

  VoidCallback? _prevCompleted;
  VorzelaRemoteActionHandler? _prevRemote;

  List<VorzelaMediaItem> get items => List.unmodifiable(_items);

  int get currentIndex =>
      _order.isEmpty ? -1 : _order[_orderIndex.clamp(0, _order.length - 1)];

  VorzelaMediaItem? get current {
    final i = currentIndex;
    if (i < 0 || i >= _items.length) return null;
    return _items[i];
  }

  bool get shuffle => _shuffle;

  set shuffle(bool value) {
    if (_shuffle == value) return;
    _shuffle = value;
    _rebuildOrder(keepCurrent: true);
    notifyListeners();
  }

  Future<void> setQueue(
    List<VorzelaMediaItem> queue, {
    int startIndex = 0,
  }) async {
    _items
      ..clear()
      ..addAll(queue);
    _rebuildOrder(startIndex: startIndex.clamp(0, max(0, queue.length - 1)));
    notifyListeners();
    if (_items.isNotEmpty) {
      await _loadCurrent(autoPlay: false);
    }
  }

  Future<void> playAt(int index, {bool autoPlay = true}) async {
    if (index < 0 || index >= _items.length) return;
    _orderIndex = _order.indexOf(index);
    if (_orderIndex < 0) {
      _rebuildOrder(startIndex: index);
      _orderIndex = _order.indexOf(index);
    }
    notifyListeners();
    await _loadCurrent(autoPlay: autoPlay);
  }

  /// Alias for [playAt] (list tiles).
  Future<void> playIndex(int index, {bool autoPlay = true}) =>
      playAt(index, autoPlay: autoPlay);

  Future<void> next({bool autoPlay = true}) async {
    onSkipNext?.call();
    if (_items.isEmpty) return;
    if (_orderIndex < _order.length - 1) {
      _orderIndex++;
      notifyListeners();
      await _loadCurrent(autoPlay: autoPlay);
      return;
    }
    if (repeatMode == VorzelaRepeatMode.all) {
      _orderIndex = 0;
      notifyListeners();
      await _loadCurrent(autoPlay: autoPlay);
    }
  }

  Future<void> previous({bool autoPlay = true}) async {
    onSkipPrevious?.call();
    if (_items.isEmpty) return;
    if (audio.position > const Duration(seconds: 3)) {
      await audio.seek(Duration.zero);
      return;
    }
    if (_orderIndex > 0) {
      _orderIndex--;
      notifyListeners();
      await _loadCurrent(autoPlay: autoPlay);
      return;
    }
    if (repeatMode == VorzelaRepeatMode.all) {
      _orderIndex = _order.length - 1;
      notifyListeners();
      await _loadCurrent(autoPlay: autoPlay);
    } else {
      await audio.seek(Duration.zero);
    }
  }

  void _rebuildOrder({int startIndex = 0, bool keepCurrent = false}) {
    final n = _items.length;
    if (n == 0) {
      _order = [];
      _orderIndex = 0;
      return;
    }
    final current = keepCurrent ? currentIndex : startIndex;
    _order = List.generate(n, (i) => i);
    if (_shuffle && n > 1) {
      _order.shuffle(Random());
      if (current >= 0 && current < n) {
        _order.remove(current);
        _order.insert(0, current);
      }
    }
    _orderIndex = current >= 0 ? _order.indexOf(current) : 0;
    if (_orderIndex < 0) _orderIndex = 0;
  }

  Future<void> _loadCurrent({required bool autoPlay}) async {
    final item = current;
    if (item == null) return;
    await audio.load(item.uri, autoPlay: autoPlay);
    await audio.syncNowPlaying(
      title: item.title ?? '',
      artist: item.artist ?? '',
    );
  }

  Future<void> _onTrackCompleted() async {
    if (_advancing) return;
    _advancing = true;
    try {
      switch (repeatMode) {
        case VorzelaRepeatMode.one:
          await audio.seek(Duration.zero);
          await audio.play();
        case VorzelaRepeatMode.all:
          await next(autoPlay: true);
        case VorzelaRepeatMode.off:
          if (_orderIndex < _order.length - 1) {
            await next(autoPlay: true);
          }
      }
    } finally {
      _advancing = false;
    }
    _prevCompleted?.call();
  }

  void _onRemoteAction(String action, {int? seekPositionMs}) {
    unawaited(() async {
      switch (action) {
        case 'next':
          await next();
        case 'previous':
          await previous();
        case 'play':
          await audio.play();
        case 'pause':
          await audio.pause();
        case 'seek':
          if (seekPositionMs != null) {
            await audio.seek(Duration(milliseconds: seekPositionMs));
          }
      }
    }());
    _prevRemote?.call(action, seekPositionMs: seekPositionMs);
  }

  @override
  void dispose() {
    audio.onTrackCompleted = _prevCompleted;
    audio.onRemoteAction = _prevRemote;
    audio.dispose();
    super.dispose();
  }
}
