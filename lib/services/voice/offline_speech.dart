import 'dart:typed_data';

import 'voice_engines_stub.dart'
    if (dart.library.ffi) 'voice_engines_qazvoice.dart' as impl;
import 'voice_model.dart';

export 'voice_model.dart';

/// Kazakh (and Russian) speech recognition on the phone itself, through
/// the qazvoice plugin: no recording leaves the phone once the model is
/// downloaded.
abstract class OfflineSpeech extends VoiceModel {
  /// The standard recognizer (153 MB); null where qazvoice does not run
  /// (web, desktop). Tests may replace it.
  static OfflineSpeech? standard = impl.createSpeech(accurate: false);

  /// The more accurate, slower and larger recognizer (253 MB).
  static OfflineSpeech? accurate = impl.createSpeech(accurate: true);

  /// Loads the model now, so the first sentence is not slowed by it.
  Future<void> warmUp();

  /// The text of a 16-bit PCM WAV recording; empty when nothing was said.
  Future<String> transcribe(Uint8List wav);
}
