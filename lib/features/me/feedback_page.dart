import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../../app/settings.dart';
import '../../data/repositories.dart';
import '../../shared/ui/l10n.dart';
import '../../shared/ui/scope.dart';
import '../../shared/ui/theme.dart';
import '../../shared/ui/widgets.dart';

/// What the app attaches to feedback about itself, so nobody has to type
/// their version or phone model. Each value is shown before sending.
Future<Map<String, String>> loadFeedbackContext() async {
  final out = <String, String>{
    'language': AppSettings.instance.lang.name,
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
  };
  try {
    final p = await PackageInfo.fromPlatform();
    out['app_version'] =
        p.buildNumber.isEmpty ? p.version : '${p.version} (${p.buildNumber})';
  } catch (_) {}
  try {
    final d = DeviceInfoPlugin();
    if (kIsWeb) {
      out['device'] = (await d.webBrowserInfo).browserName.name;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await d.androidInfo;
      out['device'] = '${a.manufacturer} ${a.model}';
      out['os_version'] = 'Android ${a.version.release}';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final i = await d.iosInfo;
      out['device'] = i.utsname.machine;
      out['os_version'] = '${i.systemName} ${i.systemVersion}';
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      final m = await d.macOsInfo;
      out['device'] = m.model;
      out['os_version'] = 'macOS ${m.osRelease}';
    }
  } catch (_) {}
  return out;
}

/// A short note to the team: one text box, the device details the app adds
/// (shown, and switchable off), and send. A failed send keeps the text and
/// says so next to the button, which then retries.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.loadContext = loadFeedbackContext});

  /// Replaced in tests.
  final Future<Map<String, String>> Function() loadContext;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const maxLength = 2000;

  final text = TextEditingController();

  /// Kept across retries so a send whose answer got lost is stored once.
  final requestId = const Uuid().v4();
  late final Future<Map<String, String>> details = widget.loadContext();
  bool attach = true;
  String? error;

  @override
  void initState() {
    super.initState();
    text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final ctx = attach ? await details : null;
    if (!mounted) return;
    setState(() => error = null);
    try {
      await context.repos.sendFeedback(
          requestId: requestId, text: text.text.trim(), context: ctx);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => error = failureText(e));
      return;
    }
    if (!mounted) return;
    toast(
        context,
        tr3('已收到，谢谢！每一条我们都会看。', 'Алдық, рақмет! Әрқайсысын оқимыз.',
            'Получили, спасибо! Читаем каждое.'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    final empty = text.text.trim().isEmpty;
    return PageScaffold(
        title: tr3('意见反馈', 'Пікір қалдыру', 'Обратная связь'),
        bottom: Column(mainAxisSize: MainAxisSize.min, children: [
          if (error != null) ...[
            Hint(
                key: const Key('feedback-error'),
                tr3('没发出去：$error。你写的内容还在，可以再试一次。',
                    'Жіберілмеді: $error. Мәтін сақталды, қайталап көріңіз.',
                    'Не отправлено: $error. Текст сохранён, попробуйте ещё раз.'),
                warn: true),
            const SizedBox(height: YSpace.sm),
          ],
          BusyButton(
              key: const Key('feedback-send'),
              label: error == null
                  ? tr3('发送', 'Жіберу', 'Отправить')
                  : tr3('重试', 'Қайталау', 'Повторить'),
              onPressed: empty ? null : send),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              key: const Key('feedback-text'),
              controller: text,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              maxLength: maxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  hintText: tr3(
                      '哪里不好用、想要什么功能，直接写就行',
                      'Не ыңғайсыз, не қосу керек, жаза беріңіз',
                      'Что неудобно, чего не хватает: просто напишите'))),
          const SizedBox(height: YSpace.md),
          FutureBuilder<Map<String, String>>(
              future: details,
              builder: (context, snap) {
                final d = snap.data ?? const {};
                final summary = [
                  if (d['app_version'] != null) 'Yusal ${d['app_version']}',
                  d['device'],
                  d['os_version'],
                  switch (d['language']) {
                    'zh' => '中文',
                    'kk' => 'Қазақша',
                    'ru' => 'Русский',
                    final l => l,
                  },
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
                return SwitchListTile(
                    key: const Key('feedback-attach'),
                    contentPadding: EdgeInsets.zero,
                    value: attach,
                    onChanged: (v) => setState(() => attach = v),
                    title: Text(
                        tr3('附带设备信息', 'Құрылғы туралы мәлімет қосу',
                            'Приложить данные устройства'),
                        style: YText.bodyStrong),
                    subtitle: Text(
                        summary.isEmpty
                            ? tr3('应用版本、设备型号、系统版本和语言',
                                'Нұсқа, құрылғы, жүйе және тіл',
                                'Версия, устройство, система и язык')
                            : summary,
                        style: YText.caption.copyWith(color: t.muted)));
              }),
          Text(
              tr3('帮我们更快找到问题。你的设计不会被附带。',
                  'Мәселені тез табуға көмектеседі. Жобаларыңыз жіберілмейді.',
                  'Помогает быстрее найти проблему. Ваши проекты не передаются.'),
              style: YText.caption.copyWith(color: t.muted)),
        ]));
  }
}
