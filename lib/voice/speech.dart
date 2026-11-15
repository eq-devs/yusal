import 'dart:typed_data';

/// What speech needs from the server. yusal-api proxies the speech service
/// (Kazakh only), so its key never ships in the app.
abstract interface class SpeechBackend {
  /// The text of a WAV recording; empty when nothing was said.
  Future<String> transcribe(Uint8List wav);

  /// [text] read aloud, as WAV.
  Future<Uint8List> synthesize(String text);
}

/// The microphone and the speaker.
abstract interface class AudioDevice {
  /// Starts recording; false when the microphone is not allowed.
  Future<bool> startRecording();

  /// Ends the recording and returns it as 16 kHz mono WAV.
  Future<Uint8List?> stopRecording();

  Future<void> play(Uint8List wav);
  Future<void> stopPlaying();
  Future<void> dispose();
}

/// Push-to-talk: record a sentence, get its text, read the reply aloud.
class Speech {
  const Speech(this.backend, this.audio);
  final SpeechBackend backend;
  final AudioDevice audio;

  /// The speech service cuts a sentence at 25 s.
  static const maxSentence = Duration(seconds: 25);

  Future<String> heard() async {
    final wav = await audio.stopRecording();
    if (wav == null || wav.isEmpty) return '';
    return backend.transcribe(wav);
  }

  Future<void> speak(String text) async =>
      audio.play(await backend.synthesize(text));
}
