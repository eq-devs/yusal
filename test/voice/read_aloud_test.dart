import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qazvoice/qazvoice.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/features/me/kazakh_voice_page.dart';
import 'package:yusal/services/voice/read_aloud.dart';
import 'package:yusal/services/voice/read_aloud_qazvoice.dart';
import 'package:yusal/voice/read_aloud_button.dart';

class FakeReader extends ReadAloud {
  FakeReader({bool installed = false})
      : _status = ValueNotifier(installed
            ? const VoiceModelStatus(VoiceModelPhase.installed)
            : VoiceModelStatus.notInstalled);
  final ValueNotifier<VoiceModelStatus> _status;
  final _speaking = ValueNotifier(false);
  final spoken = <String>[];
  int stops = 0;
  bool cancelled = false;

  @override
  ValueListenable<VoiceModelStatus> get status => _status;
  set phase(VoiceModelStatus s) => _status.value = s;
  @override
  int get downloadBytes => 119000000;
  @override
  int get diskBytes => 128000000;
  @override
  Future<void> start() async {}
  @override
  Future<void> download() async => _status.value =
      const VoiceModelStatus(VoiceModelPhase.downloading, fraction: .4);
  @override
  Future<void> cancel() async {
    cancelled = true;
    _status.value = VoiceModelStatus.notInstalled;
  }

  @override
  Future<void> delete() async => _status.value = VoiceModelStatus.notInstalled;
  @override
  ValueListenable<bool> get speaking => _speaking;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
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

  group('ReadAloudButton', () {
    Future<void> pump(WidgetTester t, ReadAloud r, [String text = 'Дайын']) {
      AppSettings.instance.lang = AppLang.kk;
      return t.pumpWidget(MaterialApp(
          home: Scaffold(body: ReadAloudButton(reader: r, text: text))));
    }

    testWidgets('reads at once when the voice is installed, tap again stops',
        (t) async {
      final r = FakeReader(installed: true);
      await pump(t, r);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(r.spoken, ['Дайын']);
      expect(find.byKey(const Key('voice-download')), findsNothing);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      await t.tap(find.byKey(const Key('voice-speak')));
      await t.pumpAndSettle();
      expect(r.stops, 1);
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
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
      r.phase = installed;
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
      r.phase = installed;
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
      r.phase = installed;
      await t.pump();
      expect(r.spoken, isEmpty);
    });

    testWidgets('a failed download says why and can be retried', (t) async {
      final r = FakeReader()
        ..phase =
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
  });

  group('KazakhVoicePage', () {
    testWidgets('downloads with its size, then can delete', (t) async {
      AppSettings.instance.lang = AppLang.kk;
      final r = FakeReader();
      await t.pumpWidget(MaterialApp(
          builder: (_, child) => AppScope(child: child!),
          home: KazakhVoicePage(reader: r)));
      await t.pumpAndSettle();
      expect(find.textContaining('119 MB'), findsWidgets);
      expect(find.textContaining('CC-BY-4.0'), findsOneWidget);
      await t.tap(find.byKey(const Key('kazakh-voice-download')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('kazakh-voice-progress')), findsOneWidget);
      r.phase = installed;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('kazakh-voice-delete')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('kazakh-voice-download')), findsOneWidget);
    });
  });
}
