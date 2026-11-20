import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../services/voice/offline_speech.dart';
import '../../shared/ui/theme.dart';
import '../../shared/ui/widgets.dart';

String _mb(int bytes) => '${(bytes / 1000000).round()} MB';

/// One line for the Me page: whether speech is heard on this phone.
String offlineVoiceValue(OfflineStatus s) => switch (s.phase) {
      OfflinePhase.installed => tr3('已开启', 'Қосулы', 'Включено'),
      OfflinePhase.downloading ||
      OfflinePhase.waiting ||
      OfflinePhase.verifying =>
        '${(s.fraction * 100).round()}%',
      OfflinePhase.paused => tr3('已暂停', 'Тоқтатылды', 'Пауза'),
      _ => tr3('未下载', 'Жүктелмеген', 'Не скачано'),
    };

/// Downloads or removes the on-device Kazakh speech model (qazvoice), and
/// shows its license notices, which CC BY 4.0 requires.
class OfflineVoicePage extends StatefulWidget {
  const OfflineVoicePage({super.key, required this.speech});
  final OfflineSpeech speech;

  @override
  State<OfflineVoicePage> createState() => _OfflineVoicePageState();
}

class _OfflineVoicePageState extends State<OfflineVoicePage> {
  late final Future<void> started = widget.speech.start();

  OfflineSpeech get speech => widget.speech;

  Future<void> download() async {
    // The status follows the download; a failure shows there too.
    unawaited(speech.download().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    return PageScaffold(
        title: tr3('离线语音识别', 'Офлайн дауыс тану', 'Офлайн-распознавание'),
        body: FutureBuilder<void>(
            future: started,
            builder: (context, snap) {
              if (snap.hasError) {
                return Hint(
                    tr3('这台设备用不了离线识别', 'Бұл құрылғыда жұмыс істемейді',
                        'На этом устройстве недоступно'),
                    warn: true);
              }
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return ValueListenableBuilder<OfflineStatus>(
                  valueListenable: speech.status,
                  builder: (context, s, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                tr3(
                                    '下载后，你说的话在手机上直接识别成文字，不上传录音，没有网络也能识别。'
                                        '只支持哈萨克语（也能听懂俄语）。没下载时照旧由服务器识别。',
                                    'Жүктелген соң сөзіңіз телефонның өзінде мәтінге айналады: '
                                        'дауыс жазбасы ешқайда жіберілмейді, интернетсіз де істейді. '
                                        'Қазақ тілі (орысшасын да түсінеді). Жүктелмесе, бұрынғыдай сервер таниды.',
                                    'После загрузки речь распознаётся на самом телефоне: запись '
                                        'никуда не отправляется, работает без интернета. Казахский '
                                        '(и русский). Пока модель не скачана, распознаёт сервер.'),
                                style: YText.body),
                            const SizedBox(height: YSpace.md),
                            Text(
                                tr3(
                                    '一次性下载 ${_mb(speech.downloadBytes)}，占用 ${_mb(speech.diskBytes)}，建议连 Wi-Fi。',
                                    'Бір рет жүктеледі: ${_mb(speech.downloadBytes)}, телефонда ${_mb(speech.diskBytes)}. Wi-Fi арқылы жүктеген дұрыс.',
                                    'Скачивается один раз: ${_mb(speech.downloadBytes)}, на телефоне ${_mb(speech.diskBytes)}. Лучше по Wi-Fi.'),
                                style: YText.caption.copyWith(color: t.muted)),
                            const SizedBox(height: YSpace.lg),
                            ..._status(s),
                            const SizedBox(height: YSpace.xl),
                            for (final c in speech.credits) ...[
                              Text('${c.name} · ${c.license}',
                                  style: YText.labelStrong
                                      .copyWith(color: t.muted)),
                              const SizedBox(height: YSpace.xs),
                              Text(c.text,
                                  style:
                                      YText.caption.copyWith(color: t.muted)),
                              const SizedBox(height: YSpace.md),
                            ],
                          ]));
            }));
  }

  List<Widget> _status(OfflineStatus s) => switch (s.phase) {
        OfflinePhase.installed => [
            Hint(
                key: const Key('offline-voice-ready'),
                tr3('已开启：语音在手机上识别', 'Қосулы: сөз телефонда танылады',
                    'Включено: речь распознаётся на телефоне'),
                icon: Icons.check_circle_outline),
            const SizedBox(height: YSpace.md),
            BusyButton(
                key: const Key('offline-voice-delete'),
                outlined: true,
                label: tr3('删除模型', 'Модельді өшіру', 'Удалить модель'),
                onPressed: speech.delete),
          ],
        OfflinePhase.downloading ||
        OfflinePhase.waiting ||
        OfflinePhase.verifying ||
        OfflinePhase.paused =>
          [
            LinearProgressIndicator(
                key: const Key('offline-voice-progress'),
                value: s.phase == OfflinePhase.waiting && s.fraction == 0
                    ? null
                    : s.fraction),
            const SizedBox(height: YSpace.sm),
            Text(
                switch (s.phase) {
                  OfflinePhase.waiting =>
                    tr3('等待网络…', 'Желіні күтуде…', 'Ждём сеть…'),
                  OfflinePhase.verifying =>
                    tr3('正在校验…', 'Тексерілуде…', 'Проверка…'),
                  OfflinePhase.paused => tr3('已暂停', 'Тоқтатылды', 'Пауза'),
                  _ =>
                    '${tr3('正在下载', 'Жүктелуде', 'Загрузка')} ${(s.fraction * 100).round()}%',
                },
                style: YText.label),
            const SizedBox(height: YSpace.md),
            if (s.phase == OfflinePhase.paused)
              BusyButton(
                  key: const Key('offline-voice-download'),
                  label: tr3('继续下载', 'Жалғастыру', 'Продолжить'),
                  onPressed: download)
            else
              BusyButton(
                  key: const Key('offline-voice-cancel'),
                  outlined: true,
                  label: tr3('取消', 'Болдырмау', 'Отменить'),
                  onPressed: speech.cancel),
          ],
        _ => [
            if (s.phase == OfflinePhase.failed) ...[
              Hint(
                  key: const Key('offline-voice-error'),
                  tr3('下载没成功：${s.error}', 'Жүктелмеді: ${s.error}',
                      'Не скачалось: ${s.error}'),
                  warn: true),
              const SizedBox(height: YSpace.md),
            ],
            BusyButton(
                key: const Key('offline-voice-download'),
                label:
                    '${tr3('下载', 'Жүктеу', 'Скачать')} (${_mb(speech.downloadBytes)})',
                onPressed: download),
          ],
      };
}
