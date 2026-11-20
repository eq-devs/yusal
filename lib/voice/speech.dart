import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories.dart';
import '../services/voice/offline_speech.dart';

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
    if (b is LocalFirstSpeech) unawaited(b.warmUp());
    return audio.startRecording();
  }

  Future<String> heard() async {
    final wav = await audio.stopRecording();
    if (wav == null || wav.isEmpty) return '';
    return backend.transcribe(wav);
  }
}

/// Transcribes on the phone once the user has downloaded the offline
/// Kazakh model (qazvoice), and on the [server] until then, or when the
/// phone fails at it.
class LocalFirstSpeech implements SpeechBackend {
  const LocalFirstSpeech({this.server, this.offline});
  final SpeechBackend? server;
  final OfflineSpeech? offline;

  /// Whether the next sentence is transcribed on the phone.
  bool get onDevice => offline?.ready ?? false;

  Future<void> warmUp() async {
    try {
      if (onDevice) await offline!.warmUp();
    } catch (e) {
      if (kDebugMode) debugPrint('offline speech warm-up: $e');
    }
  }

  @override
  Future<String> transcribe(Uint8List wav) async {
    final local = offline, remote = server;
    if (local != null && local.ready) {
      try {
        return await local.transcribe(wav);
      } catch (e) {
        if (remote == null) rethrow;
        if (kDebugMode)
          debugPrint('offline speech failed, using the server: $e');
      }
    }
    if (remote == null) throw const ApiFailure('VOICE_UNAVAILABLE');
    return remote.transcribe(wav);
  }
}
