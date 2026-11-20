import 'package:flutter/foundation.dart';

import 'offline_speech_stub.dart'
    if (dart.library.ffi) 'offline_speech_qazvoice.dart' as impl;

/// Where the on-device Kazakh speech model is.
enum OfflinePhase {
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
class OfflineStatus {
  const OfflineStatus(this.phase, {this.fraction = 0, this.error = ''});
  static const notInstalled = OfflineStatus(OfflinePhase.notInstalled);

  final OfflinePhase phase;

  /// 0 to 1 while downloading.
  final double fraction;

  /// Why the last download failed.
  final String error;

  /// A download is under way (also while it waits or is checked).
  bool get busy =>
      phase == OfflinePhase.downloading ||
      phase == OfflinePhase.waiting ||
      phase == OfflinePhase.verifying;

  @override
  bool operator ==(Object other) =>
      other is OfflineStatus &&
      other.phase == phase &&
      other.fraction == fraction &&
      other.error == error;

  @override
  int get hashCode => Object.hash(phase, fraction, error);
}

/// A license notice the app must show (CC BY 4.0 asks for attribution).
@immutable
class OfflineCredit {
  const OfflineCredit(this.name, this.license, this.text);
  final String name, license, text;
}

/// Kazakh speech recognition on the phone itself, through the qazvoice
/// plugin: no server and no network once the model is downloaded. The
/// model is a one-time download the user asks for; until it is installed
/// the app transcribes on the server as before.
abstract class OfflineSpeech {
  /// The phone's own recognizer; null where qazvoice does not run (web,
  /// desktop). Tests may replace it.
  static OfflineSpeech? instance = impl.create();

  ValueListenable<OfflineStatus> get status;

  bool get ready => status.value.phase == OfflinePhase.installed;

  /// Bytes the download fetches.
  int get downloadBytes;

  /// Bytes the model takes once installed.
  int get diskBytes;

  /// Starts the plugin and reads what is installed. Safe to call again.
  Future<void> start();

  /// Downloads the model in the background; completes when installed.
  Future<void> download();

  Future<void> cancel();

  /// Removes the model; the app goes back to the server.
  Future<void> delete();

  /// Loads the model now, so the first sentence is not slowed by it.
  Future<void> warmUp();

  /// The text of a 16-bit PCM WAV recording; empty when nothing was said.
  Future<String> transcribe(Uint8List wav);

  /// License notices of the model.
  List<OfflineCredit> get credits;
}
