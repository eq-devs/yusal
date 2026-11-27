import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yusal/features/shared/ui/voice_slot.dart';
export 'package:yusal/features/shared/ui/voice_slot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/features/voice/actions/actions.dart';
import 'package:yusal/features/voice/state/executor.dart';
import 'package:yusal/features/voice/widgets/read_aloud_button.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/features/voice/state/session.dart';
import 'package:yusal/features/voice/repository/speech.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Voice control is built into every build.
const voiceBuiltIn = true;

/// Voice control is for phones and tablets only.
bool get voicePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Asks before an outbound action runs. Never confirms by itself.
Future<bool> confirmAction(
    BuildContext context, AppAction action, Args args) async {
  final lang = appLang;
  final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
              key: const Key('voice-confirm'),
              title: Text(action.title.of(lang)),
              content: Text(tr3(
                  '确认后才会执行，取消则什么都不会发出。',
                  'Растасаңыз ғана орындалады.',
                  'Выполнится только после подтверждения.',
                  'Runs only after you confirm.', ky: 'Сиз ырастагандан кийин гана аткарылат.', uz: 'Faqat siz tasdiqlagandan keyin bajariladi.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr3('确认', 'Растау', 'Подтвердить', 'Confirm', ky: 'Ырастоо', uz: 'Tasdiqlash'))),
              ]));
  return yes ?? false;
}

String _failure(String? code) => switch (code) {
      VoiceCodes.network => tr3(
          '现在连不上服务器，请再试一次',
          'Серверге қосылу мүмкін болмады, қайталап көріңіз',
          'Нет связи с сервером, попробуйте ещё раз',
          "Can't reach the server; try again", ky: 'Серверге туташуу мүмкүн эмес; кайра аракет кылыңыз', uz: 'Serverga ulanib boʻlmadi; qayta urining'),
      ApiCodes.notSignedIn =>
        tr3('请先登录，再用语音', 'Алдымен жүйеге кіріңіз', 'Сначала войдите в аккаунт', 'Sign in first', ky: 'Адегенде кириңиз', uz: 'Avval kiring'),
      ApiCodes.rateLimited => tr3('用得太频繁了，请稍后再试', 'Тым жиі, сәл кейінірек көріңіз',
          'Слишком часто, попробуйте чуть позже',
          'Too many tries; try again a bit later', ky: 'Аракеттер өтө көп; бир аздан кийин кайталаңыз', uz: 'Urinishlar juda koʻp; birozdan keyin qayta urining'),
      ApiCodes.voiceBusy => tr3(
          '语音服务正忙，请稍后再试',
          'Дауыс қызметі бос емес, сәл кейінірек көріңіз',
          'Голосовой сервис занят, попробуйте чуть позже',
          'The voice service is busy; try again a bit later', ky: 'Үн кызматы бош эмес; бир аздан кийин кайталаңыз', uz: 'Ovoz xizmati band; birozdan keyin qayta urining'),
      VoiceCodes.tooManySteps => tr3(
          '这句话要做的步骤太多，请分开说',
          'Қадам тым көп, бөліп айтыңыз',
          'Слишком много шагов, скажите по частям',
          'Too many steps; say it in parts', ky: 'Кадамдар өтө көп; бөлүп айтыңыз', uz: 'Qadamlar juda koʻp; qismlarga boʻlib ayting'),
      _ => tr3('没有成功，请再试一次', 'Сәтсіз болды, қайталап көріңіз',
          'Не получилось, попробуйте ещё раз',
          "That didn't work; try again", ky: 'Болбой калды; кайра аракет кылыңыз', uz: 'Boʻlmadi; qayta urining'),
    };

/// Actions shown as "you can say" suggestions, most useful first.
const _suggestionOrder = [
  'design.create_house',
  'design.resize_room',
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
/// corner that turns and breathes while it listens and works, what was
/// heard and the outcome in a bubble beside it. The answer stays until it
/// is closed or the next sentence starts. The page underneath stays
/// visible.
///
/// Tapping the orb starts listening and tapping it again sends; without
/// speech, or on a long press, it opens a text field instead.
class VoiceBar extends StatefulWidget {
  const VoiceBar({super.key, required this.session, this.speech, this.reader});
  final VoiceSession session;

  /// Reads replies aloud; null leaves the speaker button out.
  final ReadAloud? reader;

  /// Null leaves the bar typed-only.
  final Speech? speech;

  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar> with TickerProviderStateMixin {
  final input = TextEditingController();
  final focus = FocusNode();
  bool typing = false;

  /// What the microphone is doing: one thing at a time.
  _Mic mic = _Mic.off;
  bool get listening => mic == _Mic.listening;
  bool get transcribing => mic == _Mic.transcribing;
  bool bannerShown = false;
  bool expanded = false;

  /// The card that says what the orb is, until the orb is first used.
  bool intro = false;
  static const _introSeen = 'voice-intro-seen';
  String? speechNote;
  Timer? limit;
  // The place the page on top keeps for the orb, if it keeps one.
  Rect? slot;
  // The page on top is one the assistant can do something on.
  bool here = false;
  // The page on top is a tab, not a page opened over one.
  bool onTab = true;
  // One turn of the orb, and how loud the voice is (0 to 1).
  late final glow = AnimationController(vsync: this, duration: _calm);
  late final level = AnimationController(vsync: this);
  StreamSubscription<double>? levels;
  static const _calm = Duration(milliseconds: 7000);
  static const _quick = Duration(milliseconds: 2600);

  VoiceSession get s => widget.session;
  bool get active => listening || transcribing || s.busy;

  _Mood get mood => listening
      ? _Mood.listening
      : transcribing || s.busy
          ? _Mood.thinking
          : !bannerShown
              ? _Mood.idle
              : s.phase == VoicePhase.failed
                  ? _Mood.failed
                  : s.phase == VoicePhase.done
                      ? _Mood.done
                      : _Mood.idle;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
    VoiceSlot.hidden.addListener(_hiddenChanged);
    // Signing in and out shows and hides the orb.
    s.repos.session.changes.addListener(_hiddenChanged);
    // The suggestions show only while the field is empty.
    input.addListener(() => setState(() {}));
    here = VoiceScreens.current?.showsAssistant ?? false;
    slot = VoiceSlot.rect;
    WidgetsBinding.instance.addPostFrameCallback(_followSlot);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && prefs.getBool(_introSeen) != true) {
        setState(() => intro = true);
      }
    }).catchError((_) {/* No storage: no introduction. */});
  }

  /// Keeps the orb on the page's slot as the page lays out and changes.
  void _followSlot(Duration _) {
    if (!mounted) return;
    final now = VoiceSlot.rect;
    final onPage = VoiceScreens.current?.showsAssistant ?? false;
    // The bar lives in the navigator's overlay, so this is the app's.
    final tab = !(Navigator.maybeOf(context)?.canPop() ?? false);
    if (now != slot || onPage != here || tab != onTab) {
      setState(() {
        slot = now;
        here = onPage;
        onTab = tab;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback(_followSlot);
  }

  void closeIntro() {
    if (!intro) return;
    setState(() => intro = false);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_introSeen, true))
        .catchError((_) => false);
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    VoiceSlot.hidden.removeListener(_hiddenChanged);
    s.repos.session.changes.removeListener(_hiddenChanged);
    limit?.cancel();
    levels?.cancel();
    glow.dispose();
    level.dispose();
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void _hiddenChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    final finished = s.phase == VoicePhase.done || s.phase == VoicePhase.failed;
    if (s.busy || finished) bannerShown = true;
    _animate();
    setState(() {});
  }

  void _animate() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (active && !still) {
      // Slow while listening, quicker while working.
      final turn = listening ? _calm : _quick;
      if (!glow.isAnimating || glow.duration != turn) {
        glow.duration = turn;
        glow.repeat();
      }
    } else {
      glow.stop();
    }
  }

  /// The orb swells with the voice: quickly up, slowly down, eased between
  /// the microphone's readings so it moves on every frame.
  void _follow(bool on) {
    levels?.cancel();
    levels = null;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!on || still) {
      level.animateTo(0, duration: const Duration(milliseconds: 260));
      return;
    }
    levels = widget.speech!.audio.levels.listen((v) {
      level.animateTo(v,
          duration: Duration(milliseconds: v > level.value ? 90 : 340),
          curve: Curves.easeOut);
    }, onError: (_) {});
  }

  /// The orb: listen, or send what was said. Speaking while a sentence
  /// is running interrupts it.
  Future<void> orb() async {
    closeIntro();
    if (widget.speech == null) return toggleTyping();
    if (transcribing) return;
    if (!listening) return startListening();
    await stopListening();
  }

  void toggleTyping() {
    closeIntro();
    setState(() {
      typing = !typing;
      speechNote = null;
    });
    if (typing) focus.requestFocus();
  }

  Future<void> startListening() async {
    // The microphone is already in use for the last sentence.
    if (mic != _Mic.off) return;
    // The microphone must not hear the reply being read.
    if (widget.reader?.speaking.value ?? false) await widget.reader!.stop();
    final speech = widget.speech!;
    final ok = await speech.audio.startRecording();
    if (!mounted) return;
    setState(() {
      typing = false;
      mic = ok ? _Mic.listening : _Mic.off;
      bannerShown = false;
      speechNote = ok
          ? null
          : tr3('请在系统设置里允许使用麦克风', 'Баптаулардан микрофонға рұқсат беріңіз',
              'Разрешите доступ к микрофону в настройках',
              'Allow microphone access in settings', ky: 'Жөндөөлөрдөн микрофонго уруксат бериңиз', uz: 'Sozlamalarda mikrofonga ruxsat bering');
    });
    _animate();
    if (ok) {
      _follow(true);
      limit = Timer(Speech.maxSentence, stopListening);
    }
  }

  Future<void> stopListening() async {
    if (!listening) return;
    limit?.cancel();
    _follow(false);
    setState(() {
      mic = _Mic.transcribing;
    });
    var text = '';
    String? note;
    try {
      text = (await widget.speech!.heard()).trim();
      if (text.isEmpty) {
        note = tr3('没听清，请再说一次', 'Естілмеді, қайталап айтыңыз',
            'Не расслышал, повторите',
            "Didn't catch that; say it again", ky: 'Түшүнгөн жокмун; кайра айтыңыз', uz: 'Tushunmadim; qayta ayting');
      }
    } catch (e) {
      note = _failure(e is ApiFailure ? e.code : VoiceCodes.network);
    }
    if (!mounted) return;
    setState(() {
      mic = _Mic.off;
      speechNote = note;
    });
    _animate();
    if (text.isEmpty) return;
    await s.say(text, spoken: true);
  }

  void send([String? text]) {
    final t = (text ?? input.text).trim();
    if (t.isEmpty) return;
    closeIntro();
    input.clear();
    expanded = false;
    // The answer takes the field's place beside the orb.
    typing = false;
    s.say(t, spoken: false);
  }

  /// What this page offers, as things to say.
  List<String> suggestions() {
    final ctx = VoiceScreens.context(s.repos, loggedIn: s.loggedIn());
    final offered = {for (final a in s.executor.registry.offered(ctx)) a.id: a};
    final lang = appLang;
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
    // Out of the way on the sign-in page, and for someone not signed in:
    // the assistant acts on an account's own designs.
    if ((VoiceSlot.hidden.value > 0 || !s.loggedIn()) && !active) {
      return const SizedBox.shrink();
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // At rest it shows only where it can do something (not over a
    // settings page, a picture, a dialog), and never over someone
    // typing into the page. A sentence in hand or an answer stays.
    final answer = bannerShown &&
        (s.phase == VoicePhase.done || s.phase == VoicePhase.failed);
    if ((!here || keyboard > 0) && !active && !typing && !answer) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lang = appLang;
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

    // What came of the sentence, beside the orb. It stays until closed
    // or the next sentence starts.
    final banner = bannerShown &&
            (s.busy || s.phase == VoicePhase.done || failed)
        ? card(
            key: const Key('voice-bar'),
            child: InkWell(
                onTap: () => setState(() => expanded = !expanded),
                // A long answer scrolls inside its bubble.
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Only as wide as its text: a short answer is a
                      // small bubble.
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                            child: Text(
                                s.busy
                                    ? (s.heard.isEmpty
                                        ? tr3(
                                            '正在处理…', 'Орындалуда…', 'Выполняю…', 'Working…', ky: 'Иштеп жатат…', uz: 'Bajarilmoqda…')
                                        : s.heard)
                                    : failed
                                        ? _failure(s.error)
                                        : s.reply.isNotEmpty
                                            ? s.reply
                                            : tr3('完成了', 'Дайын', 'Готово', 'Done', ky: 'Даяр', uz: 'Tayyor'),
                                maxLines: expanded ? null : 4,
                                overflow:
                                    expanded ? null : TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: failed ? colors.error : null))),
                        // Gone with the reply: closing the bubble or a new
                        // sentence stops the voice.
                        if (widget.reader case final reader?
                            when !s.busy &&
                                !failed &&
                                ReadAloud.canRead(s.reply))
                          ReadAloudButton(reader: reader, text: s.reply),
                        if (canUndo)
                          TextButton(
                              key: const Key('voice-undo'),
                              onPressed: undo,
                              child: Text(tr3('撤销', 'Болдырмау', 'Отменить', 'Undo', ky: 'Артка кайтаруу', uz: 'Bekor qilish'))),
                        if (s.phase == VoicePhase.acting)
                          IconButton(
                              tooltip: tr3('停止', 'Тоқтату', 'Стоп', 'Stop', ky: 'Токтотуу', uz: 'Toʻxtatish'),
                              icon: const Icon(Icons.stop_circle),
                              onPressed: s.stop),
                        if (!s.busy)
                          IconButton(
                              key: const Key('voice-close'),
                              visualDensity: VisualDensity.compact,
                              tooltip: tr3('关闭', 'Жабу', 'Закрыть', 'Close', ky: 'Жабуу', uz: 'Yopish'),
                              icon: const Icon(YIcons.close, size: 18),
                              onPressed: () =>
                                  setState(() => bannerShown = false)),
                      ]),
                      if (s.steps.isNotEmpty && (expanded || s.busy))
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final step in s.steps)
                                    Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              step.result.ok
                                                  ? YIcons.checkCircle
                                                  : YIcons.alert,
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
                      if (briefLine(s.brief).isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(briefLine(s.brief),
                                key: const Key('voice-brief'), style: quiet)),
                      if (s.options.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(spacing: 8, children: [
                              for (final o in s.options)
                                ActionChip(
                                    label: Text(o,
                                        style: theme.textTheme.bodyMedium),
                                    onPressed: () => send(o)),
                            ])),
                    ]))))
        : null;

    // Bottom: what is being heard, or the text field.
    final hint = listening
        ? tr3('正在听…说完点圆球', 'Тыңдап тұрмын… біткенде шарды басыңыз',
            'Слушаю… нажмите на шар, когда закончите',
            "Listening… tap the orb when you're done", ky: 'Угуп жатам… бүткөндө шарды басыңыз', uz: 'Tinglayapman… tugatgach sharni bosing')
        : transcribing
            ? tr3('正在识别…', 'Танып жатырмын…', 'Распознаю…', 'Recognising…', ky: 'Таанылууда…', uz: 'Aniqlanmoqda…')
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
                              tr3('想做什么？', 'Не істейміз?', 'Что сделать?', 'What should I do?', ky: 'Эмне кылайын?', uz: 'Nima qilay?')))),
              if (widget.speech != null)
                IconButton(
                    key: const Key('voice-mic'),
                    tooltip:
                        tr3('说话（哈萨克语）', 'Сөйлеу', 'Говорить (по-казахски)', 'Speak (in Kazakh)', ky: 'Сүйлөңүз (казакча)', uz: 'Gapiring (qozoqcha)'),
                    icon: const YusalIcon(YIcon.mic),
                    onPressed: s.busy ? null : startListening),
              IconButton(
                  tooltip: tr3('发送', 'Жіберу', 'Отправить', 'Send', ky: 'Жөнөтүү', uz: 'Yuborish'),
                  icon: const Icon(YIcons.arrowUp),
                  onPressed: s.busy ? null : send),
            ]))
        : hint != null
            ? GestureDetector(
                key: const Key('voice-pill'),
                // Tapping the pill while listening switches to typing.
                onTap: listening
                    ? () async {
                        limit?.cancel();
                        _follow(false);
                        await widget.speech!.audio.stopRecording();
                        setState(() => mic = _Mic.off);
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
    // What the orb is and what to say to it, until it is first used.
    // Only on the tabs: over a page that keeps a slot, or a page opened
    // over a tab (a cooperation, a demand), it would cover the work.
    final welcome = intro &&
            onTab &&
            this.slot == null &&
            !active &&
            !typing &&
            !bannerShown &&
            pill == null
        ? card(
            key: const Key('voice-intro'),
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 10),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(YIcons.ai, size: 18, color: colors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(tr3('AI 助手', 'AI көмекші', 'AI-помощник', 'AI assistant', ky: 'AI жардамчы', uz: 'AI yordamchi'),
                            style: theme.textTheme.titleSmall)),
                    IconButton(
                        key: const Key('voice-intro-close'),
                        visualDensity: VisualDensity.compact,
                        tooltip: tr3('知道了', 'Түсінікті', 'Понятно', 'Got it', ky: 'Түшүндүм', uz: 'Tushundim'),
                        icon: const Icon(YIcons.close, size: 18),
                        onPressed: closeIntro),
                  ]),
                  Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                          widget.speech != null
                              ? tr3(
                                  '点右边的圆球，直接说你想做什么。比如：',
                                  'Оң жақтағы шарды басып, не керегін айтыңыз. Мысалы:',
                                  'Нажмите на шар справа и скажите, что нужно. Например:',
                                  'Tap the orb on the right and say what you need. For example:', ky: 'Оң жактагы шарды басып, эмне керек экенин айтыңыз. Мисалы:', uz: 'Oʻngdagi sharni bosing va nima kerakligini ayting. Masalan:')
                              : tr3(
                                  '点右边的圆球，写下你想做什么。比如：',
                                  'Оң жақтағы шарды басып, не керегін жазыңыз. Мысалы:',
                                  'Нажмите на шар справа и напишите, что нужно. Например:',
                                  'Tap the orb on the right and type what you need. For example:', ky: 'Оң жактагы шарды басып, эмне керек экенин жазыңыз. Мисалы:', uz: 'Oʻngdagi sharni bosing va nima kerakligini yozing. Masalan:'),
                          style: theme.textTheme.bodyMedium)),
                  const SizedBox(height: 6),
                  Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final tip in suggestions())
                          ActionChip(
                              label:
                                  Text(tip, style: theme.textTheme.bodyMedium),
                              onPressed: () => send(tip)),
                      ])),
                ]))
        : null;

    // On a page's slot the orb is the slot's size; in the top half of
    // the screen what it says opens downwards, away from the edge.
    final screen = MediaQuery.sizeOf(context);
    final slot = this.slot;
    final orbSize = slot?.shortestSide.clamp(36.0, 52.0) ?? 52.0;
    final down = slot != null && slot.center.dy < screen.height / 2;
    final parts = [
      if (tips.isNotEmpty)
        Padding(
            padding: EdgeInsets.only(top: down ? 8 : 0, bottom: down ? 0 : 8),
            child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final tip in tips)
                    ActionChip(
                        avatar: const Icon(YIcons.idea, size: 16),
                        label: Text(tip, style: theme.textTheme.bodyMedium),
                        onPressed: () => send(tip)),
                ])),
      if (welcome != null)
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420), child: welcome),
      if (banner != null)
        Container(
            constraints: BoxConstraints(
                minHeight: orbSize,
                maxWidth: 420,
                maxHeight: screen.height * 0.45),
            margin: EdgeInsets.only(
                top: pill != null && down ? 8 : 0,
                bottom: pill != null && !down ? 8 : 0),
            child: Align(
                alignment: Alignment.centerRight,
                heightFactor: 1,
                child: banner)),
      // As tall as the orb, so the two share a centre line.
      if (pill != null)
        Container(
            constraints: BoxConstraints(minHeight: orbSize),
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420), child: pill)),
    ];

    final orbButton = Semantics(
        button: true,
        label: listening
            ? tr3('说完了', 'Айтып болдым', 'Готово', 'Done', ky: 'Даяр', uz: 'Tayyor')
            : tr3('语音操作', 'Дауыспен басқару', 'Голосовое управление', 'Voice control', ky: 'Үн менен башкаруу', uz: 'Ovozli boshqaruv'),
        child: GestureDetector(
            key: const Key('voice-button'),
            onTap: orb,
            onLongPress: toggleTyping,
            child: _Orb(
                size: orbSize,
                glow: glow,
                level: level,
                mood: mood,
                icon: listening
                    ? Icons.stop_rounded
                    : typing && widget.speech == null
                        ? YIcons.close
                        // At rest it says what a tap does.
                        : !active
                            ? (widget.speech != null
                                ? YIcons.mic
                                : YIcons.ai)
                            : null)));
    final bubbles = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: down ? parts.reversed.toList() : parts);
    final padding = MediaQuery.viewPaddingOf(context);
    final edged =
        Padding(padding: const EdgeInsets.only(right: 16), child: bubbles);

    // Transparent: taps between the parts reach the page.
    return Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          if (slot == null)
            // No place kept for it: the bottom right corner, what it says
            // beside it.
            Positioned(
                left: 16,
                right: 16,
                bottom: keyboard > 0 ? keyboard + 12 : padding.bottom + 20,
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: bubbles),
                  const SizedBox(width: 10),
                  orbButton,
                ]))
          else
            // On the page's slot; what it says opens above it, or below a
            // slot in the top half of the screen, clear of what is beside
            // the slot.
            Positioned(
                left: 16,
                right: 0,
                top: down ? slot.top : null,
                bottom: down
                    ? null
                    : keyboard > 0
                        ? math.max(keyboard + 12, screen.height - slot.bottom)
                        : screen.height - slot.bottom,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!down) edged,
                      if (!down && parts.isNotEmpty) const SizedBox(height: 8),
                      Padding(
                          padding: EdgeInsets.only(
                              right: math.max(0, screen.width - slot.right)),
                          child: orbButton),
                      if (down && parts.isNotEmpty) const SizedBox(height: 8),
                      if (down) edged,
                    ])),
        ]));
  }
}

/// The microphone: off, hearing a sentence, or turning it into text.
/// off → listening (tap the orb) → transcribing (tap again, or the time
/// limit) → off; tapping the pill while listening goes straight to off.
enum _Mic { off, listening, transcribing }

/// What the orb is doing; each has its own colours.
enum _Mood { idle, listening, thinking, done, failed }

/// The assistant's orb, in the app's colours of wood, clay and stone: a
/// dark sphere with three soft lights turning inside it at different
/// speeds, the way a phone assistant's does. It swells with the voice
/// while listening, turns faster while working, and fades to green or red
/// for an answer or a failure.
///
/// Every part is painted once and then only turned, scaled or faded by
/// the compositor, so the motion repaints nothing, here or on the page.
class _Orb extends StatelessWidget {
  const _Orb(
      {required this.size,
      required this.glow,
      required this.mood,
      this.level,
      this.icon});
  final double size;
  final Animation<double> glow;
  final _Mood mood;

  /// How loud the voice is, 0 to 1; the orb and its halo follow it.
  final Animation<double>? level;
  final IconData? icon;

  static const _amber = Color(0xffF0A63C);
  static const _clay = Color(0xffC8552D);
  static const _wood = Color(0xff9A6232);
  static const _moss = Color(0xff5F9B72);
  static const _stone = Color(0xffB9C4C6);
  static const _red = Color(0xffE0483C);

  static const _lights = {
    _Mood.idle: [_amber, _clay, _stone],
    _Mood.listening: [_amber, _clay, _moss],
    _Mood.thinking: [_amber, _stone, _wood],
    _Mood.done: [_moss, _amber, _moss],
    _Mood.failed: [_red, _clay, _wood],
  };

  // Whole turns, so the loop has no seam.
  static const _turns = [1.0, -2.0, 3.0];
  static const _at = [
    Alignment(0.5, -0.25),
    Alignment(-0.45, 0.4),
    Alignment(0.1, 0.55)
  ];

  static final _breath = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.05), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.05, end: 1), weight: 1),
  ]);

  Widget _disc(Gradient gradient) => DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      child: const SizedBox.expand());

  @override
  Widget build(BuildContext context) {
    final lights = _lights[mood]!;
    final sphere = SizedBox.square(
        dimension: size,
        child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
              BoxShadow(
                  color: lights.first.withValues(alpha: 0.35),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.06))
            ]),
            child: Stack(fit: StackFit.expand, children: [
              _disc(const RadialGradient(
                  colors: [Color(0xff4A3524), Color(0xff1F1610)])),
              for (final (i, color) in lights.indexed)
                RotationTransition(
                    turns: glow.drive(Tween(begin: 0, end: _turns[i])),
                    child: RepaintBoundary(
                        child: _disc(RadialGradient(
                            center: _at[i],
                            radius: 0.62,
                            colors: [
                          color.withValues(alpha: 0.95),
                          color.withValues(alpha: 0)
                        ])))),
              // A fixed highlight makes it a sphere, not a disc.
              _disc(RadialGradient(
                  center: const Alignment(-0.35, -0.5),
                  radius: 0.55,
                  colors: [
                    Colors.white.withValues(alpha: 0.38),
                    Colors.white.withValues(alpha: 0)
                  ])),
            ])));
    // The colours of one mood fade into the next.
    Widget orb = ScaleTransition(
        scale: glow.drive(_breath),
        child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            child: KeyedSubtree(key: ValueKey(mood), child: sphere)));
    final level = this.level;
    if (level != null) {
      orb = Stack(alignment: Alignment.center, children: [
        // A halo that grows with the voice.
        FadeTransition(
            opacity: level.drive(Tween(begin: 0, end: 0.45)),
            child: ScaleTransition(
                scale: level.drive(Tween(begin: 1, end: 1.7)),
                child: RepaintBoundary(
                    child: SizedBox.square(
                        dimension: size,
                        child: _disc(RadialGradient(
                            colors: [_amber, _amber.withValues(alpha: 0)],
                            stops: const [0.55, 1])))))),
        ScaleTransition(
            scale: level.drive(Tween(begin: 1, end: 1.22)), child: orb),
      ]);
    }
    return Stack(alignment: Alignment.center, children: [
      orb,
      if (icon != null) Icon(icon, color: Colors.white, size: size * 0.46),
    ]);
  }
}

/// Puts the voice bar over every page. Wraps the app's content in
/// `MaterialApp.builder`; shows nothing unless voice is built in, the
/// device is a phone or tablet and the backend serves voice.
class VoiceHost extends StatefulWidget {
  const VoiceHost(
      {super.key,
      required this.navigator,
      required this.repos,
      required this.voice,
      required this.child,
      this.audio,
      this.enabled = voiceBuiltIn});
  final GlobalKey<NavigatorState> navigator;
  final VoiceRepositories repos;

  /// The assistant behind the bar; it may also turn speech into text.
  final VoiceBackend voice;
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
    final backend = widget.voice;
    final audio = widget.audio;
    if (!widget.enabled || !voicePlatform) return;
    final s = session = VoiceSession(
        backend: backend,
        executor: ActionExecutor(appActions,
            confirm: (action, args) =>
                confirmAction(widget.navigator.currentContext!, action, args)),
        repos: repos,
        loggedIn: () => repos.session.currentAccount != null,
        sessionId: const Uuid().v4());
    VoiceSession.current = s;
    VoiceSlot.wanted = s.loggedIn;
    // In the navigator's overlay, not a route: pages stay "current" for
    // voice while the bar is open, and its text field has an overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = widget.navigator.currentState?.overlay;
      if (!mounted || overlay == null) return;
      entry = OverlayEntry(
          builder: (context) => Positioned.fill(
              child: VoiceBar(
                  session: s,
                  speech: switch (backend) {
                    final SpeechBackend speaker when audio != null =>
                      Speech(speaker, audio),
                    _ => null,
                  },
                  reader: ReadAloud.instance)));
      overlay.insert(entry!);
    });
  }

  @override
  void dispose() {
    entry?.remove();
    if (VoiceSession.current == session) {
      VoiceSession.current = null;
      VoiceSlot.wanted = VoiceSlot.never;
    }
    session?.dispose();
    widget.audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What the assistant has noted of the house it is asking about, in one
/// line: "12 × 13 м · 2 қабат · 3 жатын бөлме". Empty when nothing is.
String briefLine(Map<String, Object?> brief) {
  String n(Object? v) =>
      v is num && v == v.roundToDouble() ? '${v.round()}' : '$v';
  final width = brief['width_m'];
  final depth = brief['depth_m'];
  final entrance = switch (brief['entrance']) {
    'north' => tr3('北', 'солтүстік', 'север', 'north', ky: 'түндүк', uz: 'shimol'),
    'east' => tr3('东', 'шығыс', 'восток', 'east', ky: 'чыгыш', uz: 'sharq'),
    'south' => tr3('南', 'оңтүстік', 'юг', 'south', ky: 'түштүк', uz: 'janub'),
    'west' => tr3('西', 'батыс', 'запад', 'west', ky: 'батыш', uz: 'gʻarb'),
    _ => null,
  };
  return [
    if (width != null && depth != null)
      '${n(width)} × ${n(depth)} ${tr3('米', 'м', 'м', 'm', ky: 'м', uz: 'm')}'
    else if (brief['area_m2'] case final area?)
      '${n(area)} ${tr3('平米', 'м²', 'м²', 'm²', ky: 'м²', uz: 'm²')}',
    if (brief['floors'] case final floors?)
      tr3('${n(floors)} 层', '${n(floors)} қабат', 'этажей: ${n(floors)}', 'floors: ${n(floors)}', ky: 'кабаттар: ${n(floors)}', uz: 'qavatlar: ${n(floors)}'),
    if (brief['bedrooms'] case final bedrooms?)
      tr3('${n(bedrooms)} 间卧室', '${n(bedrooms)} жатын бөлме',
          'спален: ${n(bedrooms)}',
          'bedrooms: ${n(bedrooms)}', ky: 'уктоочу бөлмөлөр: ${n(bedrooms)}', uz: 'yotoqxonalar: ${n(bedrooms)}'),
    if (entrance != null)
      tr3('入口朝$entrance', 'кіреберіс: $entrance', 'вход: $entrance', 'entrance: $entrance', ky: 'кире бериш: $entrance', uz: 'kirish: $entrance'),
  ].join(' · ');
}
