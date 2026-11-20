import 'package:flutter/foundation.dart';

/// Where a downloadable on-device model is.
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

/// A model the qazvoice plugin runs on the phone: a one-time download,
/// then no server and no network.
abstract class VoiceModel {
  ValueListenable<VoiceModelStatus> get status;

  bool get ready => status.value.phase == VoiceModelPhase.installed;

  /// Bytes the download fetches.
  int get downloadBytes;

  /// Bytes the model takes once installed.
  int get diskBytes;

  /// Starts the plugin and reads what is installed. Safe to call again.
  Future<void> start();

  /// Downloads the model in the background; completes when installed.
  Future<void> download();

  Future<void> cancel();

  /// Removes the model from the phone.
  Future<void> delete();

  /// License notices of the model.
  List<VoiceCredit> get credits;
}
