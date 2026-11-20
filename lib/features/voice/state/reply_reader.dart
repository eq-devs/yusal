import 'package:flutter/foundation.dart';

import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/service/voice/voice_settings.dart';
import 'package:yusal/service/voice/wav_player.dart';
import 'package:yusal/features/voice/repository/speech.dart';

/// Reads a reply aloud the way the voice settings say: with the phone's
/// own voice (qazvoice), or with audio from the speech server.
class ReplyReader {
  ReplyReader(
      {this.device, this.server, WavPlayer? player, VoiceSettings? settings})
      : player = player ?? PluginWavPlayer(),
        settings = settings ?? VoiceSettings.instance {
    device?.speaking.addListener(_sync);
  }

  /// The phone's voice; null where qazvoice does not run.
  final ReadAloud? device;

  /// The server's voice; null without a backend that has one.
  final SpeechSynth? server;
  final WavPlayer player;
  final VoiceSettings settings;

  final _speaking = ValueNotifier(false);
  bool _serverSpeaking = false;
  int _turn = 0;

  /// True while a reply is being read, by either voice.
  ValueListenable<bool> get speaking => _speaking;

  void _sync() =>
      _speaking.value = _serverSpeaking || (device?.speaking.value ?? false);

  /// Whether there is any voice to read with.
  bool get available => device != null || server != null;

  /// Whether the phone's voice is the one to use: chosen in the
  /// settings, or the only one there is.
  bool get usesDevice =>
      device != null && (settings.tts == TtsEngine.device || server == null);

  /// The phone's voice is the one to use but is not downloaded yet.
  bool get needsDownload => usesDevice && !device!.ready;

  /// Whether [speak] can start right now, without asking for a download.
  bool get ready => available && !needsDownload;

  Future<void> speak(String text) async {
    await stop();
    if (usesDevice) {
      return device!.speak(text, voice: settings.voice, speed: settings.speed);
    }
    final turn = ++_turn;
    _serverSpeaking = true;
    _sync();
    try {
      final wav = await server!.synthesize(text, speed: settings.speed);
      if (turn == _turn) await player.play(wav);
    } finally {
      if (turn == _turn) {
        _serverSpeaking = false;
        _sync();
      }
    }
  }

  Future<void> stop() async {
    _turn++;
    if (_serverSpeaking) {
      _serverSpeaking = false;
      _sync();
      await player.stop();
    }
    if (device?.speaking.value ?? false) await device!.stop();
  }

  void dispose() {
    device?.speaking.removeListener(_sync);
    stop();
  }
}
