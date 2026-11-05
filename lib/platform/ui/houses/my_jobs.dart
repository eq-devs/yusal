import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../coop/coop_page.dart';
import '../demand/demand_detail_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'site_tab.dart';

/// "我接的活": everything I signed up for or quoted, and the work I'm doing,
/// grouped by what needs me now.
class MyJobsView extends StatelessWidget {
  const MyJobsView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<_Jobs>(load: (r) async {
      final me = r.currentAccount!.id;
      final apps = await r.myApplications();
      final coops =
          (await r.myCooperations()).where((c) => c.providerId == me).toList();
      final titles = <String, String>{};
      for (final id in {
        ...apps.map((a) => a.demandId),
        ...coops.map((c) => c.demandId)
      }) {
        try {
          titles[id] = (await r.demand(id))?.current.title ?? '';
        } catch (_) {
          titles[id] = '';
        }
      }
      return _Jobs(me, apps, coops, titles);
    }, builder: (context, j) {
      final waiting = [
        for (final c in j.coops)
          if (c.status == CooperationStatus.pending &&
              !c.agreement.confirmedBy.contains(j.me))
            _Item.coop(c),
        for (final a in j.apps)
          if (a.needsReconfirm && a.status == ApplicationStatus.submitted)
            _Item.app(a),
      ];
      final working = [
        for (final c in j.coops)
          if (c.status == CooperationStatus.confirmed) _Item.coop(c)
      ];
      final sent = [
        for (final a in j.apps)
          if (a.status == ApplicationStatus.submitted && !a.needsReconfirm)
            _Item.app(a)
      ];
      final ended = [
        for (final c in j.coops)
          if (c.status == CooperationStatus.ended) _Item.coop(c)
      ];
      if (waiting.isEmpty && working.isEmpty && sent.isEmpty && ended.isEmpty)
        return EmptyState(
            icon: Icons.work_outline,
            title: tr3('还没有接活', 'Әзірге жұмыс жоқ', 'Пока нет работы'),
            body: tr3('去“发现 · 找活”看看附近在招的房子。', '«Шолу · Жұмыс» бөлімін қараңыз.',
                'Загляните в «Обзор · Работа».'));
      Widget group(String title, List<_Item> items, {bool hot = false}) => items
              .isEmpty
          ? const SizedBox.shrink()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Text('$title · ${items.length}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: hot ? t.accent : t.ink))),
              for (final i in items) _JobCard(item: i, jobs: j),
            ]);
      return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            group(tr3('待处理', 'Күтуде', 'Ждут вас'), waiting, hot: true),
            group(tr3('进行中', 'Жүріп жатыр', 'В работе'), working),
            group(tr3('已报名 / 已报价', 'Жіберілді', 'Отправлено'), sent),
            group(tr3('已结束', 'Аяқталды', 'Завершено'), ended),
          ]);
    });
  }
}

class _Jobs {
  _Jobs(this.me, this.apps, this.coops, this.titles);
  final String me;
  final List<Application> apps;
  final List<Cooperation> coops;
  final Map<String, String> titles;
}

class _Item {
  _Item.coop(Cooperation this.coop) : app = null;
  _Item.app(Application this.app) : coop = null;
  final Cooperation? coop;
  final Application? app;
  String get demandId => coop?.demandId ?? app!.demandId;
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.item, required this.jobs});
  final _Item item;
  final _Jobs jobs;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = item.coop, a = item.app;
    final title = jobs.titles[item.demandId] ?? '';
    final String status;
    if (c != null) {
      final next = c.milestones
          .where((m) => m.status != MilestoneStatus.accepted)
          .firstOrNull;
      final me = context.repos.currentAccount?.id;
      final asked = c.status == CooperationStatus.confirmed &&
          c.endRequest != null &&
          c.endRequest!.dispute == null;
      status = asked
          ? c.endRequest!.by == me
              ? tr3('已请求结束，等业主确认', 'Аяқтау сұралды',
                  'Ждём подтверждения завершения')
              : tr3('业主请求结束，等你确认', 'Иесі аяқтауды сұрады',
                  'Заказчик просит завершить')
          : c.status == CooperationStatus.confirmed && next != null
              ? tr3(
                  '${milestoneName(next.key)}进行中 · 已记工 ${c.workLogs.length} 天',
                  '${milestoneName(next.key)} · ${c.workLogs.length} күн',
                  '${milestoneName(next.key)} · ${c.workLogs.length} дн.')
              : cooperationStatusName(c);
    } else {
      status = a!.needsReconfirm
          ? tr3('需求已修改，待重新确认报价', 'Тапсырыс өзгерді', 'Заявка изменилась')
          : [
              applicationStatusName(a.status),
              if (a.current.total != null)
                tr3(
                    '报价 ${money(a.current.total!.round())}',
                    'Ұсыныс ${money(a.current.total!.round())}',
                    'Цена ${money(a.current.total!.round())}')
              else if (a.current.expectedWage != null)
                tr3(
                    '期望 ${money(a.current.expectedWage!)} / 天',
                    '${money(a.current.expectedWage!)} / күн',
                    '${money(a.current.expectedWage!)} / день'),
              if (a.status == ApplicationStatus.submitted)
                a.readByOwner
                    ? tr3('业主已看', 'Көрді', 'Просмотрено')
                    : tr3('业主未看', 'Әлі көрмеді', 'Не просмотрено'),
            ].join(' · ');
    }
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
            borderRadius: BorderRadius.circular(yRadius),
            onTap: () => pushPage<void>(
                context,
                (_) => c != null
                    ? CooperationPage(cooperationId: c.id)
                    : DemandDetailPage(demandId: a!.demandId)),
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          title.isEmpty
                              ? tr3(
                                  '需求已不可见', 'Қолжетімсіз', 'Заявка недоступна')
                              : title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(status, style: TextStyle(color: t.muted)),
                      if (c != null && c.status == CooperationStatus.confirmed)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              FilledButton.tonalIcon(
                                  onPressed: () => logToday(context, c),
                                  icon: const Icon(
                                      Icons.event_available_outlined,
                                      size: 18),
                                  label: Text(tr3('今天记工', 'Бүгінді жазу',
                                      'Отметить день'))),
                              if (c.milestones.isNotEmpty)
                                OutlinedButton(
                                    onPressed: () => pushPage<void>(context,
                                        (_) => SitePage(cooperationId: c.id)),
                                    child: Text(tr3('申请验收', 'Қабылдауды сұрау',
                                        'Попросить приёмку'))),
                            ])),
                    ]))));
  }
}

/// One cooperation's site: milestones and work log, for either side.
class SitePage extends StatelessWidget {
  const SitePage({super.key, required this.cooperationId});
  final String cooperationId;
  @override
  Widget build(BuildContext context) => Live<Cooperation?>(
      reloadKey: cooperationId,
      load: (r) => r.cooperation(cooperationId),
      builder: (context, c) => PageScaffold(
          title: tr3('施工', 'Құрылыс', 'Стройка'),
          body: c == null
              ? EmptyState(
                  icon: Icons.lock_outline,
                  title: tr3('无法查看', 'Қолжетімсіз', 'Недоступно'))
              : SiteSection(cooperation: c)));
}
