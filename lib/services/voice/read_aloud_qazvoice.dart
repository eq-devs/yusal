import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qazvoice/qazvoice.dart';

import 'package:yusal/services/voice/read_aloud.dart';

/// qazvoice runs on Android and iOS phones only.
ReadAloud? create() => !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)
    ? QazvoiceReadAloud()
    : null;

/// [ReadAloud] through qazvoice's `tts-kk` voice (Piper, 119 MB download)
/// and its built-in playback.
class QazvoiceReadAloud extends ReadAloud {
  QazvoiceReadAloud({this.modelId = QazTts.modelId});

  final String modelId;
  final _status = ValueNotifier(VoiceModelStatus.notInstalled);
  Future<void>? _starting;
  Future<QazTts>? _tts;
  final _speaking = ValueNotifier(false);
  int _turn = 0;
  QazModel? _model;

  @override
  ValueListenable<VoiceModelStatus> get status => _status;

  @override
  int get downloadBytes => _model?.downloadSize ?? 0;

  @override
  int get diskBytes => _model?.diskSize ?? 0;

  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      await QazVoice.init(notification: const QazNotificationConfig.kk());
      final m = _model = QazVoice.model(modelId);
      void sync() => _status.value = _map(m.state.value);
      m.state.addListener(sync);
      sync();
    } catch (e) {
      // Let a later call try again.
      _starting = null;
      rethrow;
    }
  }

  static VoiceModelStatus _map(ModelState s) => switch (s) {
        NotInstalled() => VoiceModelStatus.notInstalled,
        Downloading(:final progress) => VoiceModelStatus(
            VoiceModelPhase.downloading,
            fraction: progress.fraction),
        Waiting(:final progress) => VoiceModelStatus(VoiceModelPhase.waiting,
            fraction: progress.fraction),
        Paused(:final progress) =>
          VoiceModelStatus(VoiceModelPhase.paused, fraction: progress.fraction),
        Verifying() =>
          const VoiceModelStatus(VoiceModelPhase.verifying, fraction: 1),
        Installed() =>
          const VoiceModelStatus(VoiceModelPhase.installed, fraction: 1),
        Failed(:final error) =>
          VoiceModelStatus(VoiceModelPhase.failed, error: error.message),
      };

  @override
  Future<void> download() async {
    await start();
    final m = _model!;
    if (_status.value.phase == VoiceModelPhase.paused) {
      await m.resume();
    }
    await m.download();
  }

  @override
  Future<void> cancel() async {
    await start();
    await _model!.cancel();
  }

  @override
  Future<void> delete() async {
    await start();
    await stop();
    final tts = _tts;
    _tts = null;
    if (tts != null) await (await tts).close();
    await _model!.delete();
  }

  Future<QazTts> _open() async {
    await start();
    final opening = _tts ??= QazTts.open();
    try {
      return await opening;
    } catch (_) {
      if (identical(_tts, opening)) _tts = null;
      rethrow;
    }
  }

  @override
  ValueListenable<bool> get speaking => _speaking;

  @override
  Future<void> speak(String text) async {
    // Only the newest call owns the flag: an older one ending (it was
    // stopped by this one) must not clear it.
    final turn = ++_turn;
    _speaking.value = true;
    try {
      await (await _open()).speak(text);
    } finally {
      if (turn == _turn) _speaking.value = false;
    }
  }

  @override
  Future<void> stop() async {
    _turn++;
    _speaking.value = false;
    final tts = _tts;
    if (tts != null) await (await tts).stop();
  }

  @override
  List<VoiceCredit> get credits => [
        if (_model != null)
          for (final a in QazVoice.attributions)
            if (a.modelId == modelId) VoiceCredit(a.name, a.license, a.text)
      ];
}
