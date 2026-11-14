import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'speech.dart';

/// The device's microphone and speaker through the `record` and
/// `audioplayers` plugins. Both go through a file in the temp directory.
class PluginAudio implements AudioDevice {
  AudioRecorder? _recorder;
  AudioPlayer? _player;

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
  Future<void> play(Uint8List wav) async {
    final path = await _file('voice_out.wav');
    await File(path).writeAsBytes(wav);
    await (_player ??= AudioPlayer()).play(DeviceFileSource(path));
  }

  @override
  Future<void> stopPlaying() async => _player?.stop();

  @override
  Future<void> dispose() async {
    await _recorder?.dispose();
    await _player?.dispose();
  }
}
