import 'package:flutter/foundation.dart';

import 'package:yusal/service/voice/voice_engines_stub.dart'
    if (dart.library.ffi) 'voice_engines_qazvoice.dart' as impl;
import 'package:yusal/service/voice/voice_model.dart';

export 'package:yusal/service/voice/voice_model.dart';

/// Reads text aloud in Kazakh on the phone itself, through the qazvoice
/// plugin: no server and no network once the voice is downloaded. The
/// voice is a one-time download the user agrees to when they first ask
/// for a reply to be read.
abstract class ReadAloud extends VoiceModel {
  /// The phone's own voice; null where qazvoice does not run (web,
  /// desktop). Tests may replace it.
  static ReadAloud? instance = impl.createReadAloud();

  /// Whether [text] is something the Kazakh voice can read: Cyrillic
  /// letters, so not a Chinese reply.
  static bool canRead(String text) => RegExp(r'[\u0400-\u04FF]').hasMatch(text);

  /// How many voices the model has; [speak]'s `voice` is below this.
  static const voiceCount = 6;

  /// The voices' names once the model has been opened (`F1`, `M2`…);
  /// empty before.
  List<String> get voices;

  /// True while [speak] plays.
  ValueListenable<bool> get speaking;

  /// Reads [text] aloud; completes when it ends or is stopped. A new
  /// call stops the one before it. [speed] 1.0 is natural (0.5 to 2.0).
  Future<void> speak(String text, {int voice = 0, double speed = 1.0});

  Future<void> stop();
}
