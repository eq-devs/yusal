import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays a WAV held in memory: what the speech server sends back.
abstract interface class WavPlayer {
  /// Completes when the sound ends or is stopped.
  Future<void> play(Uint8List wav);
  Future<void> stop();
}

/// [WavPlayer] through the `audioplayers` plugin.
class PluginWavPlayer implements WavPlayer {
  AudioPlayer? _player;
  Completer<void>? _playing;

  @override
  Future<void> play(Uint8List wav) async {
    await stop();
    final player = _player ??= AudioPlayer();
    final done = _playing = Completer<void>();
    final sub = player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await player.play(BytesSource(wav, mimeType: 'audio/wav'));
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> stop() async {
    final playing = _playing;
    _playing = null;
    if (playing != null && !playing.isCompleted) playing.complete();
    await _player?.stop();
  }
}
