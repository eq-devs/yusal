import 'package:flutter/material.dart';
import 'package:yusal/features/demand/state/demand.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';
import 'package:yusal/features/chat/page.dart';
import 'package:yusal/features/coop/widgets/agreement_form.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/profile/page.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/demand/pages/compare.dart';
import 'package:yusal/features/demand/page.dart';

/// The publisher's list of sign-ups or quotes: talk, invite to cooperate,
/// decline, compare.
class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key, required this.demandId});
  final String demandId;
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  bool showClosed = false;

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Live<ApplicationsData>(
        provider: applicationsProvider(widget.demandId),
        loading: const SkeletonPage(avatar: true),
        builder: (context, data) {
          final d = data.demand;
          final hire = d.type == DemandType.hire;
          final live = data.apps
              .where((a) => liveApplicationStatuses.contains(a.status))
              .toList();
          final closed = data.apps
              .where((a) => !liveApplicationStatuses.contains(a.status))
              .toList();
          final quotes = live
              .where((a) => a.status != ApplicationStatus.cooperating)
              .toList();
          return PageScaffold(
              title: hire
                  ? tr3('报名管理', 'Өтінімдер', 'Отклики', 'Responses', ky: 'Жооптор', uz: 'Javoblar')
                  : tr3('报价管理', 'Ұсыныстар', 'Предложения', 'Quotes', ky: 'Сунуштар', uz: 'Takliflar'),
              body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.current.title,
                        style: const TextStyle(
                            fontSize: YFont.title,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '${demandStatusName(d.status)} · ${tr3('第 ${d.current.no} 版', '${d.current.no}-нұсқа', 'версия ${d.current.no}', 'version ${d.current.no}', ky: '${d.current.no}-версия', uz: '${d.current.no}-versiya')}',
                        style: TextStyle(color: YTokens.of(context).muted)),
                    if (hire && d.current.hire != null) ...[
                      const SizedBox(height: 12),
                      Hint(tr3(
                          '已录用 ${hiredCount(data.coops)} / ${d.current.hire!.headcount} 人。录用后仍可继续招人。',
                          'Жалданды ${hiredCount(data.coops)} / ${d.current.hire!.headcount}.',
                          'Нанято ${hiredCount(data.coops)} из ${d.current.hire!.headcount}.',
                          'Hired ${hiredCount(data.coops)} of ${d.current.hire!.headcount}.', ky: '${d.current.hire!.headcount} ичинен ${hiredCount(data.coops)} жалданды.', uz: '${d.current.hire!.headcount} dan ${hiredCount(data.coops)} yollandi.')),
                    ],
                    if (!hire && quotes.length >= 2) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                          onPressed: () => pushPage<void>(
                              context,
                              (_) => ComparePage(
                                  demand: d,
                                  quotes: quotes,
                                  profiles: data.profiles)),
                          icon: const Icon(Icons.compare_arrows),
                          label: Text(tr3(
                              '对比 ${quotes.length} 份报价',
                              '${quotes.length} ұсынысты салыстыру',
                              'Сравнить ${quotes.length} предложения',
                              'Compare ${quotes.length} quotes', ky: '${quotes.length} сунушту салыштыруу', uz: '${quotes.length} ta taklifni solishtirish'))),
                    ],
                    const SizedBox(height: 16),
                    if (live.isEmpty)
                      EmptyState(
                          icon: Icons.hourglass_empty,
                          title: tr3('还没有人报名或报价', 'Әзірге өтінім жоқ',
                              'Пока нет откликов',
                              'No responses yet', ky: 'Азырынча жооп жок', uz: 'Hozircha javob yoʻq'),
                          body: tr3(
                              '可以分享需求，邀请认识的师傅来看。',
                              'Тапсырыспен бөлісіңіз.',
                              'Поделитесь заявкой со знакомыми мастерами.',
                              'Share the request with pros you know.', ky: 'Суроо-талапты тааныш адистер менен бөлүшүңүз.', uz: 'Soʻrovni tanish mutaxassislar bilan ulashing.')),
                    for (final a in live)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ApplicationCard(
                              demand: d,
                              application: a,
                              profile: data.profiles[a.profileId],
                              coop: data.coops
                                  .where((c) =>
                                      c.applicationId == a.id &&
                                      c.status != CooperationStatus.notFormed)
                                  .lastOrNull)),
                    if (closed.isNotEmpty)
                      TextButton(
                          onPressed: () =>
                              setState(() => showClosed = !showClosed),
                          child: Text(tr3(
                              '已撤回／未选用（${closed.length}）',
                              'Жабылғандар (${closed.length})',
                              'Отозванные / не выбранные (${closed.length})',
                              'Withdrawn / not chosen (${closed.length})', ky: 'Кайтарылып алынды / тандалган жок (${closed.length})', uz: 'Qaytarib olingan / tanlanmagan (${closed.length})'))),
                    if (showClosed)
                      for (final a in closed)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ApplicationCard(
                                demand: d,
                                application: a,
                                profile: data.profiles[a.profileId])),
                  ]));
        });
  }
}

/// Summary of one sign-up or quote with the publisher's actions.
class ApplicationCard extends StatelessWidget {
  const ApplicationCard(
      {super.key,
      required this.demand,
      required this.application,
      required this.profile,
      this.coop});
  final Demand demand;
  final Application application;
  final ServiceProfile? profile;
  final Cooperation? coop;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final a = application;
    final v = a.current;
    final name = profile?.name ?? tr3('已注销用户', 'Жойылған', 'Удалён', 'Deleted', ky: 'Өчүрүлгөн', uz: 'Oʻchirilgan');
    final hire = demand.type == DemandType.hire;
    final lines = <String>[
      if (hire) ...[
        '${tr3('可到岗', 'Келе алады', 'Может с', 'Available from', ky: 'Качантан бош', uz: 'Qachondan boʻsh')}: ${fmtDay(v.availableFrom)}',
        v.acceptsOffer
            ? tr3(
                '接受原工资条件', 'Ұсынылған жалақыға келіседі', 'Согласен на ставку', 'Agrees to the rate', ky: 'Акыга макул', uz: 'Haqqa rozi')
            : '${tr3('期望工资', 'Күтетін жалақы', 'Ожидает', 'Pending', ky: 'Күтүүдө', uz: 'Kutilmoqda')}: ${money(v.expectedWage, unit: demand.current.hire?.wageUnit ?? 'day')}',
        if (v.headcountOffered > 1)
          tr3('可提供 ${v.headcountOffered} 人', '${v.headcountOffered} адам',
              '${v.headcountOffered} чел.',
              '${v.headcountOffered} people', ky: '${v.headcountOffered} адам', uz: '${v.headcountOffered} kishi'),
      ] else ...[
        '${pricingName(v.pricing)} · ${materialName(v.materials)}',
        '${tr3('价格', 'Баға', 'Цена', 'Price', ky: 'Баасы', uz: 'Narxi')}: ${v.total == null ? tr3('现场确认后报价', 'Орында нақтыланады', 'После замера', 'After site measure', ky: 'Объектиде өлчөгөндөн кийин', uz: 'Obyektda oʻlchagandan keyin') : money(v.total)}',
        if (v.durationDays != null)
          tr3('工期 ${v.durationDays} 天', '${v.durationDays} күн',
              '${v.durationDays} дн.',
              '${v.durationDays} d', ky: '${v.durationDays} к', uz: '${v.durationDays} k'),
        if (v.scopeText.isNotEmpty)
          '${tr3('范围', 'Көлемі', 'Объём', 'Scope', ky: 'Иштин көлөмү', uz: 'Ish hajmi')}: ${v.scopeText}',
        if (v.excludes.isNotEmpty)
          '${tr3('不包含', 'Кірмейді', 'Не входит', 'Not included', ky: 'Кирбейт', uz: 'Kirmaydi')}: ${v.excludes}',
      ],
      if (v.note.isNotEmpty) v.note,
    ];

    Future<void> chat() async {
      final conv = await attempt(
          context,
          () => context
              .read(chatRepositoryProvider)
              .openConversation(a.applicantId, demandId: demand.id));
      if (conv != null && context.mounted) {
        await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
      }
    }

    Future<void> invite() async {
      final terms = await pushPage<Agreement>(
          context, (_) => AgreementForm(demand: demand, application: a));
      if (terms == null || !context.mounted) return;
      await attempt(context,
          () => context.read(cooperationRepositoryProvider).invite(a.id, terms),
          success: tr3(
              '已发起合作约定，等待对方确认', 'Келісім жіберілді', 'Соглашение отправлено', 'Agreement sent', ky: 'Макулдашуу жөнөтүлдү', uz: 'Kelishuv yuborildi'));
    }

    return YCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
          onTap: profile == null
              ? null
              : () => pushPage<void>(
                  context, (_) => ProfilePage(profileId: profile!.id)),
          child: Row(children: [
            Avatar(name, team: profile?.kind == ProfileKind.team),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: YFont.body)),
                  Text(
                      '${ago(v.createdAt, context.now)} · ${tr3('基于第 ${v.demandVersionNo} 版', '${v.demandVersionNo}-нұсқа', 'к версии ${v.demandVersionNo}', 'for version ${v.demandVersionNo}', ky: '${v.demandVersionNo}-версия үчүн', uz: '${v.demandVersionNo}-versiya uchun')}${a.versions.length > 1 ? ' · ${tr3('已修改 ${a.versions.length - 1} 次', 'өзгертілді', 'изменено', 'changed', ky: 'өзгөрдү', uz: 'oʻzgardi')}' : ''}',
                      style:
                          TextStyle(color: t.muted, fontSize: YFont.caption)),
                ])),
            StatusPill(applicationStatusName(a.status),
                color: a.status == ApplicationStatus.cooperating ? t.ok : null),
          ])),
      if (a.needsReconfirm) ...[
        const SizedBox(height: 10),
        Hint(
            tr3(
                '需求已修改，这份${hire ? '报名' : '报价'}基于旧版本，待对方重新确认。',
                'Тапсырыс өзгерді, бұл ұсыныс ескі нұсқаға негізделген.',
                'Заявка изменилась; отклик основан на старой версии.',
                'The request changed; this response is based on an old version.', ky: 'Суроо-талап өзгөрдү; бул жооп эски версияга негизделген.', uz: 'Soʻrov oʻzgardi; bu javob eski versiyaga asoslangan.'),
            warn: true),
      ],
      const SizedBox(height: 10),
      for (final l in lines)
        Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(l, style: const TextStyle(fontSize: YFont.label))),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: chat,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(tr3('沟通', 'Жазу', 'Написать', 'Message', ky: 'Билдирүү', uz: 'Xabar'))),
        if (a.status == ApplicationStatus.submitted) ...[
          FilledButton(
              onPressed: invite,
              child: Text(hire
                  ? tr3('录用并发起约定', 'Жалдау', 'Нанять', 'Hire', ky: 'Жалдоо', uz: 'Yollash')
                  : tr3('选择并发起约定', 'Таңдау', 'Выбрать', 'Choose', ky: 'Тандоо', uz: 'Tanlash'))),
          TextButton(
              onPressed: () => attempt(
                  context,
                  () => context
                      .read(applicationRepositoryProvider)
                      .markNotSelected(a.id)),
              child: Text(tr3('不选用', 'Таңдамау', 'Отклонить', 'Decline', ky: 'Баш тартуу', uz: 'Rad etish'))),
        ],
        if (coop != null)
          FilledButton.tonal(
              onPressed: () => openCooperation(context, coop!.id),
              child: Text(coop!.status == CooperationStatus.pending
                  ? tr3('查看约定（待对方确认）', 'Келісім (күтуде)', 'Соглашение (ждёт)', 'Agreement (pending)', ky: 'Макулдашуу (күтүүдө)', uz: 'Kelishuv (kutilmoqda)')
                  : tr3('查看合作', 'Келісімді көру', 'Сотрудничество', 'Cooperation', ky: 'Кызматташуу', uz: 'Hamkorlik'))),
      ]),
    ]));
  }
}
