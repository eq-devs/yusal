import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/shared/brand/yicon.dart';
import 'package:qazvoice/qazvoice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/features/me/pages/voice_settings.dart';
import 'package:yusal/features/voice/repository/speech.dart';
import 'package:yusal/features/voice/state/reply_reader.dart';
import 'package:yusal/features/voice/widgets/read_aloud_button.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/voice/offline_speech.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/service/voice/voice_engines_qazvoice.dart';
import 'package:yusal/service/voice/voice_settings.dart';
import 'package:yusal/service/voice/wav.dart';
import 'package:yusal/service/voice/wav_player.dart';

class FakeReader extends ReadAloud {
  FakeReader({bool installed = false})
      : phase = ValueNotifier(installed
            ? const VoiceModelStatus(VoiceModelPhase.installed)
            : VoiceModelStatus.notInstalled);

  /// What [status] reports; tests set it to move the model along.
  final ValueNotifier<VoiceModelStatus> phase;
  final _speaking = ValueNotifier(false);
  final spoken = <String>[];
  final how = <(int, double)>[];
  @override
  List<String> get voices => const ['F1', 'F2', 'F3', 'M1', 'M2', 'M3'];
  int stops = 0;
  bool cancelled = false;

  @override
  ValueListenable<VoiceModelStatus> get status => phase;
  @override
  int get downloadBytes => 119000000;
  @override
  int get diskBytes => 128000000;
  @override
  Future<void> start() async {}
  @override
  Future<void> download() async => phase.value =
      const VoiceModelStatus(VoiceModelPhase.downloading, fraction: .4);
  @override
  Future<void> cancel() async {
    cancelled = true;
    phase.value = VoiceModelStatus.notInstalled;
  }

  @override
  Future<void> delete() async => phase.value = VoiceModelStatus.notInstalled;
  @override
  ValueListenable<bool> get speaking => _speaking;
  @override
  Future<void> speak(String text, {int voice = 0, double speed = 1.0}) async {
    spoken.add(text);
    how.add((voice, speed));
    _speaking.value = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _speaking.value = false;
  }

  @override
  List<VoiceCredit> get credits =>
      const [VoiceCredit('Kazakh voice', 'CC-BY-4.0', 'ISSAI KazakhTTS')];
}

class FakeSpeech extends OfflineSpeech {
  FakeSpeech(this.text, {bool installed = false, this.fail = false})
      : _status = ValueNotifier(installed
            ? const VoiceModelStatus(VoiceModelPhase.installed)
            : VoiceModelStatus.notInstalled);
  final String text;
  final bool fail;
  final ValueNotifier<VoiceModelStatus> _status;
  int warmUps = 0;
  @override
  ValueListenable<VoiceModelStatus> get status => _status;
  // ignore: avoid_setters_without_getters
  set phase(VoiceModelStatus s) => _status.value = s;
  @override
  int get downloadBytes => 153000000;
  @override
  int get diskBytes => 196000000;
  @override
  Future<void> start() async {}
  @override
  Future<void> download() async => _status.value =
      const VoiceModelStatus(VoiceModelPhase.downloading, fraction: .4);
  @override
  Future<void> cancel() async => _status.value = VoiceModelStatus.notInstalled;
  @override
  Future<void> delete() async => _status.value = VoiceModelStatus.notInstalled;
  @override
  Future<void> warmUp() async => warmUps++;
  @override
  Future<String> transcribe(Uint8List wav) async =>
      fail ? throw StateError('boom') : text;
  @override
  List<VoiceCredit> get credits => const [];
}

class FakeServer implements SpeechBackend, SpeechSynth {
  final asked = <(String, double)>[];
  @override
  Future<String> transcribe(Uint8List wav) async => 'сервер';
  @override
  Future<Uint8List> synthesize(String text, {double speed = 1.0}) async {
    asked.add((text, speed));
    return Uint8List.fromList([82, 73, 70, 70]);
  }
}

class FakePlayer implements WavPlayer {
  int played = 0;
  int stops = 0;
  @override
  Future<void> play(Uint8List wav) async => played++;
  @override
  Future<void> stop() async => stops++;
}

/// Settings that are not the app's own, so tests do not leak into each
/// other.
VoiceSettings fresh() {
  SharedPreferences.setMockInitialValues({});
  return VoiceSettings.instance
    ..tts = TtsEngine.device
    ..stt = SttEngine.server
    ..voice = 0
    ..speed = 1.0
    ..autoRead = false;
}

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
  b
    ..add('WAVE'.codeUnits)
    ..add('fmt '.codeUnits);
  u32(16);
  u16(1);
  u16(channels);
  u32(rate);
  u32(rate * channels * 2);
  u16(channels * 2);
  u16(16);
  b.add('LIST'.codeUnits); // a chunk to skip
  u32(3);
  b
    ..add([1, 2, 3, 0])
    ..add('data'.codeUnits);
  u32(data.length);
  b.add(data);
  return b.toBytes();
}

/// Half a second of silence, a second of "speech", a second of silence.
Int16List sentence() => Int16List(40000)..fillRange(8000, 24000, 8000);

void main() {
  const installed = VoiceModelStatus(VoiceModelPhase.installed);

  test('only Cyrillic replies can be read', () {
    expect(ReadAloud.canRead('Екі қабатты үй дайын'), isTrue);
    expect(ReadAloud.canRead('Готово'), isTrue);
    expect(ReadAloud.canRead('完成了'), isFalse);
    expect(ReadAloud.canRead(''), isFalse);
  });

  group('QazvoiceReadAloud (qazvoice mock engines)', () {
    test('speaks once tts-kk is installed, and stops', () async {
      QazVoice.useMock(
          platform: MockQazPlatform(installed: {QazTts.modelId: 1}));
      final r = QazvoiceReadAloud();
      await r.start();
      expect(r.ready, isTrue);
      expect(r.downloadBytes, greaterThan(0));
      expect(r.credits, isNotEmpty, reason: 'CC BY 4.0 needs attribution');
      final done = r.speak('Сәлем! Үй дайын.');
      expect(r.speaking.value, isTrue);
      await done;
      expect(r.speaking.value, isFalse);
      final long = r.speak('Бір. Екі. Үш. Төрт. Бес. Алты. Жеті.' * 20);
      await r.stop();
      expect(r.speaking.value, isFalse);
      await long;
    });
  });

  group('WavPcm', () {
    test('reads the samples after other chunks', () {
      final pcm = WavPcm.parse(
          wav(Int16List.fromList([1, -2, 300]), rate: 48000, channels: 2))!;
      expect(pcm.samples, [1, -2, 300]);
      expect((pcm.sampleRate, pcm.channels), (48000, 2));
    });

    test('is null for anything else', () {
      expect(
          WavPcm.parse(Uint8List.fromList('hello world!'.codeUnits)), isNull);
    });
  });

  test('QazvoiceSpeech transcribes with either on-device model', () async {
    for (final id in [QazStt.modelId, QazStt.highAccuracyModelId]) {
      QazVoice.useMock(
          platform: MockQazPlatform(installed: {id: 1}),
          stt: () => MockSttBackend(text: 'екі қабатты үй'));
      final s = QazvoiceSpeech(modelId: id);
      await s.start();
      expect(s.ready, isTrue, reason: id);
      expect(await s.transcribe(wav(sentence())), 'Екі қабатты үй');
      expect(await s.transcribe(wav(Int16List(16000))), '');
    }
  });

  group('ChosenSpeech', () {
    final audio = wav(sentence());
    tearDown(() => OfflineSpeech.standard = OfflineSpeech.accurate = null);

    test('follows the setting, and waits for the download', () async {
      final settings = fresh();
      final std = OfflineSpeech.standard = FakeSpeech('стандарт');
      OfflineSpeech.accurate = FakeSpeech('дәл', installed: true);
      final s = ChosenSpeech(server: FakeServer(), settings: settings);
      expect(await s.transcribe(audio), 'сервер');
      settings.setStt(SttEngine.device);
      expect(await s.transcribe(audio), 'сервер', reason: 'not downloaded yet');
      std.phase = const VoiceModelStatus(VoiceModelPhase.installed);
      expect(await s.transcribe(audio), 'стандарт');
      settings.setStt(SttEngine.deviceAccurate);
      expect(await s.transcribe(audio), 'дәл');
      await s.warmUp();
      expect((OfflineSpeech.accurate! as FakeSpeech).warmUps, 1);
    });

    test('falls back to the server when the phone fails', () async {
      final settings = fresh()..stt = SttEngine.device;
      OfflineSpeech.standard = FakeSpeech('x', installed: true, fail: true);
      expect(
          await ChosenSpeech(server: FakeServer(), settings: settings)
              .transcribe(audio),
          'сервер');
    });
  });

  group('ReplyReader', () {
    test('reads with the chosen engine, voice and speed', () async {
      final settings = fresh()
        ..voice = 4
        ..speed = 1.25;
      final device = FakeReader(installed: true);
      final server = FakeServer();
      final player = FakePlayer();
      final r = ReplyReader(
          device: device, server: server, player: player, settings: settings);
      await r.speak('Сәлем');
      expect(device.how, [(4, 1.25)]);
      expect(r.speaking.value, isTrue);
      settings.setTts(TtsEngine.server);
      await r.speak('Сәлем');
      expect(r.speaking.value, isFalse, reason: 'the server audio ended');
      expect(device.stops, 1, reason: 'the phone voice was stopped first');
      expect(server.asked, [('Сәлем', 1.25)]);
      expect(player.played, 1);
    });

    test('uses whichever voice exists', () {
      final settings = fresh();
      expect(ReplyReader(settings: settings, player: FakePlayer()).available,
          isFalse);
      final onlyServer = ReplyReader(
          server: FakeServer(), settings: settings, player: FakePlayer());
      expect((onlyServer.usesDevice, onlyServer.ready), (false, true));
      settings.tts = TtsEngine.server;
      final onlyDevice = ReplyReader(
          device: FakeReader(), settings: settings, player: FakePlayer());
      expect((onlyDevice.usesDevice, onlyDevice.needsDownload), (true, true));
    });
  });

  group('ReadAloudButton', () {
    final readers = <ReadAloud, ReplyReader>{};
    Future<void> pump(WidgetTester t, ReadAloud r, [String text = 'Дайын']) {
      appLang = AppLang.kk;
      final reader = readers[r] ??= ReplyReader(
          device: r,
          server: FakeServer(),
          player: FakePlayer(),
          settings: VoiceSettings.instance);
      return t.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: Scaffold(
                  body: ReadAloudButton(reader: reader, text: text)))));
    }

    setUp(fresh);

    testWidgets('reads at once when the voice is installed, tap again stops',
        (t) async {
      final r = FakeReader(installed: true);
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(r.spoken, ['Дайын']);
      expect(find.byKey(const Key('voice-download')), findsNothing);
      expect(find.byIcon(YIcons.stop), findsOneWidget);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(r.stops, 1);
      expect(find.byIcon(YIcons.speaker), findsOneWidget);
    });

    testWidgets('first tap offers the download, shows progress, then reads',
        (t) async {
      final r = FakeReader();
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download')), findsOneWidget);
      expect(find.textContaining('119 MB'), findsOneWidget);
      expect(find.textContaining('CC-BY-4.0'), findsOneWidget);
      expect(r.spoken, isEmpty);
      await t.tap(find.byKey(const Key('voice-download-start')));
      await t.pump();
      expect(find.byKey(const Key('voice-download-percent')), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      r.phase.value = installed;
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download')), findsNothing,
          reason: 'the dialog closes by itself');
      expect(r.spoken, ['Дайын']);
    });

    testWidgets('put away, the download goes on and the reply is still read',
        (t) async {
      final r = FakeReader();
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('voice-download-start')));
      await t.pump();
      await t.tap(find.byKey(const Key('voice-download-hide')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download')), findsNothing);
      expect(find.byKey(const Key('voice-speak-progress')), findsOneWidget);
      expect(r.cancelled, isFalse);
      r.phase.value = installed;
      await t.pump();
      expect(r.spoken, ['Дайын']);
    });

    testWidgets('"not now" and cancel read nothing', (t) async {
      final r = FakeReader();
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('voice-download-start')));
      await t.pump();
      await t.tap(find.byKey(const Key('voice-download-cancel')));
      await t.pumpAndSettle();
      expect(r.cancelled, isTrue);
      r.phase.value = installed;
      await t.pump();
      expect(r.spoken, isEmpty);
    });

    testWidgets('a failed download says why and can be retried', (t) async {
      final r = FakeReader()
        ..phase.value =
            const VoiceModelStatus(VoiceModelPhase.failed, error: 'no space');
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download-error')), findsOneWidget);
      expect(find.byKey(const Key('voice-download-start')), findsOneWidget);
    });

    testWidgets('a new reply stops the old one being read', (t) async {
      final r = FakeReader(installed: true);
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pump();
      await pump(t, r, 'Жаңа жауап');
      expect(r.stops, 1);
    });

    testWidgets('with the server voice a tap reads at once, no download',
        (t) async {
      final r = FakeReader();
      VoiceSettings.instance.tts = TtsEngine.server;
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download')), findsNothing);
      expect(r.spoken, isEmpty);
    });

    testWidgets('"read every reply" starts by itself, but never a download',
        (t) async {
      VoiceSettings.instance.autoRead = true;
      final missing = FakeReader();
      await pump(t, missing);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download')), findsNothing);
      expect(missing.spoken, isEmpty);
      final r = FakeReader(installed: true);
      await pump(t, r, 'Бірінші');
      await pump(t, r, 'Екінші');
      expect(r.spoken, ['Бірінші', 'Екінші']);
    });
  });

  group('VoiceSettingsPage', () {
    late FakeReader tts;
    late FakeSpeech std;
    setUp(() {
      fresh();
      ReadAloud.instance = tts = FakeReader();
      OfflineSpeech.standard = std = FakeSpeech('x');
      OfflineSpeech.accurate = FakeSpeech('y');
    });
    tearDown(() {
      ReadAloud.instance = null;
      OfflineSpeech.standard = OfflineSpeech.accurate = null;
    });

    Future<ReplyReader> open(WidgetTester t) async {
      appLang = AppLang.kk;
      t.view.physicalSize = const Size(412, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final reader = ReplyReader(
          device: tts,
          server: FakeServer(),
          player: FakePlayer(),
          settings: VoiceSettings.instance);
      await t.pumpWidget(ProviderScope(
          child: MaterialApp(home: VoiceSettingsPage(reader: reader))));
      await t.pumpAndSettle();
      return reader;
    }

    testWidgets('choosing on-device recognition offers its download',
        (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('voice-stt-engine')));
      await t.pumpAndSettle();
      await t.tap(find.text('Телефонда').last);
      await t.pumpAndSettle();
      expect(VoiceSettings.instance.stt, SttEngine.device);
      expect(find.byKey(const Key('voice-download')), findsOneWidget);
      expect(find.textContaining('153 MB'), findsWidgets);
      await t.tap(find.byKey(const Key('voice-download-start')));
      await t.pump();
      std.phase = const VoiceModelStatus(VoiceModelPhase.installed);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-download')), findsNothing);
      expect(find.textContaining('196 MB'), findsOneWidget,
          reason: 'the models list shows it installed');
    });

    testWidgets('voice, speed and auto-read are kept', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('voice-tts-voice')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ер дауысы 2'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('voice-tts-speed')));
      await t.pumpAndSettle();
      await t.tap(find.text('1.5×'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('voice-auto-read')));
      await t.pumpAndSettle();
      final s = VoiceSettings.instance;
      expect((s.voice, s.speed, s.autoRead), (4, 1.5, true));
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('voice-speaker'), 4);
      expect(p.getDouble('voice-speed'), 1.5);
      expect(p.getBool('voice-auto-read'), true);
    });

    testWidgets('switching to the server hides the voice choice; listen plays',
        (t) async {
      final reader = await open(t);
      await t.tap(find.byKey(const Key('voice-tts-engine')));
      await t.pumpAndSettle();
      await t.tap(find.text('Серверде').last);
      await t.pumpAndSettle();
      expect(VoiceSettings.instance.tts, TtsEngine.server);
      expect(find.byKey(const Key('voice-tts-voice')), findsNothing);
      await t.tap(find.byKey(const Key('voice-listen')));
      await t.pumpAndSettle();
      expect((reader.server! as FakeServer).asked, hasLength(1));
      expect((reader.player as FakePlayer).played, 1);
    });

    testWidgets('an installed model can be deleted', (t) async {
      tts.phase.value = const VoiceModelStatus(VoiceModelPhase.installed);
      await open(t);
      await t.tap(find.byKey(const Key('voice-model-0')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('voice-model-delete')), findsOneWidget);
      await t.tap(find.text('Өшіру'));
      await t.pumpAndSettle();
      expect(tts.ready, isFalse);
    });
  });
}
