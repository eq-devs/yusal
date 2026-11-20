// Voice control end to end against real services: yusal-api with its AI
// gateway and a language model behind it, and the speech service. Nothing is
// scripted, so it costs model tokens and needs all of them running.
//
//   flutter test integration_test/voice_live_test.dart -d <device> \
//       --dart-define=YUSAL_API=http://localhost:8080
//
// The backend needs DEV_LOGIN=true, AI_GATEWAY_URL/KEY and QAZSTT_URL/KEY.
// Add --dart-define=E2E_NO_LLM=true or E2E_NO_SPEECH=true to leave out the
// half that is not set up.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/features/editor/house_editor.dart';
import 'package:yusal/main.dart';
import 'package:yusal/data/http/http_backend.dart';
import 'package:yusal/storage/last_open.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/voice/screen.dart';

import 'e2e_support.dart';

const noLlm = bool.fromEnvironment('E2E_NO_LLM');
const noSpeech = bool.fromEnvironment('E2E_NO_SPEECH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<T> io<T>(WidgetTester t, Future<T> Function() f) async =>
      (await t.runAsync(f)) as T;

  Future<HttpBackend> signedIn(WidgetTester t) async {
    requireBackend();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yusal_api.refresh_token');
    final repos = HttpBackend(api, timeout: const Duration(seconds: 90));
    await io(t, () => repos.signInWithProvider('dev', 'Voice Tester'));
    return repos;
  }

  /// Sends [text] through the voice bar and waits for the sentence to end.
  Future<void> say(WidgetTester t, String text) async {
    if (find.byKey(const Key('voice-input')).evaluate().isEmpty) {
      await t.longPress(find.byKey(const Key('voice-button')));
      await t.pumpAndSettle();
    }
    final field = t.widget<TextField>(find.byKey(const Key('voice-input')));
    field.controller!.text = text;
    field.onSubmitted!(text);
    await t.pump();
    // The model takes seconds; the answer's bubble can be closed once
    // the sentence has ended.
    final end = DateTime.now().add(const Duration(seconds: 120));
    bool busy() => find.byKey(const Key('voice-close')).evaluate().isEmpty;
    while (busy()) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('"$text" did not finish');
      }
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  String screen() => VoiceScreens.current?.screenId ?? '';

  testWidgets('speech: text read aloud comes back as the same words',
      (t) async {
    final repos = await signedIn(t);
    const sentence = 'Сәлем, бір қабат қос';
    final wav = await io<Uint8List>(t, () => repos.synthesize(sentence));
    expect(String.fromCharCodes(wav.take(4)), 'RIFF');
    expect(wav.length, greaterThan(8000));
    final heard = await io(t, () => repos.transcribe(wav));
    debugPrint('E2E heard: "$heard"');
    expect(heard.toLowerCase(), contains('қабат'));
  }, skip: noSpeech);

  testWidgets('requests in three languages move around the real app',
      (t) async {
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);
    AppSettings.instance.lang = AppLang.zh;
    final repos = await signedIn(t);
    try {
      await t.pumpWidget(
          ProviderScope(child: HouseApp(repos: repos, store: ProjectStore())));
      await idle(t, 1000);
      expect(screen(), startsWith('shell.'));

      await say(t, '打开我的');
      expect(screen(), 'shell.me');
      await say(t, 'Хабарларды аш');
      expect(screen(), 'shell.messages');
      await say(t, 'Открой мои дома');
      expect(screen(), 'shell.houses');

      // Something this screen cannot do: no action runs, the model answers.
      await say(t, '把客厅改名叫书房');
      expect(screen(), 'shell.houses');
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
    }
  }, skip: noLlm);

  testWidgets('a spoken Kazakh command, through speech and the model',
      (t) async {
    final previous = await LastOpenProject.read();
    await LastOpenProject.write(null);
    AppSettings.instance.lang = AppLang.kk;
    final repos = await signedIn(t);
    try {
      // The speech service says the command and hears it back: the same
      // text a user's recording would give.
      final wav =
          await io<Uint8List>(t, () => repos.synthesize('Хабарларды аш'));
      final heard = await io(t, () => repos.transcribe(wav));
      debugPrint('E2E heard: "$heard"');
      expect(heard.trim(), isNotEmpty);

      await t.pumpWidget(
          ProviderScope(child: HouseApp(repos: repos, store: ProjectStore())));
      await idle(t, 1000);
      await say(t, heard);
      expect(screen(), 'shell.messages');
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await LastOpenProject.write(previous);
      AppSettings.instance.lang = AppLang.zh;
    }
  }, skip: noLlm || noSpeech);

  testWidgets('a design is edited by sentences and undone', (t) async {
    final store = ProjectStore();
    var sequence = 0;
    final previous = await LastOpenProject.read();
    final doc = createHouse(
        name: 'Yusal voice live',
        width: 10000,
        depth: 8000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        newId: () => 'live_${sequence++}');
    final id = await store.createProject(doc);
    AppSettings.instance.lang = AppLang.zh;
    final repos = await signedIn(t);
    Map<String, String> shown(String kind) => {
          for (final e in VoiceScreens.current!.entities)
            if (e.kind == kind) e.alias: e.title
        };
    try {
      await t.pumpWidget(
          ProviderScope(child: HouseApp(repos: repos, store: store)));
      await idle(t, 1000);
      await open(t, HouseEditor(entry: ProjectEntry(id, doc), store: store));
      expect(screen(), 'editor.plan');
      expect(shown('floor').keys, ['f1']);

      await say(t, '加一层楼，再把这个房间改名叫书房');
      expect(shown('floor').keys, ['f1', 'f2']);
      expect(shown('room').values, contains('书房'));

      await say(t, '在书房的北墙加一扇窗');
      expect(shown('opening'), hasLength(1));

      await say(t, '撤销');
      expect(shown('opening'), isEmpty);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await store.deleteProject(id);
      await LastOpenProject.write(previous);
    }
  }, skip: noLlm);
}
