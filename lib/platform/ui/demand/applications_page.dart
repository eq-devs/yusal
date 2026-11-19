import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../chat/chat_page.dart';
import '../coop/agreement_form.dart';
import '../l10n.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../components.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare_page.dart';
import 'demand_detail_page.dart';

class _AppsData {
  _AppsData(this.demand, this.apps, this.profiles, this.coops);
  final Demand demand;
  final List<Application> apps;
  final Map<String, ServiceProfile?> profiles;
  final List<Cooperation> coops;
}

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
    AppScope.watch(context);
    return Live<_AppsData>(
        load: (r) async {
          final d = (await r.demand(widget.demandId))!;
          final (apps, coops) =
              await (r.applicationsFor(d.id), r.cooperationsFor(d.id)).wait;
          final profiles =
              await Future.wait([for (final a in apps) r.profile(a.profileId)]);
          return _AppsData(
              d,
              apps,
              {for (final (i, a) in apps.indexed) a.profileId: profiles[i]},
              coops);
        },
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
                  ? tr3('报名管理', 'Өтінімдер', 'Отклики')
                  : tr3('报价管理', 'Ұсыныстар', 'Предложения'),
              body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.current.title,
                        style: const TextStyle(
                            fontSize: YFont.title, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '${demandStatusName(d.status)} · ${tr3('第 ${d.current.no} 版', '${d.current.no}-нұсқа', 'версия ${d.current.no}')}',
                        style: TextStyle(color: YTokens.of(context).muted)),
                    if (hire && d.current.hire != null) ...[
                      const SizedBox(height: 12),
                      Hint(tr3(
                          '已录用 ${hiredCount(data.coops)} / ${d.current.hire!.headcount} 人。录用后仍可继续招人。',
                          'Жалданды ${hiredCount(data.coops)} / ${d.current.hire!.headcount}.',
                          'Нанято ${hiredCount(data.coops)} из ${d.current.hire!.headcount}.')),
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
                              'Сравнить ${quotes.length} предложения'))),
                    ],
                    const SizedBox(height: 16),
                    if (live.isEmpty)
                      EmptyState(
                          icon: Icons.hourglass_empty,
                          title: tr3('还没有人报名或报价', 'Әзірге өтінім жоқ',
                              'Пока нет откликов'),
                          body: tr3(
                              '可以分享需求，邀请认识的师傅来看。',
                              'Тапсырыспен бөлісіңіз.',
                              'Поделитесь заявкой со знакомыми мастерами.')),
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
                              'Отозванные / не выбранные (${closed.length})'))),
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
    final repos = context.repos;
    final name = profile?.name ?? tr3('已注销用户', 'Жойылған', 'Удалён');
    final hire = demand.type == DemandType.hire;
    final lines = <String>[
      if (hire) ...[
        '${tr3('可到岗', 'Келе алады', 'Может с')}: ${fmtDay(v.availableFrom)}',
        v.acceptsOffer
            ? tr3(
                '接受原工资条件', 'Ұсынылған жалақыға келіседі', 'Согласен на ставку')
            : '${tr3('期望工资', 'Күтетін жалақы', 'Ожидает')}: ${money(v.expectedWage, unit: demand.current.hire?.wageUnit ?? 'day')}',
        if (v.headcountOffered > 1)
          tr3('可提供 ${v.headcountOffered} 人', '${v.headcountOffered} адам',
              '${v.headcountOffered} чел.'),
      ] else ...[
        '${pricingName(v.pricing)} · ${materialName(v.materials)}',
        '${tr3('价格', 'Баға', 'Цена')}: ${v.total == null ? tr3('现场确认后报价', 'Орында нақтыланады', 'После замера') : money(v.total)}',
        if (v.durationDays != null)
          tr3('工期 ${v.durationDays} 天', '${v.durationDays} күн',
              '${v.durationDays} дн.'),
        if (v.scopeText.isNotEmpty)
          '${tr3('范围', 'Көлемі', 'Объём')}: ${v.scopeText}',
        if (v.excludes.isNotEmpty)
          '${tr3('不包含', 'Кірмейді', 'Не входит')}: ${v.excludes}',
      ],
      if (v.note.isNotEmpty) v.note,
    ];

    Future<void> chat() async {
      final conv = await attempt(context,
          () => repos.openConversation(a.applicantId, demandId: demand.id));
      if (conv != null && context.mounted)
        await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
    }

    Future<void> invite() async {
      final terms = await pushPage<Agreement>(
          context, (_) => AgreementForm(demand: demand, application: a));
      if (terms == null || !context.mounted) return;
      await attempt(context, () => repos.invite(a.id, terms),
          success: tr3(
              '已发起合作约定，等待对方确认', 'Келісім жіберілді', 'Соглашение отправлено'));
    }

    return YCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
          onTap: profile == null
              ? null
              : () => pushPage<void>(
                  context, (_) => ProfilePage(profileId: profile!.id)),
          child: Row(children: [
            Avatar(name, size: 40, team: profile?.kind == ProfileKind.team),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: YFont.body)),
                  Text(
                      '${ago(v.createdAt, context.now)} · ${tr3('基于第 ${v.demandVersionNo} 版', '${v.demandVersionNo}-нұсқа', 'к версии ${v.demandVersionNo}')}${a.versions.length > 1 ? ' · ${tr3('已修改 ${a.versions.length - 1} 次', 'өзгертілді', 'изменено')}' : ''}',
                      style: TextStyle(color: t.muted, fontSize: YFont.caption)),
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
                'Заявка изменилась; отклик основан на старой версии.'),
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
            label: Text(tr3('沟通', 'Жазу', 'Написать'))),
        if (a.status == ApplicationStatus.submitted) ...[
          FilledButton(
              onPressed: invite,
              child: Text(hire
                  ? tr3('录用并发起约定', 'Жалдау', 'Нанять')
                  : tr3('选择并发起约定', 'Таңдау', 'Выбрать'))),
          TextButton(
              onPressed: () =>
                  attempt(context, () => repos.markNotSelected(a.id)),
              child: Text(tr3('不选用', 'Таңдамау', 'Отклонить'))),
        ],
        if (coop != null)
          FilledButton.tonal(
              onPressed: () => openCooperation(context, coop!.id),
              child: Text(coop!.status == CooperationStatus.pending
                  ? tr3('查看约定（待对方确认）', 'Келісім (күтуде)', 'Соглашение (ждёт)')
                  : tr3('查看合作', 'Келісімді көру', 'Сотрудничество'))),
      ]),
    ]));
  }
}
