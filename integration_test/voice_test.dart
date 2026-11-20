// Voice control on a real phone or simulator: the bar over the real app, a
// spoken request through the device's microphone, and a design
// edited and undone by one sentence. The language model and the speech
// service are scripted here, so no server is needed.
//
//   xcrun simctl privacy <simulator-id> grant microphone com.yusal.client
//   flutter test integration_test/voice_test.dart -d <simulator-id>
//
// `flutter test` removes the app when a run ends, and that drops the grant:
// grant before every run (granting while the app runs stops the app).
// Without it iOS asks on screen and the two tests that record fail with
// "the microphone must be allowed".
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/editor/house_editor.dart';
import 'package:yusal/main.dart';
import '../test/support/mock/mock_backend.dart';
import 'package:yusal/domain/models.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/audio_device.dart';
import 'package:yusal/voice/screen.dart';
import 'package:yusal/voice/session.dart';
import 'package:yusal/voice/speech.dart';
import 'package:yusal/voice/voice_overlay.dart';

VoiceTurn act(String turnId, List<(String, Map<String, Object?>)> calls) =>
    VoiceTurn(turnId: turnId, calls: [
      for (final (i, c) in calls.indexed) ActionCall('c$i', c.$1, c.$2)
    ]);

/// The in-memory backend plus a scripted language model and speech service.
class VoiceMock extends MockBackend implements VoiceBackend, SpeechBackend {
  VoiceMock(this.turns, {this.hears = ''})
      : super(latency: Duration.zero, seed: false) {
    // The orb shows only for someone signed in (the assistant acts on an
    // account's own designs), and this backend starts with no accounts.
    accounts[_user] = Account(
        id: _user,
        phone: '+77010000000',
        displayName: 'Voice test',
        createdAt: now);
    signInAs(_user);
  }
  static const _user = 'acc_voice_test';
  final List<VoiceTurn> turns;
  final String hears;
  final said = <({String text, bool spoken, Map<String, Object?> context})>[];
  final recordings = <Uint8List>[];

  @override
  Future<VoiceTurn> say(
      {required String sessionId,
      required String text,
      required bool spoken,
      required Map<String, Object?> context}) async {
    said.add((text: text, spoken: spoken, context: context));
    return turns.removeAt(0);
  }

  @override
  Future<VoiceTurn> results(
          {required String turnId,
          required List<Map<String, Object?>> results,
          required Map<String, Object?> context}) async =>
      turns.removeAt(0);

  @override
  Future<String> transcribe(Uint8List wav) async {
    recordings.add(wav);
    return hears;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final onPhone = Platform.isIOS || Platform.isAndroid;

  /// Waits off the test clock (recording, playing, files).
  Future<void> real(WidgetTester t, int ms) async {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump();
  }

  /// [settle] is off while the orb listens: it turns for as long as it
  /// does, so the page never settles until the sentence's time is up.
  Future<void> waitFor(WidgetTester t, bool Function() done,
      {bool settle = true}) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await real(t, 100);
    }
    if (settle) await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String text) async {
    // Set through the controller: the simulated keyboard does not always
    // reach a field in an overlay.
    // A long press opens typing; a tap would start listening. The field
    // closes again when a sentence is sent.
    if (find.byKey(const Key('voice-input')).evaluate().isEmpty) {
      await t.longPress(find.byKey(const Key('voice-button')));
      await t.pumpAndSettle();
    }
    final field = t.widget<TextField>(find.byKey(const Key('voice-input')));
    field.controller!.text = text;
    field.onSubmitted!(text);
    await t.pumpAndSettle();
  }

  /// The answer's bubble lists what was done only while the sentence runs;
  /// afterwards a tap on the bubble opens the list.
  Future<void> showSteps(WidgetTester t, String reply) async {
    await t.tap(find.text(reply));
    await t.pumpAndSettle();
  }

  testWidgets('the bar over the real app changes tabs by a typed request',
      (t) async {
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);
    AppSettings.instance.lang = AppLang.zh;
    final repos = VoiceMock([
      act('t1', [
        ('nav.tab', {'tab': 'me'})
      ]),
      const VoiceTurn(reply: '已打开“我的”。'),
    ]);
    try {
      await t.pumpWidget(ProviderScope(child: HouseApp(repos: repos)));
      await t.pumpAndSettle();
      final start = VoiceScreens.current!.screenId;
      expect(start, startsWith('shell.'));
      expect(start, isNot('shell.me'));

      await type(t, '打开我的');
      await waitFor(t, () => find.text('已打开“我的”。').evaluate().isNotEmpty);

      expect(VoiceScreens.current!.screenId, 'shell.me');
      await showSteps(t, '已打开“我的”。');
      expect(find.text('切换主页面'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // The model was told where the user was and what could run there.
      final sent = repos.said.single;
      expect((sent.text, sent.spoken), ('打开我的', false));
      expect(sent.context['screen'], start);
      expect(sent.context['actions'], contains('nav.tab'));
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
    }
  });

  testWidgets('a spoken request is recorded, sent as heard and answered in text',
      (t) async {
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);
    AppSettings.instance.lang = AppLang.kk;
    final repos = VoiceMock([const VoiceTurn(reply: 'Жарайды.')],
        hears: 'менің бетімді аш');
    try {
      await t.pumpWidget(ProviderScope(child: HouseApp(repos: repos)));
      await t.pumpAndSettle();
      // Tap the orb to listen, tap it again when done.
      await t.tap(find.byKey(const Key('voice-button')));
      await waitFor(
          t, () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
          settle: false);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget,
          reason: 'the microphone must be allowed (see the top of this file)');
      await real(t, 1500);
      await t.tap(find.byKey(const Key('voice-button')));
      await waitFor(t, () => find.text('Жарайды.').evaluate().isNotEmpty);

      // What the speech service got: a 16 kHz mono 16-bit WAV of about the
      // time spoken.
      final wav = ByteData.sublistView(repos.recordings.single);
      expect(String.fromCharCodes(repos.recordings.single.take(4)), 'RIFF');
      expect(wav.getUint16(22, Endian.little), 1, reason: 'channels');
      expect(wav.getUint32(24, Endian.little), 16000, reason: 'sample rate');
      expect(wav.getUint16(34, Endian.little), 16, reason: 'bits per sample');
      expect(wav.lengthInBytes, inInclusiveRange(16000, 160000));

      expect(repos.said.map((s) => (s.text, s.spoken)),
          [('менің бетімді аш', true)]);
      expect(find.text('Жарайды.'), findsOneWidget);
      await real(t, 1200);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
      AppSettings.instance.lang = AppLang.zh;
    }
  }, skip: !onPhone);

  testWidgets('the microphone records twice in a row', (t) async {
    final audio = PluginAudio();
    await t.runAsync(() async {
      // Twice in a row: the second recording must not reuse the first file.
      for (var i = 0; i < 2; i++) {
        // Without the permission iOS shows its prompt and this never returns.
        expect(
            await audio
                .startRecording()
                .timeout(const Duration(seconds: 10), onTimeout: () => false),
            isTrue,
            reason:
                'the microphone must be allowed (see the top of this file)');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final wav = await audio.stopRecording();
        expect(wav, isNotNull);
        expect(String.fromCharCodes(wav!.take(4)), 'RIFF');
        expect(wav.length, greaterThan(44));
      }
      expect(await audio.stopRecording(), isNull);
      await audio.dispose();
    });
  }, skip: !onPhone);

  testWidgets('one sentence edits the open design and undoes as one step',
      (t) async {
    final store = ProjectStore();
    var sequence = 0;
    final previous = await LastOpenProject.read();
    final doc = createHouse(
        name: 'Yusal voice test',
        width: 10000,
        depth: 8000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        newId: () => 'voice_${sequence++}');
    final id = await store.createProject(doc);
    AppSettings.instance.lang = AppLang.zh;
    final repos = VoiceMock([
      act('t1', [
        ('design.add_floor', {}),
        ('design.rename_room', {'room': 'r1', 'name': '书房'}),
      ]),
      act('t2', [
        (
          'design.add_opening',
          {'room': 'r1', 'side': 'north', 'kind': 'window'}
        )
      ]),
      const VoiceTurn(reply: '加好了。'),
      act('t3', [('editor.undo', {})]),
      const VoiceTurn(reply: '已撤销。'),
    ]);
    final navigator = GlobalKey<NavigatorState>();
    Map<String, String> shown(String kind) => {
          for (final e in VoiceScreens.current!.entities)
            if (e.kind == kind) e.alias: e.title
        };
    try {
      await t.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => VoiceHost(
              navigator: navigator, repos: repos, enabled: true, child: child!),
          home: HouseEditor(entry: ProjectEntry(id, doc), store: store)));
      await t.pumpAndSettle();
      expect(VoiceScreens.current!.screenId, 'editor.plan');
      final openings = shown('opening').length;
      final before = '${shown('floor')} ${shown('room')} ${shown('opening')}';
      expect(shown('floor').keys, ['f1']);

      await type(t, '加一层楼，把这间叫书房，再在北墙加窗');
      await waitFor(t, () => find.text('加好了。').evaluate().isNotEmpty);
      expect(shown('floor').keys, ['f1', 'f2']);
      expect(shown('room').values, contains('书房'));
      expect(shown('opening'), hasLength(openings + 1));
      await showSteps(t, '加好了。');
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
      // Aliases only: no id of the design left the app.
      expect('${repos.said.single.context}', isNot(contains('voice_')));

      await type(t, '撤销');
      await waitFor(t, () => find.text('已撤销。').evaluate().isNotEmpty);
      expect('${shown('floor')} ${shown('room')} ${shown('opening')}', before);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await store.deleteProject(id);
      await LastOpenProject.write(previous);
    }
  });
}
