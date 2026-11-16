import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/voice/action.dart';
import 'package:yusal/voice/executor.dart';
import 'package:yusal/voice/registry.dart';
import 'package:yusal/voice/session.dart';
import 'package:yusal/voice/speech.dart';
import 'package:yusal/voice/voice_overlay.dart';

import 'session_test.dart' show ScriptedBackend, act;

/// A backend that also serves voice, as the real one does.
class VoiceMock extends MockBackend implements VoiceBackend {
  /// Signed in, as the orb is only there for someone who is.
  VoiceMock(this.inner, {bool signedIn = true})
      : super(latency: Duration.zero, seed: false) {
    accounts['me'] = Account(
        id: 'me',
        phone: '',
        displayName: 'Me',
        createdAt: DateTime.utc(2026, 11, 1));
    if (signedIn) signInAs('me');
  }
  final ScriptedBackend inner;

  @override
  Future<VoiceTurn> say(
          {required String sessionId,
          required String text,
          required bool spoken,
          required Map<String, Object?> context}) =>
      inner.say(
          sessionId: sessionId, text: text, spoken: spoken, context: context);

  @override
  Future<VoiceTurn> results(
          {required String turnId,
          required List<Map<String, Object?>> results,
          required Map<String, Object?> context}) =>
      inner.results(turnId: turnId, results: results, context: context);
}

/// A backend that also does speech: every recording says [text].
class SpeakingMock extends VoiceMock implements SpeechBackend {
  SpeakingMock(super.inner, this.text);
  final String text;

  @override
  Future<String> transcribe(Uint8List wav) async => text;
}

class FakeAudio implements AudioDevice {
  FakeAudio({this.allowed = true});
  final bool allowed;
  final log = <String>[];

  @override
  Future<bool> startRecording() async {
    log.add('record');
    return allowed;
  }

  @override
  Future<Uint8List?> stopRecording() async => Uint8List(4);

  @override
  Stream<double> get levels => Stream.value(0.8);

  @override
  Future<void> dispose() async => log.add('dispose');
}

void main() {
  final navigator = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester t, VoiceMock repos,
          {bool enabled = true, AudioDevice? audio}) =>
      t.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => VoiceHost(
              navigator: navigator,
              repos: repos,
              enabled: enabled,
              audio: audio,
              child: child!),
          home: const Scaffold(body: Text('page'))));

  testWidgets('typing a request shows what was done and the reply', (t) async {
    final backend = ScriptedBackend([
      act('t1', [
        ('nav.tab', {'tab': 'me'})
      ]),
      const VoiceTurn(
          reply: '这里没有主页面。',
          options: ['回到首页', '算了'],
          brief: {'width_m': 12, 'depth_m': 13.5, 'floors': 2}),
      const VoiceTurn(reply: '好的。'),
    ]);
    await pump(t, VoiceMock(backend));
    await t.pump();
    expect(find.byKey(const Key('voice-bar')), findsNothing);
    expect(find.byKey(const Key('voice-input')), findsNothing);

    // Without speech the orb opens a text field.
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    await t.enterText(find.byKey(const Key('voice-input')), '打开我的');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();

    // The outcome is a bubble; tapping it shows the steps that ran.
    expect(find.text('这里没有主页面。'), findsOneWidget);
    await t.tap(find.text('这里没有主页面。'));
    await t.pumpAndSettle();
    // The step ran and failed (no shell here): it is listed with its name.
    expect(find.text('切换主页面'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    // Nothing changed a design, so there is nothing to undo.
    expect(find.byKey(const Key('voice-undo')), findsNothing);

    // What is known of the house so far goes with the question, and
    // leaves with it.
    expect(t.widget<Text>(find.byKey(const Key('voice-brief'))).data,
        briefLine(const {'width_m': 12, 'depth_m': 13.5, 'floors': 2}));
    expect(briefLine(const {'width_m': 12, 'depth_m': 13.5, 'floors': 2}),
        startsWith('12 × 13.5 '));
    expect(briefLine(const {'notes': '老人房在一楼'}), '');

    // An offered answer is sent as the next sentence.
    await t.tap(find.text('算了'));
    await t.pumpAndSettle();
    expect(backend.said.map((s) => s.text), ['打开我的', '算了']);
    expect(find.text('好的。'), findsOneWidget);
    expect(find.byKey(const Key('voice-brief')), findsNothing);

    // A finished reply stays beside the orb until it is closed.
    await t.pump(const Duration(seconds: 30));
    expect(find.text('好的。'), findsOneWidget);
    final orb = t.getRect(find.byKey(const Key('voice-button')));
    final bubble = t.getRect(find.byKey(const Key('voice-bar')));
    expect(bubble.right, lessThan(orb.left));
    expect(bubble.bottom, greaterThan(orb.top));
    // A short answer is a small bubble, not a bar across the screen.
    expect(bubble.width, lessThan(200));
    await t.tap(find.byKey(const Key('voice-close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('voice-bar')), findsNothing);
  });

  testWidgets('a spoken request is sent as heard and its reply shown as text',
      (t) async {
    final backend = ScriptedBackend([const VoiceTurn(reply: 'Жарайды.')]);
    final repos = SpeakingMock(backend, ' бір қабат қос ');
    final audio = FakeAudio();
    await pump(t, repos, audio: audio);
    await t.pump();

    // One tap listens: the pill says so and the orb shows stop.
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    expect(find.byKey(const Key('voice-pill')), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(backend.said, isEmpty);
    // The next sends what was said.
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pumpAndSettle();

    expect(
        backend.said.map((s) => (s.text, s.spoken)), [('бір қабат қос', true)]);
    expect(find.text('Жарайды.'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    // Nothing is read aloud.
    expect(audio.log, ['record']);

    // A long press types instead, with the microphone a tap away.
    await t.longPress(find.byKey(const Key('voice-button')));
    await t.pump();
    expect(find.byKey(const Key('voice-input')), findsOneWidget);
    expect(find.byKey(const Key('voice-mic')), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    expect(audio.log.last, 'dispose');
  });

  testWidgets('speech says why it cannot go on, and typing has no mic',
      (t) async {
    final backend = ScriptedBackend([]);
    await pump(t, SpeakingMock(backend, ''), audio: FakeAudio());
    await t.pump();
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pumpAndSettle();
    expect(find.text('没听清，请再说一次'), findsOneWidget);
    expect(backend.said, isEmpty);

    await t.pumpWidget(const SizedBox());
    await pump(t, SpeakingMock(backend, 'x'), audio: FakeAudio(allowed: false));
    await t.pump();
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    expect(find.text('请在系统设置里允许使用麦克风'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);

    // No audio device, or a backend without speech: typed only.
    await t.pumpWidget(const SizedBox());
    await pump(t, SpeakingMock(backend, 'x'));
    await t.pump();
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    expect(find.byKey(const Key('voice-input')), findsOneWidget);
    expect(find.byKey(const Key('voice-mic')), findsNothing);
  });

  testWidgets('a failure says what to do', (t) async {
    await pump(t, VoiceMock(ScriptedBackend([Exception('offline')])));
    await t.pump();
    await t.tap(find.byKey(const Key('voice-button')));
    await t.pump();
    await t.enterText(find.byKey(const Key('voice-input')), '你好');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(find.text('现在连不上服务器，请再试一次'), findsOneWidget);
  });

  testWidgets('nothing shows when voice is off, on desktop, or unserved',
      (t) async {
    await pump(t, VoiceMock(ScriptedBackend([])), enabled: false);
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await t.pumpWidget(const SizedBox());
    await pump(t, VoiceMock(ScriptedBackend([])));
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsNothing);
    debugDefaultTargetPlatformOverride = null;

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => VoiceHost(
            navigator: navigator,
            repos: MockBackend(latency: Duration.zero, seed: false),
            enabled: true,
            child: child!),
        home: const Scaffold()));
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsNothing);
  });

  testWidgets('the orb is there only for someone signed in', (t) async {
    final repos = VoiceMock(ScriptedBackend([]), signedIn: false);
    await pump(t, repos);
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsNothing);
    repos.signInAs('me');
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsOneWidget);
    // At rest the orb says what a tap does.
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    repos.signInAs(null);
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsNothing);
  });

  testWidgets('the orb introduces itself until it is first used', (t) async {
    SharedPreferences.setMockInitialValues({});
    final backend = ScriptedBackend([const VoiceTurn(reply: '好的。')]);
    await pump(t, VoiceMock(backend));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('voice-intro')), findsOneWidget);
    expect(find.text('AI 助手'), findsOneWidget);
    // An example on the card is sent as a sentence, and the card is gone
    // for good.
    final example = find.descendant(
        of: find.byKey(const Key('voice-intro')),
        matching: find.byType(ActionChip));
    expect(example, findsWidgets);
    await t.tap(example.first);
    await t.pumpAndSettle();
    expect(backend.said, hasLength(1));
    expect(find.byKey(const Key('voice-intro')), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('voice-intro-seen'),
        isTrue);

    await t.pumpWidget(const SizedBox.shrink());
    await pump(t, VoiceMock(ScriptedBackend([])));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('voice-button')), findsOneWidget);
    expect(find.byKey(const Key('voice-intro')), findsNothing);
  });

  testWidgets('the sign-in page has no orb over its buttons', (t) async {
    await pump(t, VoiceMock(ScriptedBackend([])));
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsOneWidget);

    // What the sign-in page does while it is open.
    VoiceBar.hidden.value++;
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsNothing);

    VoiceBar.hidden.value--;
    await t.pump();
    expect(find.byKey(const Key('voice-button')), findsOneWidget);
  });

  testWidgets('an outbound action asks first and runs only on confirm',
      (t) async {
    var ran = 0;
    final registry = ActionRegistry([
      AppAction(
          id: 'test.send',
          title: const L3('发送消息', 'Хабар жіберу', 'Отправить сообщение'),
          examples: const L3('发送', 'Жібер', 'Отправь'),
          risk: Risk.outbound,
          run: (_, __) async {
            ran++;
            return const ActionResult.ok();
          })
    ]);
    await t.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()));
    final executor = ActionExecutor(registry,
        confirm: (a, args) =>
            confirmAction(navigator.currentContext!, a, args));
    final ctx = ActionContext(
        repos: MockBackend(latency: Duration.zero, seed: false),
        loggedIn: true);

    for (final (button, code, count) in [
      ('取消', ActionCodes.declined, 0),
      ('确认', null, 1)
    ]) {
      final result = executor.run('test.send', {}, ctx, source: Source.voice);
      await t.pumpAndSettle();
      expect(find.text('发送消息'), findsOneWidget);
      expect(ran, count == 1 ? 0 : ran, reason: 'not before the answer');
      await t.tap(find.text(button));
      await t.pumpAndSettle();
      expect((await result).code, code);
      expect(ran, count);
    }
  });
}
