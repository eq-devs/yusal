import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:yusal/features/voice/repository/speech.dart';

/// The device's microphone through the `record` plugin, by way of a file
/// in the temp directory.
class PluginAudio implements AudioDevice {
  AudioRecorder? _recorder;

  Future<String> _file(String name) async =>
      '${(await getTemporaryDirectory()).path}/$name';

  @override
  Future<bool> startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;
    await recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: await _file('voice_in.wav'));
    return true;
  }

  // The plugin reports decibels below full scale: a quiet room is near
  // -50, speech close to the phone near -10.
  @override
  Stream<double> get levels => (_recorder ??= AudioRecorder())
      .onAmplitudeChanged(const Duration(milliseconds: 60))
      .map((a) => ((a.current + 50) / 40).clamp(0.0, 1.0));

  @override
  Future<Uint8List?> stopRecording() async {
    final path = await _recorder?.stop();
    if (path == null) return null;
    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  @override
  Future<void> dispose() async {
    await _recorder?.dispose();
  }
}
