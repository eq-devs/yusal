import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../cards.dart';
import '../coop/coop_page.dart';
import '../demand/applications_page.dart';
import '../demand/demand_detail_page.dart';
import '../demand/publish_page.dart';
import '../home/post_page.dart';
import '../house_progress.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'my_houses_data.dart';
import 'site_tab.dart';
import '../../../motion/motion.dart';

/// One house's workspace: where it stands, and every demand, quote and
/// cooperation for it in one place. Tabs: find people, quotes, cooperation,
/// building site.
class HouseWorkspacePage extends StatefulWidget {
  const HouseWorkspacePage(
      {super.key, required this.houseKey, this.initialTab = 0});
  final String houseKey;
  final int initialTab;
  @override
  State<HouseWorkspacePage> createState() => _HouseWorkspacePageState();
}

class _HouseWorkspacePageState extends State<HouseWorkspacePage>
    with SingleTickerProviderStateMixin {
  late final tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final store = context.projectStore;
    return Live<MyHouse?>(
        reloadKey: widget.houseKey,
        load: (r) async {
          final all = await loadMyHouses(r, store);
          for (final h in all) if (h.key == widget.houseKey) return h;
          return null;
        },
        builder: (context, h) {
          if (h == null)
            return PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.home_outlined,
                    title:
                        tr3('这栋房子还没有需求', 'Тапсырыс жоқ', 'Заявок пока нет')));
          final t = YTokens.of(context);
          final me = context.repos.currentAccount?.id ?? '';
          return Scaffold(
              appBar: AppBar(
                  title: Text(h.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: display(size: 20)),
                  actions: [
                    if (h.postId != null)
                      IconButton(
                          key: const Key('workspace-house-page'),
                          tooltip: tr3('房子页', 'Үй беті', 'Страница дома'),
                          onPressed: () => pushPage<void>(
                              context, (_) => PostPage(postId: h.postId!)),
                          icon: const Icon(Icons.public)),
                  ],
                  bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(118),
                      child: Column(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                            child: HouseProgress(
                                stage: h.stage,
                                onTap: (s) => tabs.animateTo(switch (s) {
                                      HouseStage.design ||
                                      HouseStage.finding =>
                                        0,
                                      HouseStage.building => 3,
                                      HouseStage.done => 2,
                                    }))),
                        // Scrolls: four labels with counters do not fit
                        // a phone in Russian or Kazakh.
                        TabBar(
                            controller: tabs,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            padding: const EdgeInsets.symmetric(
                                horizontal: YSpace.sm),
                            tabs: [
                              Tab(text: tr3('找人', 'Іздеу', 'Поиск')),
                              Tab(
                                  text:
                                      '${tr3('报价', 'Ұсыныстар', 'Предложения')}${h.newQuotes > 0 ? ' · ${h.newQuotes}' : ''}'),
                              Tab(
                                  text:
                                      '${tr3('合作', 'Келісім', 'Соглашения')}${h.pendingConfirm(me) > 0 ? ' · ${h.pendingConfirm(me)}' : ''}'),
                              Tab(text: tr3('施工', 'Құрылыс', 'Стройка')),
                            ]),
                      ]))),
              body: MotionTabView(controller: tabs, children: [
                _FindTab(house: h),
                _QuotesTab(house: h),
                _CoopTab(house: h),
                SiteTab(house: h),
              ]),
              backgroundColor: t.bg);
        });
  }
}

class _FindTab extends StatelessWidget {
  const _FindTab({required this.house});
  final MyHouse house;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: [
        for (final d in house.demands)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DemandCard(
                  compact: true,
                  demand: d,
                  trailing: d.status == DemandStatus.open
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: StatusPill(demandStatusName(d.status),
                              color: YTokens.of(context).ok))
                      : null,
                  onTap: () => pushPage<void>(
                      context, (_) => DemandDetailPage(demandId: d.id)))),
        OutlinedButton.icon(
            onPressed: () => pushPage<void>(
                context, (_) => PublishPage(designProjectId: house.projectId)),
            icon: const Icon(Icons.add),
            label: Text(tr3('为这栋房子再招一个阶段', 'Тағы бір кезең', 'Добавить этап'))),
      ]);
}

class _QuotesTab extends StatelessWidget {
  const _QuotesTab({required this.house});
  final MyHouse house;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final rows = [
      for (final d in house.demands)
        if ((house.quotes[d.id]?.total ?? 0) > 0) d
    ];
    if (rows.isEmpty)
      return EmptyState(
          icon: Icons.request_quote_outlined,
          title: tr3('还没有报名或报价', 'Әзірге өтінім жоқ', 'Откликов пока нет'),
          body: tr3('需求发布后，师傅的报价会按同一张工程量清单出现在这里。', 'Ұсыныстар осында шығады.',
              'Предложения появятся здесь.'));
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          for (final d in rows)
            Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(d.current.title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        tr3(
                            house.quotes[d.id]!.unread > 0
                                ? '${house.quotes[d.id]!.total} 份报价，${house.quotes[d.id]!.unread} 份新的 · 点开逐项比较'
                                : '${house.quotes[d.id]!.total} 份报价 · 点开逐项比较',
                            '${house.quotes[d.id]!.total} ұсыныс',
                            '${house.quotes[d.id]!.total} предложений, новых ${house.quotes[d.id]!.unread}'),
                        style: TextStyle(color: t.muted)),
                    trailing: house.quotes[d.id]!.unread > 0
                        ? Badge(label: Text('${house.quotes[d.id]!.unread}'))
                        : const Icon(Icons.chevron_right),
                    onTap: () => pushPage<void>(
                        context, (_) => ApplicationsPage(demandId: d.id)))),
        ]);
  }
}

class _CoopTab extends StatelessWidget {
  const _CoopTab({required this.house});
  final MyHouse house;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.repos.currentAccount?.id ?? '';
    if (house.cooperations.isEmpty)
      return EmptyState(
          icon: Icons.handshake_outlined,
          title: tr3('还没有合作', 'Келісім жоқ', 'Пока нет соглашений'),
          body: tr3('在报价里邀请一位师傅，双方确认合作约定后会出现在这里。', 'Шеберді шақырыңыз.',
              'Пригласите мастера из предложений.'));
    String demandTitle(String id) =>
        house.demands.where((d) => d.id == id).firstOrNull?.current.title ?? '';
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          for (final c in house.cooperations)
            Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(demandTitle(c.demandId),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(cooperationStatusName(c),
                        style: TextStyle(color: t.muted)),
                    trailing: (c.status == CooperationStatus.pending &&
                            !c.agreement.confirmedBy.contains(me))
                        ? StatusPill(tr3('待你确认', 'Растаңыз', 'Подтвердите'),
                            color: t.accent, filled: true)
                        : const Icon(Icons.chevron_right),
                    onTap: () => pushPage<void>(
                        context, (_) => CooperationPage(cooperationId: c.id)))),
        ]);
  }
}

/// Small thumbnail for a house: its plan preview or a placeholder.
class HouseThumb extends StatelessWidget {
  const HouseThumb({super.key, required this.house, this.size = 72});
  final MyHouse house;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = house.preview;
    return ClipRRect(
        borderRadius: BorderRadius.circular(YRadius.control),
        child: SizedBox(
            width: size,
            height: size,
            child: p == null
                ? ColoredBox(
                    color: t.surface,
                    child: Icon(
                        house.hasDesign
                            ? Icons.home_outlined
                            : Icons.construction,
                        color: t.muted))
                : Image.memory(Uint8List.fromList(p), fit: BoxFit.cover)));
  }
}
