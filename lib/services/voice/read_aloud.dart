import 'package:flutter/foundation.dart';

import 'package:yusal/services/voice/read_aloud_stub.dart'
    if (dart.library.ffi) 'read_aloud_qazvoice.dart' as impl;

/// Where the on-device Kazakh voice model is.
enum VoiceModelPhase {
  notInstalled,
  downloading,

  /// Queued, or waiting for a network.
  waiting,
  paused,
  verifying,
  installed,
  failed,
}

@immutable
class VoiceModelStatus {
  const VoiceModelStatus(this.phase, {this.fraction = 0, this.error = ''});
  static const notInstalled = VoiceModelStatus(VoiceModelPhase.notInstalled);

  final VoiceModelPhase phase;

  /// 0 to 1 while downloading.
  final double fraction;

  /// Why the last download failed.
  final String error;

  /// A download is under way (also while it waits or is checked).
  bool get busy =>
      phase == VoiceModelPhase.downloading ||
      phase == VoiceModelPhase.waiting ||
      phase == VoiceModelPhase.verifying;

  @override
  bool operator ==(Object other) =>
      other is VoiceModelStatus &&
      other.phase == phase &&
      other.fraction == fraction &&
      other.error == error;

  @override
  int get hashCode => Object.hash(phase, fraction, error);
}

/// A license notice the app must show (CC BY 4.0 asks for attribution).
@immutable
class VoiceCredit {
  const VoiceCredit(this.name, this.license, this.text);
  final String name;
  final String license;
  final String text;
}

/// Reads text aloud in Kazakh on the phone itself, through the qazvoice
/// plugin: no server and no network once the voice is downloaded. The
/// voice is a one-time download the user agrees to when they first ask
/// for a reply to be read.
abstract class ReadAloud {
  /// The phone's own voice; null where qazvoice does not run (web,
  /// desktop). Tests may replace it.
  static ReadAloud? instance = impl.create();

  /// Whether [text] is something the Kazakh voice can read: Cyrillic
  /// letters, so not a Chinese reply.
  static bool canRead(String text) => RegExp(r'[\u0400-\u04FF]').hasMatch(text);

  ValueListenable<VoiceModelStatus> get status;

  bool get ready => status.value.phase == VoiceModelPhase.installed;

  /// Bytes the download fetches.
  int get downloadBytes;

  /// Bytes the voice takes once installed.
  int get diskBytes;

  /// Starts the plugin and reads what is installed. Safe to call again.
  Future<void> start();

  /// Downloads the voice in the background; completes when installed.
  Future<void> download();

  Future<void> cancel();

  /// Removes the voice from the phone.
  Future<void> delete();

  /// True while [speak] plays.
  ValueListenable<bool> get speaking;

  /// Reads [text] aloud; completes when it ends or is stopped. A new
  /// call stops the one before it.
  Future<void> speak(String text);

  Future<void> stop();

  /// License notices of the voice.
  List<VoiceCredit> get credits;
}
