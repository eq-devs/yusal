import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qazvoice/qazvoice.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/data/repositories.dart';
import 'package:yusal/features/me/offline_voice_page.dart';
import 'package:yusal/services/voice/offline_speech.dart';
import 'package:yusal/services/voice/offline_speech_qazvoice.dart';
import 'package:yusal/services/voice/wav.dart';
import 'package:yusal/voice/speech.dart';

/// A 16-bit PCM WAV, like the `record` plugin writes.
Uint8List wav(Int16List samples, {int rate = 16000, int channels = 1}) {
  final b = BytesBuilder();
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  final data =
      samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);
  b.add('RIFF'.codeUnits);
  u32(36 + data.length);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1);
  u16(channels);
  u32(rate);
  u32(rate * channels * 2);
  u16(channels * 2);
  u16(16);
  b.add('LIST'.codeUnits); // a chunk to skip
  u32(3);
  b.add([1, 2, 3, 0]);
  b.add('data'.codeUnits);
  u32(data.length);
  b.add(data);
  return b.toBytes();
}

/// Half a second of silence, a second of "speech", a second of silence.
Int16List sentence() => Int16List(40000)..fillRange(8000, 24000, 8000);

class FakeServer implements SpeechBackend {
  int calls = 0;
  @override
  Future<String> transcribe(Uint8List wav) async {
    calls++;
    return 'сервер';
  }
}

class FakeOffline extends OfflineSpeech {
  FakeOffline({bool installed = false, this.fail = false})
      : _status = ValueNotifier(installed
            ? const OfflineStatus(OfflinePhase.installed)
            : OfflineStatus.notInstalled);
  final ValueNotifier<OfflineStatus> _status;
  final bool fail;
  int calls = 0, warmUps = 0;

  @override
  ValueListenable<OfflineStatus> get status => _status;
  set phase(OfflineStatus s) => _status.value = s;
  @override
  int get downloadBytes => 153000000;
  @override
  int get diskBytes => 196000000;
  @override
  Future<void> start() async {}
  @override
  Future<void> download() async => _status.value =
      const OfflineStatus(OfflinePhase.downloading, fraction: .4);
  @override
  Future<void> cancel() async => _status.value = OfflineStatus.notInstalled;
  @override
  Future<void> delete() async => _status.value = OfflineStatus.notInstalled;
  @override
  Future<void> warmUp() async => warmUps++;
  @override
  Future<String> transcribe(Uint8List wav) async {
    calls++;
    if (fail) throw const QazEngineError('boom');
    return 'телефон';
  }

  @override
  List<OfflineCredit> get credits =>
      const [OfflineCredit('Speech recognition', 'CC-BY-4.0', 'NVIDIA …')];
}

void main() {
  group('WavPcm', () {
    test('reads the samples after other chunks', () {
      final pcm = WavPcm.parse(
          wav(Int16List.fromList([1, -2, 300]), rate: 48000, channels: 2))!;
      expect(pcm.samples, [1, -2, 300]);
      expect(pcm.sampleRate, 48000);
      expect(pcm.channels, 2);
    });

    test('reads to the end when the recorder left the size unset', () {
      final bytes = wav(Int16List.fromList([5, 6]));
      ByteData.sublistView(bytes).setUint32(bytes.length - 8, 0, Endian.little);
      expect(WavPcm.parse(bytes)!.samples, [5, 6]);
    });

    test('is null for anything else', () {
      expect(
          WavPcm.parse(Uint8List.fromList('hello world!'.codeUnits)), isNull);
      expect(WavPcm.parse(Uint8List(4)), isNull);
    });
  });

  group('LocalFirstSpeech', () {
    final audio = wav(sentence());

    test('uses the server until the model is installed', () async {
      final server = FakeServer(), offline = FakeOffline();
      final s = LocalFirstSpeech(server: server, offline: offline);
      expect(await s.transcribe(audio), 'сервер');
      offline.phase = const OfflineStatus(OfflinePhase.installed);
      expect(await s.transcribe(audio), 'телефон');
      expect((server.calls, offline.calls), (1, 1));
    });

    test('falls back to the server when the phone fails', () async {
      final server = FakeServer();
      final s = LocalFirstSpeech(
          server: server, offline: FakeOffline(installed: true, fail: true));
      expect(await s.transcribe(audio), 'сервер');
    });

    test('says voice is unavailable with neither', () async {
      await expectLater(
          const LocalFirstSpeech().transcribe(audio),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'VOICE_UNAVAILABLE')));
    });

    test('warms the model up only when it is installed', () async {
      final off = FakeOffline();
      final s = LocalFirstSpeech(offline: off);
      await s.warmUp();
      expect(off.warmUps, 0);
      off.phase = const OfflineStatus(OfflinePhase.installed);
      await s.warmUp();
      expect(off.warmUps, 1);
    });
  });

  group('QazvoiceSpeech (qazvoice mock engines)', () {
    test('transcribes a recording once stt-kk is installed', () async {
      QazVoice.useMock(
          platform: MockQazPlatform(installed: {QazStt.modelId: 1}),
          stt: () => MockSttBackend(text: 'екі қабатты үй'));
      final s = QazvoiceSpeech();
      await s.start();
      expect(s.ready, isTrue);
      expect(s.downloadBytes, greaterThan(0));
      expect(s.credits, isNotEmpty, reason: 'CC BY 4.0 needs attribution');
      expect(await s.transcribe(wav(sentence())), 'Екі қабатты үй');
      expect(await s.transcribe(wav(Int16List(16000))), '',
          reason: 'silence is nothing said');
      await expectLater(s.transcribe(Uint8List(8)), throwsFormatException);
    });
  });

  group('OfflineVoicePage', () {
    Future<void> open(WidgetTester t, OfflineSpeech s) async {
      AppSettings.instance.lang = AppLang.kk;
      await t.pumpWidget(MaterialApp(
          builder: (_, child) => AppScope(child: child!),
          home: OfflineVoicePage(speech: s)));
      await t.pumpAndSettle();
    }

    testWidgets('downloads with its size, then can delete', (t) async {
      final s = FakeOffline();
      await open(t, s);
      expect(find.textContaining('153 MB'), findsWidgets);
      expect(find.textContaining('CC-BY-4.0'), findsOneWidget);
      await t.tap(find.byKey(const Key('offline-voice-download')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('offline-voice-progress')), findsOneWidget);
      expect(find.textContaining('40%'), findsOneWidget);
      s.phase = const OfflineStatus(OfflinePhase.installed);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('offline-voice-ready')), findsOneWidget);
      await t.tap(find.byKey(const Key('offline-voice-delete')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('offline-voice-download')), findsOneWidget);
    });

    testWidgets('shows why a download failed', (t) async {
      final s = FakeOffline()
        ..phase = const OfflineStatus(OfflinePhase.failed, error: 'no space');
      await open(t, s);
      expect(find.byKey(const Key('offline-voice-error')), findsOneWidget);
      expect(find.textContaining('no space'), findsOneWidget);
    });
  });
}
