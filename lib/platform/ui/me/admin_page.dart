import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../demand/demand_detail_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Minimal moderation back office: demand review, reports and the audit
/// log. Every decision records who, when and why.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return DefaultTabController(
        length: 3,
        child: Scaffold(
            appBar: AppBar(
                title: Text(tr3('审核后台', 'Модерация', 'Модерация')),
                bottom: TabBar(tabs: [
                  Tab(text: tr3('待审核', 'Күтуде', 'На проверке')),
                  Tab(text: tr3('举报', 'Шағымдар', 'Жалобы')),
                  Tab(text: tr3('操作记录', 'Журнал', 'Журнал')),
                ])),
            body:
                const TabBarView(children: [_Queue(), _Reports(), _Audit()])));
  }
}

class _Queue extends StatelessWidget {
  const _Queue();
  @override
  Widget build(BuildContext context) => Live<List<Demand>>(
      load: (r) => r.reviewQueue(),
      builder: (context, list) =>
          ListView(padding: const EdgeInsets.all(20), children: [
            if (list.isEmpty)
              EmptyState(
                  icon: Icons.task_alt,
                  title: tr3('没有待审核的需求', 'Бос', 'Очередь пуста')),
            for (final d in list)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: YCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        InkWell(
                            onTap: () => pushPage<void>(context,
                                (_) => DemandDetailPage(demandId: d.id)),
                            child: Text(d.current.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16))),
                        Text(d.current.description,
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, children: [
                          FilledButton(
                              onPressed: () => attempt(
                                  context, () => context.repos.approve(d.id)),
                              child: Text(tr3('通过', 'Мақұлдау', 'Одобрить'))),
                          OutlinedButton(
                              onPressed: () async {
                                final reason = await askText(
                                    context, tr3('拒绝原因', 'Себебі', 'Причина'));
                                if (reason != null && context.mounted)
                                  await attempt(context,
                                      () => context.repos.reject(d.id, reason));
                              },
                              child:
                                  Text(tr3('拒绝', 'Қабылдамау', 'Отклонить'))),
                        ]),
                      ]))),
          ]));
}

class _Reports extends StatelessWidget {
  const _Reports();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<Report>>(
        load: (r) => r.reports(),
        builder: (context, list) =>
            ListView(padding: const EdgeInsets.all(20), children: [
              if (list.isEmpty)
                EmptyState(
                    icon: Icons.flag_outlined,
                    title: tr3('没有举报', 'Бос', 'Жалоб нет')),
              for (final r in list)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: YCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${r.target.name} · ${r.targetId}',
                              style: TextStyle(color: t.muted, fontSize: 12)),
                          Text(r.reason,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                              tr3('举报不等于事实成立，请核实后处理。', 'Тексеріп шешіңіз.',
                                  'Жалоба — не доказательство; проверьте.'),
                              style: TextStyle(color: t.muted, fontSize: 12)),
                          const SizedBox(height: 8),
                          if (r.status == ReportStatus.open)
                            Wrap(spacing: 8, children: [
                              FilledButton(
                                  onPressed: () async {
                                    final note = await askText(
                                        context,
                                        tr3('处理说明（违规）', 'Түсініктеме',
                                            'Решение (нарушение)'));
                                    if (note != null && context.mounted)
                                      await attempt(
                                          context,
                                          () => context.repos
                                              .resolveReport(r.id, true, note));
                                  },
                                  child: Text(tr3(
                                      '核实违规并处理', 'Бұзушылық', 'Нарушение'))),
                              OutlinedButton(
                                  onPressed: () async {
                                    final note = await askText(
                                        context,
                                        tr3('驳回说明', 'Түсініктеме',
                                            'Причина отказа'));
                                    if (note != null && context.mounted)
                                      await attempt(
                                          context,
                                          () => context.repos.resolveReport(
                                              r.id, false, note));
                                  },
                                  child: Text(
                                      tr3('驳回', 'Қабылдамау', 'Отклонить'))),
                            ])
                          else
                            Text(
                                '${r.status.name} · ${r.resolution} · ${r.handledBy} · ${fmtDay(r.handledAt)}'),
                        ]))),
            ]));
  }
}

class _Audit extends StatelessWidget {
  const _Audit();
  @override
  Widget build(BuildContext context) => Live<List<AuditEntry>>(
      load: (r) => r.audit(),
      builder: (context, list) =>
          ListView(padding: const EdgeInsets.all(20), children: [
            if (list.isEmpty)
              EmptyState(
                  icon: Icons.history, title: tr3('暂无记录', 'Бос', 'Пусто')),
            for (final a in list)
              ListTile(
                  title: Text('${a.action} · ${a.targetId}'),
                  subtitle: Text(
                      '${a.by} · ${fmtDay(a.at)} ${fmtTime(a.at)} · ${a.reason}')),
          ]));
}
