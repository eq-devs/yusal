import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app/settings.dart';
import '../platform/data/repositories.dart';
import 'action.dart';
import 'actions.dart';
import 'executor.dart';
import 'session.dart';
import 'speech.dart';

/// Voice control is built in only with `--dart-define=YUSAL_VOICE=true`,
/// until yusal-api and the AI gateway serve it.
const voiceBuiltIn = bool.fromEnvironment('YUSAL_VOICE');

/// Voice control is for phones and tablets only.
bool get voicePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Asks before an outbound action runs. Never confirms by itself.
Future<bool> confirmAction(
    BuildContext context, AppAction action, Args args) async {
  final lang = AppSettings.instance.lang;
  final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
              key: const Key('voice-confirm'),
              title: Text(action.title.of(lang)),
              content: Text(tr3(
                  '确认后才会执行，取消则什么都不会发出。',
                  'Растасаңыз ғана орындалады.',
                  'Выполнится только после подтверждения.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr3('确认', 'Растау', 'Подтвердить'))),
              ]));
  return yes ?? false;
}

String _failure(String? code) => switch (code) {
      VoiceCodes.network => tr3(
          '现在连不上服务器，请再试一次',
          'Серверге қосылу мүмкін болмады, қайталап көріңіз',
          'Нет связи с сервером, попробуйте ещё раз'),
      'RATE_LIMITED' => tr3('用得太频繁了，请稍后再试', 'Тым жиі, сәл кейінірек көріңіз',
          'Слишком часто, попробуйте чуть позже'),
      'VOICE_BUSY' => tr3(
          '语音服务正忙，请稍后再试',
          'Дауыс қызметі бос емес, сәл кейінірек көріңіз',
          'Голосовой сервис занят, попробуйте чуть позже'),
      VoiceCodes.tooManySteps => tr3(
          '这句话要做的步骤太多，请分开说',
          'Қадам тым көп, бөліп айтыңыз',
          'Слишком много шагов, скажите по частям'),
      _ => tr3('没有成功，请再试一次', 'Сәтсіз болды, қайталап көріңіз',
          'Не получилось, попробуйте ещё раз'),
    };

/// The button that opens voice control and the bar above it that shows
/// what was heard, what is being done and what came of it.
class VoiceBar extends StatefulWidget {
  const VoiceBar({super.key, required this.session, this.speech});
  final VoiceSession session;

  /// Null leaves the bar typed-only.
  final Speech? speech;

  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar> {
  final input = TextEditingController();
  bool open = false;
  bool listening = false, transcribing = false;
  String? speechNote;
  Timer? limit;

  VoiceSession get s => widget.session;

  @override
  void dispose() {
    limit?.cancel();
    input.dispose();
    super.dispose();
  }

  /// First tap starts recording, the second sends what was said. A reply
  /// to a spoken request is also read aloud.
  Future<void> mic() async {
    final speech = widget.speech!;
    if (transcribing || s.busy) return;
    if (!listening) {
      await speech.audio.stopPlaying();
      final ok = await speech.audio.startRecording();
      if (!mounted) return;
      setState(() {
        listening = ok;
        speechNote = ok
            ? null
            : tr3('请在系统设置里允许使用麦克风', 'Баптаулардан микрофонға рұқсат беріңіз',
                'Разрешите доступ к микрофону в настройках');
      });
      if (ok) limit = Timer(Speech.maxSentence, mic);
      return;
    }
    limit?.cancel();
    setState(() {
      listening = false;
      transcribing = true;
    });
    var text = '';
    String? note;
    try {
      text = (await speech.heard()).trim();
      if (text.isEmpty) {
        note = tr3('没听清，请再说一次', 'Естілмеді, қайталап айтыңыз',
            'Не расслышал, повторите');
      }
    } catch (e) {
      note = _failure(e is ApiFailure ? e.code : VoiceCodes.network);
    }
    if (!mounted) return;
    setState(() {
      transcribing = false;
      speechNote = note;
    });
    if (text.isEmpty) return;
    await s.say(text, spoken: true);
    if (s.phase != VoicePhase.done || s.reply.isEmpty) return;
    try {
      await speech.speak(s.reply);
    } catch (_) {
      // The reply is on screen either way.
    }
  }

  void send([String? text]) {
    final t = (text ?? input.text).trim();
    if (t.isEmpty || s.busy) return;
    input.clear();
    s.say(t, spoken: false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final theme = Theme.of(context);
        final lang = AppSettings.instance.lang;
        final quiet = theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (open)
                Material(
                    key: const Key('voice-bar'),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.surface,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (s.heard.isNotEmpty)
                                Text(s.heard, style: quiet),
                              for (final step in s.steps)
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(
                                      step.result.ok
                                          ? Icons.check_circle
                                          : Icons.error_outline,
                                      size: 16,
                                      color: step.result.ok
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error),
                                  const SizedBox(width: 8),
                                  Flexible(
                                      child: Text(
                                          step.action?.title.of(lang) ?? '?')),
                                ]),
                              if (speechNote != null)
                                Text(speechNote!,
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
                              if (s.busy || transcribing)
                                const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: LinearProgressIndicator()),
                              if (s.phase == VoicePhase.done &&
                                  s.reply.isNotEmpty)
                                Text(s.reply, style: theme.textTheme.bodyLarge),
                              if (s.phase == VoicePhase.failed)
                                Text(_failure(s.error),
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
                              if (s.options.isNotEmpty)
                                Wrap(spacing: 8, children: [
                                  for (final o in s.options)
                                    ActionChip(
                                        label: Text(o),
                                        onPressed: () => send(o)),
                                ]),
                              Row(children: [
                                Expanded(
                                    child: TextField(
                                        key: const Key('voice-input'),
                                        controller: input,
                                        enabled: !s.busy,
                                        textInputAction: TextInputAction.send,
                                        onSubmitted: send,
                                        decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: tr3(
                                                '想做什么？',
                                                'Не істейміз?',
                                                'Что сделать?')))),
                                if (widget.speech != null)
                                  IconButton(
                                      key: const Key('voice-mic'),
                                      tooltip: listening
                                          ? tr3('说完了', 'Айтып болдым', 'Готово')
                                          : tr3('说话（哈萨克语）', 'Сөйлеу',
                                              'Говорить (по-казахски)'),
                                      color: listening
                                          ? theme.colorScheme.error
                                          : null,
                                      icon: Icon(listening
                                          ? Icons.stop_circle_outlined
                                          : Icons.mic),
                                      onPressed:
                                          s.busy || transcribing ? null : mic),
                                s.phase == VoicePhase.acting
                                    ? IconButton(
                                        tooltip: tr3('停止', 'Тоқтату', 'Стоп'),
                                        icon: const Icon(Icons.stop_circle),
                                        onPressed: s.stop)
                                    : IconButton(
                                        tooltip:
                                            tr3('发送', 'Жіберу', 'Отправить'),
                                        icon: const Icon(Icons.send),
                                        onPressed: s.busy ? null : send),
                              ]),
                            ]))),
              const SizedBox(height: 8),
              FloatingActionButton(
                  key: const Key('voice-button'),
                  heroTag: null,
                  tooltip:
                      tr3('语音操作', 'Дауыспен басқару', 'Голосовое управление'),
                  onPressed: () => setState(() => open = !open),
                  child: Icon(open ? Icons.close : Icons.mic_none)),
            ]);
      });
}

/// Puts the voice bar over every page. Wraps the app's content in
/// `MaterialApp.builder`; shows nothing unless voice is built in, the
/// device is a phone or tablet and the backend serves voice.
class VoiceHost extends StatefulWidget {
  const VoiceHost(
      {super.key,
      required this.navigator,
      required this.repos,
      required this.child,
      this.audio,
      this.enabled = voiceBuiltIn});
  final GlobalKey<NavigatorState> navigator;
  final PlatformRepositories repos;
  final Widget child;

  /// The microphone and speaker; without it, or with a backend that does
  /// no speech, the bar is typed-only. Disposed with this widget.
  final AudioDevice? audio;
  final bool enabled;

  @override
  State<VoiceHost> createState() => _VoiceHostState();
}

class _VoiceHostState extends State<VoiceHost> {
  VoiceSession? session;
  OverlayEntry? entry;

  @override
  void initState() {
    super.initState();
    final repos = widget.repos;
    final Object backend = repos;
    final Object speaker = repos;
    final audio = widget.audio;
    if (!widget.enabled || !voicePlatform || backend is! VoiceBackend) return;
    final s = session = VoiceSession(
        backend: backend,
        executor: ActionExecutor(appActions,
            confirm: (action, args) =>
                confirmAction(widget.navigator.currentContext!, action, args)),
        repos: repos,
        loggedIn: () => repos.currentAccount != null,
        sessionId: const Uuid().v4());
    // In the navigator's overlay, not a route: pages stay "current" for
    // voice while the bar is open, and its text field has an overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = widget.navigator.currentState?.overlay;
      if (!mounted || overlay == null) return;
      entry = OverlayEntry(
          builder: (context) => Positioned(
              right: 16,
              left: 16,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 96,
              child: Align(
                  alignment: Alignment.bottomRight,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: VoiceBar(
                          session: s,
                          speech: audio != null && speaker is SpeechBackend
                              ? Speech(speaker, audio)
                              : null)))));
      overlay.insert(entry!);
    });
  }

  @override
  void dispose() {
    entry?.remove();
    session?.dispose();
    widget.audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
