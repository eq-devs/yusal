import 'dart:typed_data';

/// What speech needs from the server. yusal-api proxies the speech service
/// (Kazakh only), so its key never ships in the app. Replies are shown as
/// text, not read aloud.
abstract interface class SpeechBackend {
  /// The text of a WAV recording; empty when nothing was said.
  Future<String> transcribe(Uint8List wav);
}

/// The microphone.
abstract interface class AudioDevice {
  /// Starts recording; false when the microphone is not allowed.
  Future<bool> startRecording();

  /// Ends the recording and returns it as 16 kHz mono WAV.
  Future<Uint8List?> stopRecording();

  Future<void> dispose();
}

/// Push-to-talk: record a sentence and get its text.
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
}
