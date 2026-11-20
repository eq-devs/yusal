import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qazvoice/qazvoice.dart';

import 'offline_speech.dart';
import 'wav.dart';

/// qazvoice runs on Android and iOS phones only.
OfflineSpeech? create() => !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)
    ? QazvoiceSpeech()
    : null;

/// [OfflineSpeech] through qazvoice's `stt-kk` model (FastConformer,
/// Kazakh and Russian, 153 MB download).
class QazvoiceSpeech extends OfflineSpeech {
  QazvoiceSpeech({this.modelId = QazStt.modelId});

  final String modelId;
  final _status = ValueNotifier(OfflineStatus.notInstalled);
  Future<void>? _starting;
  Future<QazStt>? _stt;
  QazModel? _model;

  @override
  ValueListenable<OfflineStatus> get status => _status;

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

  static OfflineStatus _map(ModelState s) => switch (s) {
        NotInstalled() => OfflineStatus.notInstalled,
        Downloading(:final progress) =>
          OfflineStatus(OfflinePhase.downloading, fraction: progress.fraction),
        Waiting(:final progress) =>
          OfflineStatus(OfflinePhase.waiting, fraction: progress.fraction),
        Paused(:final progress) =>
          OfflineStatus(OfflinePhase.paused, fraction: progress.fraction),
        Verifying() => const OfflineStatus(OfflinePhase.verifying, fraction: 1),
        Installed() => const OfflineStatus(OfflinePhase.installed, fraction: 1),
        Failed(:final error) =>
          OfflineStatus(OfflinePhase.failed, error: error.message),
      };

  @override
  Future<void> download() async {
    await start();
    final m = _model!;
    if (_status.value.phase == OfflinePhase.paused) {
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
    final stt = _stt;
    _stt = null;
    if (stt != null) await (await stt).close();
    await _model!.delete();
  }

  Future<QazStt> _open() async {
    await start();
    final opening = _stt ??= QazStt.open(numbersToDigits: true);
    try {
      return await opening;
    } catch (_) {
      if (identical(_stt, opening)) _stt = null;
      rethrow;
    }
  }

  @override
  Future<void> warmUp() async {
    if (!ready) return;
    await (await _open()).preload();
  }

  @override
  Future<String> transcribe(Uint8List wav) async {
    final pcm = WavPcm.parse(wav);
    if (pcm == null) throw const FormatException('not a 16-bit PCM WAV');
    final session = (await _open()).session();
    await session.addPcm16(pcm.samples,
        sampleRate: pcm.sampleRate, channels: pcm.channels);
    final finals = await session.finish();
    return finals
        .map((r) => r.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' ');
  }

  @override
  List<OfflineCredit> get credits => [
        if (_model != null)
          for (final a in QazVoice.attributions)
            if (a.modelId == modelId) OfflineCredit(a.name, a.license, a.text)
      ];
}
