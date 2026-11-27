import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/routes.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/houses/state/my_jobs.dart';
import 'package:yusal/features/coop/widgets/site_tab.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// "我接的活": everything I signed up for or quoted, and the work I'm doing,
/// grouped by what needs me now.
class MyJobsView extends StatelessWidget {
  const MyJobsView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<MyJobs>(
        provider: myJobsProvider,
        builder: (context, j) {
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
          if (waiting.isEmpty &&
              working.isEmpty &&
              sent.isEmpty &&
              ended.isEmpty) {
            return EmptyState(
                icon: YIcons.hire,
                title: tr3('还没有接活', 'Әзірге жұмыс жоқ', 'Пока нет работы', 'No work yet', ky: 'Азырынча иш жок', uz: 'Hozircha ish yoʻq'),
                body: tr3(
                    '去“发现 · 找活”看看附近在招的房子。',
                    '«Шолу · Жұмыс» бөлімін қараңыз.',
                    'Загляните в «Обзор · Работа».',
                    'Have a look in “Discover · Jobs”.', ky: '«Ачылыштар · Иштер» бөлүмүн карап көрүңүз.', uz: '“Kashf qilish · Ishlar” boʻlimini koʻrib chiqing.'));
          }
          Widget group(String title, List<_Item> items, {bool hot = false}) =>
              items.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          Padding(
                              padding:
                                  const EdgeInsets.only(top: 16, bottom: 8),
                              child: Text('$title · ${items.length}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: hot ? t.accent : t.ink))),
                          for (final i in items) _JobCard(item: i, jobs: j),
                        ]);
          return ListView(
              padding: EdgeInsets.fromLTRB(
                  20, 4, 20, 40 + MediaQuery.paddingOf(context).bottom),
              children: [
                group(tr3('待处理', 'Күтуде', 'Ждут вас', 'Waiting for you', ky: 'Сизди күтүүдө', uz: 'Sizni kutmoqda'), waiting, hot: true),
                group(tr3('进行中', 'Жүріп жатыр', 'В работе', 'In progress', ky: 'Аткарылууда', uz: 'Jarayonda'), working),
                group(tr3('已报名 / 已报价', 'Жіберілді', 'Отправлено', 'Sent', ky: 'Жөнөтүлдү', uz: 'Yuborildi'), sent),
                group(tr3('已结束', 'Аяқталды', 'Завершено', 'Finished', ky: 'Бүттү', uz: 'Tugallandi'), ended),
              ]);
        });
  }
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
  final MyJobs jobs;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = item.coop;
    final a = item.app;
    final title = jobs.titles[item.demandId] ?? '';
    final String status;
    if (c != null) {
      final next = c.milestones
          .where((m) => m.status != MilestoneStatus.accepted)
          .firstOrNull;
      final me = context.session.currentAccount?.id;
      status = c.endPhase == EndPhase.asked
          ? c.endRequest!.by == me
              ? tr3('已请求结束，等业主确认', 'Аяқтау сұралды',
                  'Ждём подтверждения завершения',
                  'Waiting for completion to be confirmed', ky: 'Бүтүрүүнүн ырасталышын күтүүдө', uz: 'Yakunlash tasdiqlanishi kutilmoqda')
              : tr3('业主请求结束，等你确认', 'Иесі аяқтауды сұрады',
                  'Заказчик просит завершить',
                  'The client asks to finish', ky: 'Кардар бүтүрүүнү сурап жатат', uz: 'Mijoz yakunlashni soʻramoqda')
          : c.status == CooperationStatus.confirmed && next != null
              ? tr3(
                  '${milestoneName(next.key)}进行中 · 已记工 ${c.workLogs.length} 天',
                  '${milestoneName(next.key)} · ${c.workLogs.length} күн',
                  '${milestoneName(next.key)} · ${c.workLogs.length} дн.',
                  '${milestoneName(next.key)} · ${c.workLogs.length} d', ky: '${milestoneName(next.key)} · ${c.workLogs.length} к', uz: '${milestoneName(next.key)} · ${c.workLogs.length} k')
              : cooperationStatusName(c);
    } else {
      status = a!.needsReconfirm
          ? tr3('需求已修改，待重新确认报价', 'Тапсырыс өзгерді', 'Заявка изменилась', 'The request changed', ky: 'Суроо-талап өзгөрдү', uz: 'Soʻrov oʻzgardi')
          : [
              applicationStatusName(a.status),
              if (a.current.total != null)
                tr3(
                    '报价 ${money(a.current.total!.round())}',
                    'Ұсыныс ${money(a.current.total!.round())}',
                    'Цена ${money(a.current.total!.round())}',
                    'Price ${money(a.current.total!.round())}', ky: 'Баасы ${money(a.current.total!.round())}', uz: 'Narxi ${money(a.current.total!.round())}')
              else if (a.current.expectedWage != null)
                tr3(
                    '期望 ${money(a.current.expectedWage)} / 天',
                    '${money(a.current.expectedWage)} / күн',
                    '${money(a.current.expectedWage)} / день',
                    '${money(a.current.expectedWage)} / day', ky: '${money(a.current.expectedWage)} / күн', uz: '${money(a.current.expectedWage)} / kun'),
              if (a.status == ApplicationStatus.submitted)
                a.readByOwner
                    ? tr3('业主已看', 'Көрді', 'Просмотрено', 'Viewed', ky: 'Каралды', uz: 'Koʻrildi')
                    : tr3('业主未看', 'Әлі көрмеді', 'Не просмотрено', 'Not viewed', ky: 'Каралган жок', uz: 'Koʻrilmagan'),
            ].join(' · ');
    }
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
            borderRadius: BorderRadius.circular(yRadius),
            onTap: () => pushPage<void>(
                context,
                (_) => c != null
                    ? pageFor(ToCooperation(c.id))
                    : pageFor(ToDemand(a!.demandId))),
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          title.isEmpty
                              ? tr3(
                                  '需求已不可见', 'Қолжетімсіз', 'Заявка недоступна', 'Request unavailable', ky: 'Суроо-талап жеткиликсиз', uz: 'Soʻrov mavjud emas')
                              : title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: YFont.body)),
                      const SizedBox(height: 2),
                      Text(status, style: TextStyle(color: t.muted)),
                      if (c != null && c.status == CooperationStatus.confirmed)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              FilledButton.tonalIcon(
                                  onPressed: onLogToday(context, c),
                                  icon: const Icon(
                                      YIcons.calendarCheck,
                                      size: 18),
                                  label: Text(logTodayLabel(c))),
                              if (c.milestones.isNotEmpty)
                                OutlinedButton(
                                    onPressed: () => pushPage<void>(context,
                                        (_) => SitePage(cooperationId: c.id)),
                                    child: Text(tr3('申请验收', 'Қабылдауды сұрау',
                                        'Попросить приёмку',
                                        'Ask for acceptance', ky: 'Кабыл алууну суроо', uz: 'Qabul qilishni soʻrash'))),
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
      provider: siteCooperationProvider(cooperationId),
      loading: const SkeletonPage(),
      builder: (context, c) => PageScaffold(
          title: tr3('施工', 'Құрылыс', 'Стройка', 'Build', ky: 'Курулуш', uz: 'Qurilish'),
          body: c == null
              ? EmptyState(
                  icon: YIcons.lock,
                  title: tr3('无法查看', 'Қолжетімсіз', 'Недоступно', 'Unavailable', ky: 'Жеткиликсиз', uz: 'Mavjud emas'))
              : SiteSection(cooperation: c)));
}
