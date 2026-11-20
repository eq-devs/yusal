import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/features/shared/brand/yicon.dart';
import 'package:yusal/features/voice/state/reply_reader.dart';

String _mb(int bytes) => '${(bytes / 1000000).round()} MB';

/// The speaker beside a reply: reads it aloud with the voice chosen in
/// the voice settings. With the phone's voice, the first tap offers its
/// one-time download; while that runs the button shows its progress, and
/// the reply is read when it is done. With "read every reply" on, it
/// starts by itself.
class ReadAloudButton extends StatefulWidget {
  const ReadAloudButton({super.key, required this.reader, required this.text});
  final ReplyReader reader;
  final String text;

  @override
  State<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends State<ReadAloudButton> {
  ReplyReader get reader => widget.reader;
  ReadAloud? get device => reader.device;

  /// The download was started from here: read the reply when it lands,
  /// even if the dialog was put away meanwhile.
  bool waiting = false;

  @override
  void initState() {
    super.initState();
    device?.status.addListener(_statusChanged);
    _autoRead();
  }

  @override
  void didUpdateWidget(ReadAloudButton old) {
    super.didUpdateWidget(old);
    // Another reply took this one's place.
    if (old.text != widget.text) {
      waiting = false;
      reader.stop();
      _autoRead();
    }
  }

  @override
  void dispose() {
    device?.status.removeListener(_statusChanged);
    reader.stop();
    super.dispose();
  }

  /// Never asks for a download by itself: only reads when it can.
  void _autoRead() {
    if (reader.settings.autoRead && reader.ready) speak();
  }

  void _statusChanged() {
    if (waiting && reader.ready) {
      waiting = false;
      speak();
    }
  }

  Future<void> speak() async {
    try {
      await reader.speak(widget.text);
    } catch (e) {
      if (kDebugMode) debugPrint('read aloud: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(tr3('没能读出来，请再试一次', 'Оқылмады, қайталап көріңіз',
              'Не удалось озвучить, попробуйте ещё раз',
              "Couldn't play it; try again", ky: 'Ойнотуу мүмкүн болбоду; кайра аракет кылыңыз', uz: 'Ijro etib boʻlmadi; qayta urining'))));
    }
  }

  Future<void> tap() async {
    if (reader.speaking.value) return reader.stop();
    final device = this.device;
    if (device == null || !reader.usesDevice) return speak();
    try {
      await device.start();
    } catch (e) {
      if (kDebugMode) debugPrint('read aloud: $e');
    }
    if (!mounted) return;
    if (device.ready) return speak();
    waiting = true;
    await showVoiceDownload(context, device);
    // Put away while downloading: still read the reply when it lands.
    waiting = device.status.value.busy;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([device?.status, reader.speaking]),
      builder: (context, _) {
        final status = reader.usesDevice
            ? device!.status.value
            : VoiceModelStatus.notInstalled;
        final speaking = reader.speaking.value;
        return IconButton(
            key: const Key('voice-speak'),
            visualDensity: VisualDensity.compact,
            tooltip: speaking
                ? tr3('停止朗读', 'Тоқтату', 'Остановить', 'Stop', ky: 'Токтотуу', uz: 'Toʻxtatish')
                : tr3('朗读', 'Дауыстап оқу', 'Озвучить', 'Read aloud', ky: 'Үн чыгарып окуу', uz: 'Ovoz chiqarib oʻqish'),
            onPressed: tap,
            icon: status.busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        key: const Key('voice-speak-progress'),
                        strokeWidth: 2.5,
                        value: status.fraction > 0 ? status.fraction : null))
                : Icon(
                    speaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    size: 20));
      });
}

/// Offers a voice model's download and shows it through to the end:
/// the Kazakh voice unless [title] and [about] say otherwise. True once
/// the model is installed, false when the user said no, null when they
/// put the dialog away and left the download running.
Future<bool?> showVoiceDownload(BuildContext context, VoiceModel reader,
        {String? title, String? about}) =>
    showDialog<bool>(
        context: context,
        builder: (context) =>
            _VoiceDownloadDialog(reader: reader, title: title, about: about));

class _VoiceDownloadDialog extends StatefulWidget {
  const _VoiceDownloadDialog({required this.reader, this.title, this.about});
  final VoiceModel reader;
  final String? title;
  final String? about;

  @override
  State<_VoiceDownloadDialog> createState() => _VoiceDownloadDialogState();
}

class _VoiceDownloadDialogState extends State<_VoiceDownloadDialog> {
  VoiceModel get reader => widget.reader;

  @override
  void initState() {
    super.initState();
    reader.status.addListener(_changed);
  }

  @override
  void dispose() {
    reader.status.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (reader.ready) return Navigator.pop(context, true);
    setState(() {});
  }

  void download() {
    // The status follows the download; a failure shows there too.
    reader.download().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quiet =
        theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final s = reader.status.value;
    final percent = (s.fraction * 100).round();
    return AlertDialog(
        key: const Key('voice-download'),
        icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .12),
                shape: BoxShape.circle),
            child: Icon(YIcons.mic,
                color: colors.primary, size: 28)),
        title: Text(
            widget.title ??
                tr3('下载哈萨克语语音', 'Қазақша дауысты жүктеу',
                'Скачать казахский голос',
                'Download the Kazakh voice', ky: 'Казак тилиндеги үндү жүктөп алуу', uz: 'Qozoq tilidagi ovozni yuklab olish'),
            textAlign: TextAlign.center),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!s.busy && s.phase != VoiceModelPhase.paused) ...[
                Text(
                    widget.about ??
                    tr3(
                        '下载一次，以后助手的回答就能在手机上读出来，不用联网。',
                        'Бір рет жүктеңіз: көмекшінің жауабы телефонның өзінде, интернетсіз дауыстап оқылады.',
                        'Скачайте один раз, и ответы помощника будут озвучиваться прямо на телефоне, без интернета.',
                        "Download once and the assistant's replies are read aloud right on your phone, with no internet.", ky: 'Бир жолу жүктөп алсаңыз, жардамчынын жооптору интернетсиз эле телефонуңузда үн чыгарып окулат.', uz: 'Bir marta yuklab olsangiz, yordamchi javoblari internetsiz telefoningizda ovoz chiqarib oʻqiladi.'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                    tr3(
                        '大小 ${_mb(reader.downloadBytes)}，建议连 Wi-Fi',
                        'Көлемі ${_mb(reader.downloadBytes)}, Wi-Fi арқылы жүктеген дұрыс',
                        'Размер ${_mb(reader.downloadBytes)}, лучше по Wi-Fi',
                        'Size ${_mb(reader.downloadBytes)}; Wi-Fi is best', ky: 'Көлөмү ${_mb(reader.downloadBytes)}; Wi-Fi жакшыраак', uz: 'Hajmi ${_mb(reader.downloadBytes)}; Wi-Fi maʼqul'),
                    textAlign: TextAlign.center,
                    style: quiet),
                if (s.phase == VoiceModelPhase.failed) ...[
                  const SizedBox(height: 12),
                  Text(
                      tr3('下载没成功：${s.error}', 'Жүктелмеді: ${s.error}',
                          'Не скачалось: ${s.error}',
                          'Download failed: ${s.error}', ky: 'Жүктөө ишке ашкан жок: ${s.error}', uz: 'Yuklab boʻlmadi: ${s.error}'),
                      key: const Key('voice-download-error'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.error)),
                ],
              ] else ...[
                Text('$percent%',
                    key: const Key('voice-download-percent'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                        minHeight: 8,
                        value: s.phase == VoiceModelPhase.waiting &&
                                s.fraction == 0
                            ? null
                            : s.fraction)),
                const SizedBox(height: 12),
                Text(
                    switch (s.phase) {
                      VoiceModelPhase.waiting =>
                        tr3('等待网络…', 'Желіні күтуде…', 'Ждём сеть…', 'Waiting for the network…', ky: 'Тармакты күтүүдө…', uz: 'Tarmoq kutilmoqda…'),
                      VoiceModelPhase.verifying =>
                        tr3('正在校验…', 'Тексерілуде…', 'Проверка…', 'Checking…', ky: 'Текшерилүүдө…', uz: 'Tekshirilmoqda…'),
                      VoiceModelPhase.paused =>
                        tr3('已暂停', 'Тоқтатылды', 'Пауза', 'Paused', ky: 'Тындырылды', uz: 'Toʻxtatildi'),
                      _ =>
                          '${_mb((reader.downloadBytes * s.fraction).round())} / ${_mb(reader.downloadBytes)}',
                    },
                    textAlign: TextAlign.center,
                    style: quiet),
              ],
              for (final c in reader.credits) ...[
                const SizedBox(height: 12),
                Text('${c.text} (${c.license})',
                    textAlign: TextAlign.center,
                    style: quiet?.copyWith(fontSize: 10)),
              ],
            ]),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: s.busy
            ? [
                TextButton(
                    key: const Key('voice-download-cancel'),
                    onPressed: () {
                      reader.cancel();
                      Navigator.pop(context, false);
                    },
                    child: Text(tr3('取消下载', 'Тоқтату', 'Отменить', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                FilledButton.tonal(
                    key: const Key('voice-download-hide'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr3('后台下载', 'Фонда жүктеу', 'В фоне', 'In background', ky: 'Фондо', uz: 'Fonda'))),
              ]
            : [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr3('以后再说', 'Кейін', 'Не сейчас', 'Not now', ky: 'Азыр эмес', uz: 'Hozir emas'))),
                FilledButton.icon(
                    key: const Key('voice-download-start'),
                    onPressed: download,
                    icon: const Icon(YIcons.download, size: 18),
                    label: Text(s.phase == VoiceModelPhase.paused
                        ? tr3('继续', 'Жалғастыру', 'Продолжить', 'Continue', ky: 'Улантуу', uz: 'Davom etish')
                        : tr3('下载', 'Жүктеу', 'Скачать', 'Download', ky: 'Жүктөп алуу', uz: 'Yuklab olish'))),
              ]);
  }
}
