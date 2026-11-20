import 'package:flutter/material.dart';

import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/brand/yicon.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/voice/repository/speech.dart' show SpeechSynth;
import 'package:yusal/features/voice/repository/voice_repository.dart';
import 'package:yusal/features/voice/state/reply_reader.dart';
import 'package:yusal/features/voice/widgets/read_aloud_button.dart'
    show showVoiceDownload;
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/voice/offline_speech.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/service/voice/voice_settings.dart';

String _mb(int bytes) => '${(bytes / 1000000).round()} MB';

/// "F2" → "Woman 2", "M1" → "Man 1"; any other name as it is.
String voiceName(String raw, int index) {
  final m = RegExp(r'^([FM])(\d+)$').firstMatch(raw);
  if (m == null) return raw.isEmpty ? '${index + 1}' : raw;
  return m[1] == 'F'
      ? tr3('女声 ${m[2]}', 'Әйел дауысы ${m[2]}', 'Женский ${m[2]}',
          'Woman ${m[2]}', ky: 'Аял үнү ${m[2]}', uz: 'Ayol ovozi ${m[2]}')
      : tr3('男声 ${m[2]}', 'Ер дауысы ${m[2]}', 'Мужской ${m[2]}',
          'Man ${m[2]}', ky: 'Эркек үнү ${m[2]}', uz: 'Erkak ovozi ${m[2]}');
}

String _ttsName(TtsEngine e) => switch (e) {
      TtsEngine.device => tr3('手机本地', 'Телефонда', 'На телефоне', 'On the phone',
          ky: 'Телефондо', uz: 'Telefonda'),
      TtsEngine.server => tr3('服务器', 'Серверде', 'На сервере', 'On the server',
          ky: 'Серверде', uz: 'Serverda'),
    };

String _sttName(SttEngine e) => switch (e) {
      SttEngine.server => tr3('服务器', 'Серверде', 'На сервере', 'On the server',
          ky: 'Серверде', uz: 'Serverda'),
      SttEngine.device => tr3('手机本地', 'Телефонда', 'На телефоне', 'On the phone',
          ky: 'Телефондо', uz: 'Telefonda'),
      SttEngine.deviceAccurate =>
        tr3('手机本地（高精度）', 'Телефонда (дәлірек)', 'На телефоне (точнее)',
            'On the phone (more accurate)',
            ky: 'Телефондо (тагыраак)', uz: 'Telefonda (aniqroq)'),
    };

String _speedName(double v) =>
    v == 1.0 ? tr3('正常', 'Қалыпты', 'Обычная', 'Normal', ky: 'Кадимки', uz: 'Oddiy') : '$v×';

String _modelState(VoiceModel m) {
  final s = m.status.value;
  return switch (s.phase) {
    VoiceModelPhase.installed =>
      '${tr3('已下载', 'Жүктелген', 'Скачано', 'Downloaded', ky: 'Жүктөлдү', uz: 'Yuklab olindi')} · ${_mb(m.diskBytes)}',
    VoiceModelPhase.downloading ||
    VoiceModelPhase.waiting ||
    VoiceModelPhase.verifying =>
      '${tr3('正在下载', 'Жүктелуде', 'Загрузка', 'Downloading', ky: 'Жүктөлүүдө', uz: 'Yuklanmoqda')} ${(s.fraction * 100).round()}%',
    VoiceModelPhase.paused => tr3('已暂停', 'Тоқтатылды', 'Пауза', 'Paused',
        ky: 'Тындырылды', uz: 'Toʻxtatildi'),
    VoiceModelPhase.failed => tr3('下载失败', 'Жүктелмеді', 'Не скачалось',
        'Download failed', ky: 'Жүктөлгөн жок', uz: 'Yuklab boʻlmadi'),
    VoiceModelPhase.notInstalled =>
      '${tr3('未下载', 'Жүктелмеген', 'Не скачано', 'Not downloaded', ky: 'Жүктөлгөн жок', uz: 'Yuklab olinmagan')} · ${_mb(m.downloadBytes)}',
  };
}

/// Everything about voice in one place: where replies are read aloud
/// (the phone's qazvoice voice or the server), with which voice and how
/// fast; where speech is recognized (the server or one of two on-device
/// models); and the downloads those choices need, with their license
/// notices, which CC BY 4.0 requires.
class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key, this.settings, this.reader});
  final VoiceSettings? settings;

  /// For the "listen" row; made from the backend when not given.
  final ReplyReader? reader;

  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> {
  static const sample = 'Сәлеметсіз бе! Мен сіздің үй жобалау көмекшіңізбін.';

  late final VoiceSettings settings = widget.settings ?? VoiceSettings.instance;
  ReplyReader? _own;
  late final ReplyReader reader = widget.reader ?? _makeReader();

  ReadAloud? get tts => ReadAloud.instance;
  List<(VoiceModel, String, String)> get models => [
        if (tts case final m?)
          (
            m,
            tr3('哈萨克语语音', 'Қазақша дауыс', 'Казахский голос', 'Kazakh voice',
                ky: 'Казакча үн', uz: 'Qozoqcha ovoz'),
            tr3('用来朗读回答', 'Жауапты дауыстап оқиды', 'Озвучивает ответы',
                'Reads replies aloud',
                ky: 'Жоопторду үн чыгарып окуйт', uz: 'Javoblarni ovoz chiqarib oʻqiydi')
          ),
        if (OfflineSpeech.standard case final m?)
          (
            m,
            tr3('语音识别', 'Сөз тану', 'Распознавание речи', 'Speech recognition',
                ky: 'Сөз таануу', uz: 'Nutqni tanish'),
            tr3('哈萨克语和俄语', 'Қазақша және орысша', 'Казахский и русский',
                'Kazakh and Russian',
                ky: 'Казакча жана орусча', uz: 'Qozoqcha va ruscha')
          ),
        if (OfflineSpeech.accurate case final m?)
          (
            m,
            tr3('语音识别（高精度）', 'Сөз тану (дәлірек)',
                'Распознавание речи (точнее)',
                'Speech recognition (more accurate)',
                ky: 'Сөз таануу (тагыраак)', uz: 'Nutqni tanish (aniqroq)'),
            tr3('更准，但更慢更大', 'Дәлірек, бірақ баяу әрі үлкен',
                'Точнее, но медленнее и больше',
                'More accurate, but slower and larger',
                ky: 'Тагыраак, бирок жайыраак жана чоңураак',
                uz: 'Aniqroq, lekin sekinroq va kattaroq')
          ),
      ];

  ReplyReader _makeReader() {
    final voice = context.read(voiceRepositoryProvider);
    return _own = ReplyReader(
        device: tts,
        server: switch (voice) {
          final SpeechSynth synth => synth,
          _ => null,
        },
        settings: settings);
  }

  @override
  void initState() {
    super.initState();
    for (final (m, _, _) in models) {
      m.start().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    if (_own == null) reader.stop();
    super.dispose();
  }

  /// Offers [model]'s download when a choice needs it.
  Future<void> ensure(VoiceModel? model, String title, String about) async {
    if (model == null || model.ready || model.status.value.busy) return;
    await showVoiceDownload(context, model, title: title, about: about);
  }

  Future<void> pickTts() async {
    final v = await pickOne<TtsEngine>(
        context,
        tr3('在哪里朗读', 'Қайда оқылады', 'Где озвучивать',
            'Where replies are read', ky: 'Кайда окулат', uz: 'Qayerda oʻqiladi'),
        [
          if (tts != null) (TtsEngine.device, _ttsName(TtsEngine.device)),
          if (reader.server != null)
            (TtsEngine.server, _ttsName(TtsEngine.server)),
        ],
        selected: settings.tts);
    if (v == null || !mounted) return;
    settings.setTts(v);
    if (v == TtsEngine.device) {
      final (m, title, _) = models.first;
      await ensure(
          m,
          title,
          tr3(
              '下载一次，回答就能在手机上读出来，不用联网。',
              'Бір рет жүктеңіз: жауап телефонның өзінде, интернетсіз оқылады.',
              'Скачайте один раз, и ответы будут озвучиваться на телефоне, без интернета.',
              'Download once and replies are read aloud on the phone, with no internet.',
              ky: 'Бир жолу жүктөп алыңыз: жооптор интернетсиз эле телефондо окулат.',
              uz: 'Bir marta yuklab oling: javoblar internetsiz telefonda oʻqiladi.'));
    }
  }

  Future<void> pickStt() async {
    final v = await pickOne<SttEngine>(
        context,
        tr3('在哪里识别语音', 'Сөз қайда танылады', 'Где распознавать речь',
            'Where speech is recognized',
            ky: 'Сөз кайда таанылат', uz: 'Nutq qayerda tanaladi'),
        [
          (SttEngine.server, _sttName(SttEngine.server)),
          if (OfflineSpeech.standard != null)
            (SttEngine.device, _sttName(SttEngine.device)),
          if (OfflineSpeech.accurate != null)
            (SttEngine.deviceAccurate, _sttName(SttEngine.deviceAccurate)),
        ],
        selected: settings.stt);
    if (v == null || !mounted) return;
    settings.setStt(v);
    final model = switch (v) {
      SttEngine.server => null,
      SttEngine.device => OfflineSpeech.standard,
      SttEngine.deviceAccurate => OfflineSpeech.accurate,
    };
    await ensure(
        model,
        tr3('下载语音识别模型', 'Сөз тану моделін жүктеу',
            'Скачать модель распознавания', 'Download the speech model',
            ky: 'Сөз таануу моделин жүктөп алуу',
            uz: 'Nutqni tanish modelini yuklab olish'),
        tr3(
            '下载一次，你说的话就在手机上识别，录音不上传。下载完成前仍由服务器识别。',
            'Бір рет жүктеңіз: сөзіңіз телефонда танылады, жазба еш жерге жіберілмейді. Жүктелгенше сервер таниды.',
            'Скачайте один раз, и речь будет распознаваться на телефоне, запись никуда не отправляется. До этого распознаёт сервер.',
            'Download once and what you say is recognized on the phone; the recording is not sent anywhere. Until then the server recognizes it.',
            ky: 'Бир жолу жүктөп алыңыз: сөзүңүз телефондо таанылат, жазуу эч жакка жөнөтүлбөйт. Ага чейин сервер тааныйт.',
            uz: 'Bir marta yuklab oling: gapingiz telefonda tanaladi, yozuv hech qayerga yuborilmaydi. Shu paytgacha server taniydi.'));
  }

  Future<void> pickVoice() async {
    final names = tts?.voices ?? const <String>[];
    final v = await pickOne<int>(
        context,
        tr3('声音', 'Дауыс', 'Голос', 'Voice', ky: 'Үн', uz: 'Ovoz'),
        [
          for (var i = 0; i < ReadAloud.voiceCount; i++)
            (i, voiceName(i < names.length ? names[i] : _fallback[i], i))
        ],
        selected: settings.voice);
    if (v != null) settings.setVoice(v);
  }

  static const _fallback = ['F1', 'F2', 'F3', 'M1', 'M2', 'M3'];

  Future<void> pickSpeed() async {
    final v = await pickOne<double>(context, tr3('语速', 'Жылдамдық', 'Скорость', 'Speed',
        ky: 'Ылдамдык', uz: 'Tezlik'),
        [for (final s in VoiceSettings.speeds) (s, _speedName(s))],
        selected: settings.speed);
    if (v != null) settings.setSpeed(v);
  }

  Future<void> listen() async {
    if (reader.speaking.value) return reader.stop();
    if (reader.needsDownload) {
      final (m, title, about) = models.first;
      await ensure(m, title, about);
      if (!mounted || reader.needsDownload) return;
    }
    try {
      await reader.speak(sample);
    } catch (_) {
      if (mounted) {
        toast(
            context,
            tr3('没能读出来，请再试一次', 'Оқылмады, қайталап көріңіз',
                'Не удалось озвучить, попробуйте ещё раз',
                'Could not read it aloud; try again',
                ky: 'Окулган жок, кайра аракет кылыңыз',
                uz: 'Oʻqib boʻlmadi, qayta urinib koʻring'));
      }
    }
  }

  Future<void> manage(VoiceModel m, String title, String about) async {
    if (!m.ready) {
      await showVoiceDownload(context, m, title: title, about: about);
      return;
    }
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                key: const Key('voice-model-delete'),
                title: Text(title),
                content: Text(tr3(
                    '从手机里删除？占用 ${_mb(m.diskBytes)}，以后可以再下载。',
                    'Телефоннан өшірілсін бе? ${_mb(m.diskBytes)} босайды, кейін қайта жүктеуге болады.',
                    'Удалить с телефона? Освободится ${_mb(m.diskBytes)}, потом можно скачать снова.',
                    'Delete it from the phone? That frees ${_mb(m.diskBytes)}; you can download it again later.',
                    ky: 'Телефондон өчүрүлсүнбү? ${_mb(m.diskBytes)} бошойт, кийин кайра жүктөп алса болот.',
                    uz: 'Telefondan oʻchirilsinmi? ${_mb(m.diskBytes)} boʻshaydi, keyin qayta yuklab olish mumkin.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel',
                          ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(tr3('删除', 'Өшіру', 'Удалить', 'Delete',
                          ky: 'Өчүрүү', uz: 'Oʻchirish'))),
                ]));
    if (yes ?? false) await m.delete();
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final t = YTokens.of(context);
    final names = tts?.voices ?? const <String>[];
    return PageScaffold(
        title: tr3('语音', 'Дауыс', 'Голос', 'Voice', ky: 'Үн', uz: 'Ovoz'),
        body: ListenableBuilder(
            listenable: Listenable.merge([
              settings,
              reader.speaking,
              for (final (m, _, _) in models) m.status
            ]),
            builder: (context, _) {
              final credits = [for (final (m, _, _) in models) ...m.credits];
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (reader.available)
                      SettingsGroup(
                          title: tr3('朗读回答', 'Жауапты дауыстап оқу',
                              'Озвучивание ответов', 'Reading replies aloud',
                              ky: 'Жоопторду үн чыгарып окуу',
                              uz: 'Javoblarni ovoz chiqarib oʻqish'),
                          children: [
                            SettingsRow(
                                key: const Key('voice-tts-engine'),
                                icon: Icons.volume_up_outlined,
                                title: tr3('在哪里朗读', 'Қайда оқылады', 'Где озвучивать',
                                    'Where replies are read',
                                    ky: 'Кайда окулат', uz: 'Qayerda oʻqiladi'),
                                value: _ttsName(reader.usesDevice
                                    ? TtsEngine.device
                                    : TtsEngine.server),
                                onTap: pickTts),
                            if (reader.usesDevice)
                              SettingsRow(
                                  key: const Key('voice-tts-voice'),
                                  icon: YIcons.profile,
                                  title: tr3('声音', 'Дауыс', 'Голос', 'Voice', ky: 'Үн', uz: 'Ovoz'),
                                  value: voiceName(
                                      settings.voice < names.length
                                          ? names[settings.voice]
                                          : _fallback[settings.voice %
                                              _fallback.length],
                                      settings.voice),
                                  onTap: pickVoice),
                            SettingsRow(
                                key: const Key('voice-tts-speed'),
                                icon: Icons.speed_outlined,
                                title: tr3('语速', 'Жылдамдық', 'Скорость', 'Speed',
        ky: 'Ылдамдык', uz: 'Tezlik'),
                                value: _speedName(settings.speed),
                                onTap: pickSpeed),
                            SettingsRow(
                                key: const Key('voice-auto-read'),
                                icon: Icons.play_circle_outline,
                                title: tr3('自动朗读每条回答', 'Әр жауапты өзі оқысын',
                                    'Озвучивать каждый ответ',
                                    'Read every reply aloud',
                                    ky: 'Ар бир жоопту өзү окусун',
                                    uz: 'Har bir javobni oʻzi oʻqisin'),
                                trailing: Switch(
                                    value: settings.autoRead,
                                    onChanged: settings.setAutoRead),
                                onTap: () =>
                                    settings.setAutoRead(!settings.autoRead)),
                            SettingsRow(
                                key: const Key('voice-listen'),
                                icon: reader.speaking.value
                                    ? Icons.stop_circle_outlined
                                    : Icons.hearing_outlined,
                                title: reader.speaking.value
                                    ? tr3('停止', 'Тоқтату', 'Остановить', 'Stop',
                                        ky: 'Токтотуу', uz: 'Toʻxtatish')
                                    : tr3('试听', 'Тыңдап көру', 'Послушать', 'Listen',
                                        ky: 'Угуп көрүү', uz: 'Tinglab koʻrish'),
                                onTap: listen),
                          ]),
                    SettingsGroup(
                        title: tr3('语音识别', 'Сөз тану', 'Распознавание речи', 'Speech recognition',
                ky: 'Сөз таануу', uz: 'Nutqni tanish'),
                        children: [
                          SettingsRow(
                              key: const Key('voice-stt-engine'),
                              icon: YIcons.mic,
                              title: tr3('在哪里识别', 'Қайда танылады',
                                  'Где распознавать', 'Where it is recognized',
                                  ky: 'Кайда таанылат', uz: 'Qayerda tanaladi'),
                              value: _sttName(settings.stt),
                              onTap: pickStt),
                        ]),
                    if (models.isNotEmpty)
                      SettingsGroup(
                          title: tr3('手机上的模型', 'Телефондағы модельдер',
                              'Модели на телефоне', 'Models on the phone',
                              ky: 'Телефондогу моделдер',
                              uz: 'Telefondagi modellar'),
                          children: [
                            for (final (i, (m, title, about)) in models.indexed)
                              SettingsRow(
                                  key: Key('voice-model-$i'),
                                  icon: m.ready
                                      ? YIcons.checkCircle
                                      : YIcons.download,
                                  title: title,
                                  subtitle: '$about · ${_modelState(m)}',
                                  onTap: () => manage(m, title, about)),
                          ]),
                    if (credits.isNotEmpty) ...[
                      const SizedBox(height: YSpace.md),
                      for (final c in credits)
                        Padding(
                            padding: const EdgeInsets.only(bottom: YSpace.sm),
                            child: Text('${c.name} · ${c.license}\n${c.text}',
                                style: YText.caption.copyWith(color: t.muted))),
                    ],
                  ]);
            }));
  }
}
