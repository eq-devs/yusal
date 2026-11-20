import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories.dart';
import '../services/voice/offline_speech.dart';
import '../services/voice/voice_settings.dart';

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

  /// How loud the microphone hears, 0 (quiet) to 1 (loud), several times a
  /// second while recording. For showing that the app is listening.
  Stream<double> get levels;

  Future<void> dispose();
}

/// Push-to-talk: record a sentence and get its text.
class Speech {
  const Speech(this.backend, this.audio);
  final SpeechBackend backend;
  final AudioDevice audio;

  /// The speech service cuts a sentence at 25 s.
  static const maxSentence = Duration(seconds: 25);

  /// Starts recording, and loads the on-device model meanwhile.
  Future<bool> start() {
    final b = backend;
    if (b is ChosenSpeech) unawaited(b.warmUp());
    return audio.startRecording();
  }

  Future<String> heard() async {
    final wav = await audio.stopRecording();
    if (wav == null || wav.isEmpty) return '';
    return backend.transcribe(wav);
  }
}

/// What the server reads aloud. yusal-api proxies the speech service.
abstract interface class SpeechSynth {
  /// [text] as WAV. [speed] 1.0 is natural (0.5 to 2.0).
  Future<Uint8List> synthesize(String text, {double speed});
}

/// Transcribes where the user chose in the voice settings: on the phone
/// (qazvoice) once that model is downloaded, otherwise on the [server].
/// The server also takes over when the phone fails at a sentence.
class ChosenSpeech implements SpeechBackend {
  ChosenSpeech({this.server, VoiceSettings? settings})
      : settings = settings ?? VoiceSettings.instance;
  final SpeechBackend? server;
  final VoiceSettings settings;

  /// The recognizer the settings name; null for the server.
  OfflineSpeech? get chosen => switch (settings.stt) {
        SttEngine.server => null,
        SttEngine.device => OfflineSpeech.standard,
        SttEngine.deviceAccurate => OfflineSpeech.accurate,
      };

  /// Whether the next sentence is transcribed on the phone.
  bool get onDevice => chosen?.ready ?? false;

  Future<void> warmUp() async {
    try {
      if (onDevice) await chosen!.warmUp();
    } catch (e) {
      if (kDebugMode) debugPrint('offline speech warm-up: $e');
    }
  }

  @override
  Future<String> transcribe(Uint8List wav) async {
    final local = chosen, remote = server;
    if (local != null && local.ready) {
      try {
        return await local.transcribe(wav);
      } catch (e) {
        if (remote == null) rethrow;
        if (kDebugMode) {
          debugPrint('offline speech failed, using the server: $e');
        }
      }
    }
    if (remote == null) throw const ApiFailure('VOICE_UNAVAILABLE');
    return remote.transcribe(wav);
  }
}
