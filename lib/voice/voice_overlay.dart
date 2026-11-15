import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app/settings.dart';
import '../platform/data/repositories.dart';
import 'action.dart';
import 'actions.dart';
import 'executor.dart';
import 'actions_design.dart';
import 'screen.dart';
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
      ApiCodes.notSignedIn =>
        tr3('请先登录，再用语音', 'Алдымен жүйеге кіріңіз', 'Сначала войдите в аккаунт'),
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

/// Actions shown as "you can say" suggestions, most useful first.
const _suggestionOrder = [
  'design.create_house',
  'design.add_opening',
  'design.add_furniture',
  'design.add_room',
  'design.add_floor',
  'houses.create',
  'houses.open',
  'form.fill',
  'nav.tab',
];

/// Voice control in the manner of a phone assistant: a small orb in the
/// corner, the screen's edges glowing while it listens and works, what was
/// heard in a pill at the bottom and the outcome in a banner at the top
/// that gets out of the way. The page underneath stays visible.
///
/// Tapping the orb starts listening and tapping it again sends; without
/// speech, or on a long press, it opens a text field instead.
class VoiceBar extends StatefulWidget {
  const VoiceBar({super.key, required this.session, this.speech});
  final VoiceSession session;

  /// Null leaves the bar typed-only.
  final Speech? speech;

  /// How long a finished reply stays before the banner hides.
  static const showFor = Duration(seconds: 5);

  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar>
    with SingleTickerProviderStateMixin {
  final input = TextEditingController();
  final focus = FocusNode();
  bool typing = false, listening = false, transcribing = false;
  bool bannerShown = false, expanded = false;
  String? speechNote;
  Timer? limit, hide;
  late final glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  VoiceSession get s => widget.session;
  bool get active => listening || transcribing || s.busy;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
    // The suggestions show only while the field is empty.
    input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    limit?.cancel();
    hide?.cancel();
    glow.dispose();
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final finished = s.phase == VoicePhase.done || s.phase == VoicePhase.failed;
    if (s.busy || finished) bannerShown = true;
    hide?.cancel();
    // A question with answers to pick, or an open banner, stays.
    if (finished && s.options.isEmpty && !expanded) {
      hide = Timer(VoiceBar.showFor, () {
        if (mounted) setState(() => bannerShown = false);
      });
    }
    _animate();
    setState(() {});
  }

  void _animate() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (active && !still) {
      if (!glow.isAnimating) glow.repeat(reverse: true);
    } else {
      glow.stop();
    }
  }

  /// The orb: listen, or send what was said.
  Future<void> orb() async {
    if (widget.speech == null) return toggleTyping();
    if (transcribing || s.busy) return;
    if (!listening) return startListening();
    await stopListening();
  }

  void toggleTyping() {
    setState(() {
      typing = !typing;
      speechNote = null;
    });
    if (typing) focus.requestFocus();
  }

  Future<void> startListening() async {
    final speech = widget.speech!;
    final ok = await speech.audio.startRecording();
    if (!mounted) return;
    setState(() {
      typing = false;
      listening = ok;
      bannerShown = false;
      speechNote = ok
          ? null
          : tr3('请在系统设置里允许使用麦克风', 'Баптаулардан микрофонға рұқсат беріңіз',
              'Разрешите доступ к микрофону в настройках');
    });
    _animate();
    if (ok) limit = Timer(Speech.maxSentence, stopListening);
  }

  Future<void> stopListening() async {
    if (!listening) return;
    limit?.cancel();
    setState(() {
      listening = false;
      transcribing = true;
    });
    var text = '';
    String? note;
    try {
      text = (await widget.speech!.heard()).trim();
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
    _animate();
    if (text.isEmpty) return;
    await s.say(text, spoken: true);
  }

  void send([String? text]) {
    final t = (text ?? input.text).trim();
    if (t.isEmpty || s.busy) return;
    input.clear();
    expanded = false;
    s.say(t, spoken: false);
  }

  /// What this page offers, as things to say.
  List<String> suggestions() {
    final ctx = VoiceScreens.context(s.repos, loggedIn: s.loggedIn());
    final offered = {for (final a in s.executor.registry.offered(ctx)) a.id: a};
    final lang = AppSettings.instance.lang;
    return [
      for (final id in _suggestionOrder)
        if (offered[id] != null) offered[id]!.examples.of(lang)
    ].take(3).toList();
  }

  /// The sentence changed the open design, so one undo takes it back.
  bool get canUndo {
    final Object? screen = VoiceScreens.current;
    return screen is DesignHost &&
        s.phase == VoicePhase.done &&
        s.steps.any((step) =>
            step.result.ok && (step.action?.id.startsWith('design.') ?? false));
  }

  void undo() {
    final Object? screen = VoiceScreens.current;
    if (screen is DesignHost) screen.undoDesign();
    setState(() => bannerShown = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lang = AppSettings.instance.lang;
    final insets = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final quiet =
        theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final failed = s.phase == VoicePhase.failed;

    Widget card(
            {required Widget child, Key? key, EdgeInsets? padding}) =>
        Material(
            key: key,
            elevation: 6,
            color: colors.surface,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
                padding: padding ??
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: child));

    // Top: what came of the sentence.
    final banner = bannerShown &&
            (s.busy || s.phase == VoicePhase.done || failed)
        ? card(
            key: const Key('voice-bar'),
            child: InkWell(
                onTap: () => setState(() {
                      expanded = !expanded;
                      if (expanded) hide?.cancel();
                    }),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _Orb(size: 26, glow: glow, busy: s.busy),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                s.busy
                                    ? (s.heard.isEmpty
                                        ? tr3(
                                            '正在处理…', 'Орындалуда…', 'Выполняю…')
                                        : s.heard)
                                    : failed
                                        ? _failure(s.error)
                                        : s.reply.isNotEmpty
                                            ? s.reply
                                            : tr3('完成了', 'Дайын', 'Готово'),
                                maxLines: expanded ? null : 2,
                                overflow:
                                    expanded ? null : TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: failed ? colors.error : null))),
                        if (canUndo)
                          TextButton(
                              key: const Key('voice-undo'),
                              onPressed: undo,
                              child: Text(tr3('撤销', 'Болдырмау', 'Отменить'))),
                        if (s.phase == VoicePhase.acting)
                          IconButton(
                              tooltip: tr3('停止', 'Тоқтату', 'Стоп'),
                              icon: const Icon(Icons.stop_circle),
                              onPressed: s.stop),
                      ]),
                      if (s.steps.isNotEmpty && (expanded || s.busy))
                        Padding(
                            padding: const EdgeInsets.only(top: 6, left: 36),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final step in s.steps)
                                    Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              step.result.ok
                                                  ? Icons.check_circle
                                                  : Icons.error_outline,
                                              size: 14,
                                              color: step.result.ok
                                                  ? colors.primary
                                                  : colors.error),
                                          const SizedBox(width: 6),
                                          Flexible(
                                              child: Text(
                                                  step.action?.title.of(lang) ??
                                                      '?',
                                                  style: quiet)),
                                        ]),
                                ])),
                      if (s.options.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 6, left: 36),
                            child: Wrap(spacing: 8, children: [
                              for (final o in s.options)
                                ActionChip(
                                    label: Text(o), onPressed: () => send(o)),
                            ])),
                    ])))
        : null;

    // Bottom: what is being heard, or the text field.
    final hint = listening
        ? tr3('正在听…说完点圆球', 'Тыңдап тұрмын… біткенде шарды басыңыз',
            'Слушаю… нажмите на шар, когда закончите')
        : transcribing
            ? tr3('正在识别…', 'Танып жатырмын…', 'Распознаю…')
            : speechNote;
    final pill = typing
        ? card(
            padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      key: const Key('voice-input'),
                      controller: input,
                      focusNode: focus,
                      enabled: !s.busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: send,
                      // Plain text in the pill, whatever the app's
                      // field style.
                      decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          hintText:
                              tr3('想做什么？', 'Не істейміз?', 'Что сделать?')))),
              if (widget.speech != null)
                IconButton(
                    key: const Key('voice-mic'),
                    tooltip:
                        tr3('说话（哈萨克语）', 'Сөйлеу', 'Говорить (по-казахски)'),
                    icon: const Icon(Icons.mic),
                    onPressed: s.busy ? null : startListening),
              IconButton(
                  tooltip: tr3('发送', 'Жіберу', 'Отправить'),
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: s.busy ? null : send),
            ]))
        : hint != null
            ? GestureDetector(
                key: const Key('voice-pill'),
                // Tapping the pill while listening switches to typing.
                onTap: listening
                    ? () async {
                        limit?.cancel();
                        await widget.speech!.audio.stopRecording();
                        setState(() => listening = false);
                        _animate();
                        toggleTyping();
                      }
                    : null,
                child: card(
                    child: Text(hint,
                        style: speechNote != null && !listening && !transcribing
                            ? TextStyle(color: colors.error)
                            : null)))
            : null;
    final tips = typing && !s.busy && input.text.isEmpty && !bannerShown
        ? suggestions()
        : const <String>[];

    // Transparent: taps between the parts reach the page.
    return Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          // The screen's edges glow while voice listens or works.
          if (active)
            Positioned.fill(
                child: IgnorePointer(
                    child: AnimatedBuilder(
                        animation: glow,
                        builder: (context, _) => CustomPaint(
                            key: const Key('voice-glow'),
                            painter: _EdgeGlow(
                                listening
                                    ? 0.55 + 0.45 * glow.value
                                    : 0.35 + 0.25 * glow.value,
                                colors))))),
          if (banner != null)
            Positioned(
                top: insets.top + 8,
                left: 12,
                right: 12,
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: banner))),
          Positioned(
              left: 16,
              right: 16,
              bottom: keyboard + 96,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      if (tips.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  for (final tip in tips)
                                    ActionChip(
                                        avatar: const Icon(
                                            Icons.lightbulb_outline,
                                            size: 16),
                                        label: Text(tip,
                                            style: theme.textTheme.bodyMedium),
                                        onPressed: () => send(tip)),
                                ])),
                      if (pill != null)
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: pill),
                    ])),
                const SizedBox(width: 10),
                Semantics(
                    button: true,
                    label: listening
                        ? tr3('说完了', 'Айтып болдым', 'Готово')
                        : tr3(
                            '语音操作', 'Дауыспен басқару', 'Голосовое управление'),
                    child: GestureDetector(
                        key: const Key('voice-button'),
                        onTap: orb,
                        onLongPress: toggleTyping,
                        child: _Orb(
                            size: 52,
                            glow: glow,
                            busy: active,
                            icon: listening
                                ? Icons.stop_rounded
                                : typing && widget.speech == null
                                    ? Icons.close
                                    : null))),
              ])),
        ]));
  }
}

/// The assistant's orb: a turning colour wheel, brighter while busy.
class _Orb extends StatelessWidget {
  const _Orb(
      {required this.size, required this.glow, required this.busy, this.icon});
  final double size;
  final Animation<double> glow;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
        animation: glow,
        builder: (context, _) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                    transform: GradientRotation(glow.value * 3.1416),
                    colors: [
                      colors.primary,
                      colors.tertiary,
                      colors.secondary,
                      colors.primary
                    ]),
                boxShadow: [
                  BoxShadow(
                      color:
                          colors.primary.withValues(alpha: busy ? 0.5 : 0.25),
                      blurRadius: busy ? 18 : 8)
                ]),
            child: icon == null
                ? null
                : Icon(icon, color: colors.onPrimary, size: size * 0.5)));
  }
}

/// A soft coloured glow along the screen's edges.
class _EdgeGlow extends CustomPainter {
  _EdgeGlow(this.strength, this.colors);
  final double strength;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = SweepGradient(colors: [
      colors.primary,
      colors.tertiary,
      colors.secondary,
      colors.primary
    ]).createShader(rect);
    for (final (width, blur, alpha) in [(18.0, 18.0, 0.55), (5.0, 3.0, 0.9)]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              rect.deflate(width / 2), const Radius.circular(28)),
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = Colors.white.withValues(alpha: alpha * strength)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
    }
  }

  @override
  bool shouldRepaint(_EdgeGlow old) => old.strength != strength;
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

  /// The microphone; without it, or with a backend that does
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
          builder: (context) => Positioned.fill(
              child: VoiceBar(
                  session: s,
                  speech: audio != null && speaker is SpeechBackend
                      ? Speech(speaker, audio)
                      : null)));
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
