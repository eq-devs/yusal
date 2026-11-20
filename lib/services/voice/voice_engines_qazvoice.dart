import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qazvoice/qazvoice.dart';

import 'offline_speech.dart';
import 'read_aloud.dart';
import 'wav.dart';

/// qazvoice runs on Android and iOS phones only.
bool get _phone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

ReadAloud? createReadAloud() => _phone ? QazvoiceReadAloud() : null;

OfflineSpeech? createSpeech({required bool accurate}) => _phone
    ? QazvoiceSpeech(
        modelId: accurate ? QazStt.highAccuracyModelId : QazStt.modelId)
    : null;

/// One qazvoice model: where its download is, and its license notices.
mixin _QazModel implements VoiceModel {
  String get modelId;

  final _status = ValueNotifier(VoiceModelStatus.notInstalled);
  Future<void>? _starting;
  QazModel? _model;

  @override
  ValueListenable<VoiceModelStatus> get status => _status;

  @override
  bool get ready => _status.value.phase == VoiceModelPhase.installed;

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

  /// Lets go of the loaded engine before the files are removed.
  Future<void> _close();

  @override
  Future<void> delete() async {
    await start();
    await _close();
    await _model!.delete();
  }

  @override
  List<VoiceCredit> get credits => [
        if (_model != null)
          for (final a in QazVoice.attributions)
            if (a.modelId == modelId) VoiceCredit(a.name, a.license, a.text)
      ];
}

/// [ReadAloud] through qazvoice's `tts-kk` voice (Piper, 119 MB download)
/// and its built-in playback.
class QazvoiceReadAloud extends ReadAloud with _QazModel {
  @override
  String get modelId => QazTts.modelId;

  Future<QazTts>? _tts;
  final _speaking = ValueNotifier(false);
  int _turn = 0;
  List<String> _voices = const [];

  @override
  List<String> get voices => _voices;

  @override
  Future<void> _close() async {
    await stop();
    final tts = _tts;
    _tts = null;
    if (tts != null) await (await tts).close();
  }

  Future<QazTts> _open() async {
    await start();
    final opening = _tts ??= QazTts.open();
    try {
      final tts = await opening;
      _voices = tts.speakers;
      return tts;
    } catch (_) {
      if (identical(_tts, opening)) _tts = null;
      rethrow;
    }
  }

  @override
  ValueListenable<bool> get speaking => _speaking;

  @override
  Future<void> speak(String text, {int voice = 0, double speed = 1.0}) async {
    // Only the newest call owns the flag: an older one ending (it was
    // stopped by this one) must not clear it.
    final turn = ++_turn;
    _speaking.value = true;
    try {
      final tts = await _open();
      await tts.speak(text,
          speaker: voice < tts.speakers.length ? voice : 0,
          speed: speed.clamp(0.5, 2.0));
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
}

/// [OfflineSpeech] through a qazvoice recognizer: `stt-kk` (FastConformer,
/// 153 MB) or `stt-kk-giga` (GigaAM, more accurate, 253 MB).
class QazvoiceSpeech extends OfflineSpeech with _QazModel {
  QazvoiceSpeech({this.modelId = QazStt.modelId});

  @override
  final String modelId;

  Future<QazStt>? _stt;

  @override
  Future<void> _close() async {
    final stt = _stt;
    _stt = null;
    if (stt != null) await (await stt).close();
  }

  Future<QazStt> _open() async {
    await start();
    final opening = _stt ??= QazStt.open(model: modelId, numbersToDigits: true);
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
}
