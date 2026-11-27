import 'package:flutter/material.dart';
import 'package:yusal/features/demand/state/demand.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/home/widgets/plan_viewer.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Base address of public share pages (to be served by the web host).
const shareBase = 'https://yusal.app/d/';

/// Share link of a demand and a preview of what an outside visitor sees.
class SharePage extends StatelessWidget {
  const SharePage({super.key, required this.demand});
  final Demand demand;

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final t = YTokens.of(context);
    final link = '$shareBase${demand.shareToken}';
    final mine = context.session.currentAccount?.id == demand.ownerId;
    return PageScaffold(
        title: tr3('分享需求', 'Бөлісу', 'Поделиться', 'Share', ky: 'Бөлүшүү', uz: 'Ulashish'),
        body: Live<(PublicDemandView?, Demand?)>(
            provider: sharePreviewProvider((demand.id, demand.shareToken)),
            builder: (context, data) {
              final (view, current) = data;
              final revoked = current?.shareRevoked ?? false;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    YCard(
                        child: Row(children: [
                      Expanded(
                          child: SelectableText(link,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      IconButton(
                          tooltip:
                              tr3('复制链接', 'Сілтемені көшіру', 'Копировать', 'Copy', ky: 'Көчүрүү', uz: 'Nusxalash'),
                          icon: const Icon(YIcons.copy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: link));
                            if (context.mounted) {
                              toast(context,
                                  tr3('已复制', 'Көшірілді', 'Скопировано', 'Copied', ky: 'Көчүрүлдү', uz: 'Nusxalandi'));
                            }
                          }),
                    ])),
                    const SizedBox(height: 12),
                    BusyButton(
                        icon: YIcons.share,
                        label: tr3('通过其他应用分享', 'Басқа қолданбамен бөлісу',
                            'Отправить через…',
                            'Send via…', ky: 'Жөнөтүү…', uz: 'Yuborish…'),
                        onPressed: () async {
                          try {
                            await SharePlus.instance.share(ShareParams(
                                text: '${demand.current.title}\n$link'));
                          } catch (_) {
                            if (context.mounted) {
                              toast(
                                  context,
                                  tr3('此设备不支持系统分享，请复制链接', 'Сілтемені көшіріңіз',
                                      'Скопируйте ссылку',
                                      'Copy the link', ky: 'Шилтемени көчүрүү', uz: 'Havolani nusxalash'));
                            }
                          }
                        }),
                    const SizedBox(height: 8),
                    Text(
                        tr3(
                            '分享到 WhatsApp、Telegram 等应用时，对方未安装 Yusal 也能先在网页查看公开信息，登录后再报名或报价。',
                            'Yusal жоқ адам да ашық ақпаратты вебте көре алады.',
                            'Без приложения откроется веб-страница с публичными данными.',
                            'Without the app it opens a web page with the public details.', ky: 'Тиркемеси жок болсо, ачык маалыматтар менен веб-барак ачылат.', uz: 'Ilova boʻlmasa, ochiq maʼlumotlar bilan veb-sahifa ochiladi.'),
                        style:
                            TextStyle(color: t.muted, fontSize: YFont.caption)),
                    if (mine) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr3(
                              '撤销分享链接', 'Сілтемені өшіру', 'Отключить ссылку', 'Turn off the link', ky: 'Шилтемени өчүрүү', uz: 'Havolani oʻchirish')),
                          subtitle: Text(tr3(
                              '撤销后网页显示“已撤销”，不影响你的需求和备份。',
                              'Сілтеме өшеді, тапсырыс сақталады.',
                              'Ссылка перестанет работать; заявка останется.',
                              'The link stops working; the request stays.', ky: 'Шилтеме иштебей калат; суроо-талап калат.', uz: 'Havola ishlamay qoladi; soʻrov qoladi.')),
                          value: revoked,
                          onChanged: (v) => attempt(
                              context,
                              () => context
                                  .read(demandRepositoryProvider)
                                  .setShareRevoked(demand.id, v))),
                    ],
                    SectionTitle(
                        tr3('网页预览', 'Веб-көрініс', 'Как увидят по ссылке', 'How it looks from the link', ky: 'Шилтемеден кандай көрүнөт', uz: 'Havoladan qanday koʻrinadi')),
                    _PublicPreview(view: view),
                  ]);
            }));
  }
}

class _PublicPreview extends StatelessWidget {
  const _PublicPreview({required this.view});
  final PublicDemandView? view;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final v = view;
    final frame = BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(yRadius),
        boxShadow: t.softShadow,
        color: t.bg);
    if (v == null || !v.available) {
      return Container(
          decoration: frame,
          padding: const EdgeInsets.all(24),
          child: EmptyState(
              icon: Icons.link_off,
              title: tr3(
                  '此链接已撤销，或需求已关闭／下架',
                  'Сілтеме өшірілген не тапсырыс жабылған',
                  'Ссылка отключена или заявка закрыта',
                  'The link is off or the request is closed', ky: 'Шилтеме өчүк же суроо-талап жабык', uz: 'Havola oʻchiq yoki soʻrov yopiq')));
    }
    return Container(
        decoration: frame,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Yusal',
                style: TextStyle(
                    color: t.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: YFont.heading)),
            const Spacer(),
            StatusPill(demandTypeName(v.type)),
          ]),
          const SizedBox(height: 12),
          Text(v.title,
              style: const TextStyle(
                  fontSize: YFont.section, fontWeight: FontWeight.w700)),
          Text(placeText(v.region, v.locality),
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 8),
          Text(budgetText(v.budget),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(v.trades.map(tradeName).join(listSep)),
          if (v.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(v.description),
          ],
          if (v.snapshot != null) ...[
            PlanAttachment(
                snapshot: v.snapshot,
                hidden: v.snapshot?.planJson == null &&
                    v.snapshot?.preview == null),
            const SizedBox(height: 12),
            if (v.snapshot!.preview != null)
              ClipRRect(
                  borderRadius: BorderRadius.circular(YRadius.control),
                  child: Image.memory(imageBytes(v.snapshot!.preview!),
                      height: 140, fit: BoxFit.contain)),
            if (v.snapshot!.lines.isNotEmpty) QtyTable(v.snapshot!.lines),
          ],
          const SizedBox(height: 14),
          Text(
              tr3(
                  '不显示：电话、具体地址、完整设计文件。登录 Yusal 后可报名或报价。',
                  'Телефон, мекенжай, жоба файлы көрсетілмейді.',
                  'Телефон, адрес и файл проекта скрыты. Войдите, чтобы откликнуться.',
                  'Phone, address and design file are hidden. Sign in to respond.', ky: 'Телефон, дарек жана долбоор файлы жашырылган. Жооп берүү үчүн кириңиз.', uz: 'Telefon, manzil va loyiha fayli yashirilgan. Javob berish uchun kiring.'),
              style: TextStyle(color: t.muted, fontSize: YFont.caption)),
        ]));
  }
}
