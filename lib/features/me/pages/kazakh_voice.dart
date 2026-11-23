import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';

String _mb(int bytes) => '${(bytes / 1000000).round()} MB';

/// One line for the Me page: whether replies can be read aloud.
String kazakhVoiceValue(VoiceModelStatus s) => switch (s.phase) {
      VoiceModelPhase.installed => tr3('已下载', 'Жүктелген', 'Скачано', 'Downloaded'),
      VoiceModelPhase.downloading ||
      VoiceModelPhase.waiting ||
      VoiceModelPhase.verifying =>
        '${(s.fraction * 100).round()}%',
      VoiceModelPhase.paused => tr3('已暂停', 'Тоқтатылды', 'Пауза', 'Paused'),
      _ => tr3('未下载', 'Жүктелмеген', 'Не скачано', 'Not downloaded'),
    };

/// Downloads or removes the on-device Kazakh voice (qazvoice), and
/// shows its license notices, which CC BY 4.0 requires.
class KazakhVoicePage extends StatefulWidget {
  const KazakhVoicePage({super.key, required this.reader});
  final ReadAloud reader;

  @override
  State<KazakhVoicePage> createState() => _KazakhVoicePageState();
}

class _KazakhVoicePageState extends State<KazakhVoicePage> {
  late final Future<void> started = widget.reader.start();

  ReadAloud get reader => widget.reader;

  Future<void> download() async {
    // The status follows the download; a failure shows there too.
    reader.download().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final t = YTokens.of(context);
    return PageScaffold(
        title: tr3('哈萨克语朗读', 'Қазақша дауыс', 'Казахский голос', 'Kazakh voice'),
        body: FutureBuilder<void>(
            future: started,
            builder: (context, snap) {
              if (snap.hasError) {
                return Hint(
                    tr3('这台设备用不了', 'Бұл құрылғыда жұмыс істемейді',
                        'На этом устройстве недоступно',
                        'Not available on this device'),
                    warn: true);
              }
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return ValueListenableBuilder<VoiceModelStatus>(
                  valueListenable: reader.status,
                  builder: (context, s, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                tr3(
                                    '下载后，点助手回答旁边的喇叭，就能用哈萨克语读出来。'
                                        '在手机上合成，不用联网。',
                                    'Жүктелген соң көмекшінің жауабы жанындағы дыбыс белгісін '
                                        'бассаңыз, жауап қазақша дауыстап оқылады. Телефонның '
                                        'өзінде, интернетсіз істейді.',
                                    'После загрузки нажмите на динамик рядом с ответом '
                                        'помощника, и он прозвучит по-казахски. Работает на '
                                        'самом телефоне, без интернета.',
                                    "After downloading, tap the speaker next to the assistant's reply and it's read aloud in Kazakh. Works on the phone itself, with no internet."),
                                style: YText.body),
                            const SizedBox(height: YSpace.md),
                            Text(
                                tr3(
                                    '一次性下载 ${_mb(reader.downloadBytes)}，占用 ${_mb(reader.diskBytes)}，建议连 Wi-Fi。',
                                    'Бір рет жүктеледі: ${_mb(reader.downloadBytes)}, телефонда ${_mb(reader.diskBytes)}. Wi-Fi арқылы жүктеген дұрыс.',
                                    'Скачивается один раз: ${_mb(reader.downloadBytes)}, на телефоне ${_mb(reader.diskBytes)}. Лучше по Wi-Fi.',
                                    'One-time download: ${_mb(reader.downloadBytes)}, ${_mb(reader.diskBytes)} on the phone. Wi-Fi is best.'),
                                style: YText.caption.copyWith(color: t.muted)),
                            const SizedBox(height: YSpace.lg),
                            ..._status(s),
                            const SizedBox(height: YSpace.xl),
                            for (final c in reader.credits) ...[
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

  List<Widget> _status(VoiceModelStatus s) => switch (s.phase) {
        VoiceModelPhase.installed => [
            Hint(
                key: const Key('kazakh-voice-ready'),
                tr3('已下载，可以朗读了', 'Жүктелген, оқуға дайын',
                    'Скачано, можно слушать',
                    'Downloaded; ready to listen'),
                icon: Icons.check_circle_outline),
            const SizedBox(height: YSpace.md),
            BusyButton(
                key: const Key('kazakh-voice-delete'),
                outlined: true,
                label: tr3('删除语音', 'Дауысты өшіру', 'Удалить голос', 'Delete the voice'),
                onPressed: reader.delete),
          ],
        VoiceModelPhase.downloading ||
        VoiceModelPhase.waiting ||
        VoiceModelPhase.verifying ||
        VoiceModelPhase.paused =>
          [
            LinearProgressIndicator(
                key: const Key('kazakh-voice-progress'),
                value: s.phase == VoiceModelPhase.waiting && s.fraction == 0
                    ? null
                    : s.fraction),
            const SizedBox(height: YSpace.sm),
            Text(
                switch (s.phase) {
                  VoiceModelPhase.waiting =>
                    tr3('等待网络…', 'Желіні күтуде…', 'Ждём сеть…', 'Waiting for the network…'),
                  VoiceModelPhase.verifying =>
                    tr3('正在校验…', 'Тексерілуде…', 'Проверка…', 'Checking…'),
                  VoiceModelPhase.paused => tr3('已暂停', 'Тоқтатылды', 'Пауза', 'Paused'),
                  _ =>
                    '${tr3('正在下载', 'Жүктелуде', 'Загрузка', 'Download')} ${(s.fraction * 100).round()}%',
                },
                style: YText.label),
            const SizedBox(height: YSpace.md),
            if (s.phase == VoiceModelPhase.paused)
              BusyButton(
                  key: const Key('kazakh-voice-download'),
                  label: tr3('继续下载', 'Жалғастыру', 'Продолжить', 'Continue'),
                  onPressed: download)
            else
              BusyButton(
                  key: const Key('kazakh-voice-cancel'),
                  outlined: true,
                  label: tr3('取消', 'Болдырмау', 'Отменить', 'Cancel'),
                  onPressed: reader.cancel),
          ],
        _ => [
            if (s.phase == VoiceModelPhase.failed) ...[
              Hint(
                  key: const Key('kazakh-voice-error'),
                  tr3('下载没成功：${s.error}', 'Жүктелмеді: ${s.error}',
                      'Не скачалось: ${s.error}',
                      'Download failed: ${s.error}'),
                  warn: true),
              const SizedBox(height: YSpace.md),
            ],
            BusyButton(
                key: const Key('kazakh-voice-download'),
                label:
                    '${tr3('下载', 'Жүктеу', 'Скачать', 'Download')} (${_mb(reader.downloadBytes)})',
                onPressed: download),
          ],
      };
}
