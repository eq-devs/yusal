import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../cards.dart';
import '../chat/inbox_page.dart';
import '../demand/demand_detail_page.dart';
import '../demand/publish_page.dart';
import '../l10n.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// First tab: "find work / find people" with search and filters.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  bool people = false;
  final query = TextEditingController();
  DemandType? type;
  String? trade, region;
  ProfileKind? kind;
  bool availableNow = false;

  Future<void> publish() async {
    if (!await requireLogin(context) || !mounted) return;
    await pushPage<void>(context, (_) => const PublishPage());
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    AppScope.watch(context);
    final filters = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          if (!people) ...[
            FilterPill(
                label: type == null
                    ? tr3('全部类型', 'Барлық түрі', 'Все типы')
                    : demandTypeName(type!),
                selected: type != null,
                icon: Icons.tune,
                onTap: () async {
                  final v = await pickOne<DemandType?>(
                      context,
                      tr3('需求类型', 'Түрі', 'Тип'),
                      [
                        (null, tr3('全部', 'Барлығы', 'Все')),
                        for (final d in DemandType.values)
                          (d, demandTypeName(d)),
                      ],
                      selected: type);
                  if (mounted) setState(() => type = v);
                }),
            const SizedBox(width: 8),
          ],
          FilterPill(
              label: trade == null
                  ? tr3('工种', 'Мамандық', 'Специальность')
                  : tradeName(trade!),
              selected: trade != null,
              onTap: () async {
                final v = await pickOne<String?>(
                    context,
                    tr3('工种', 'Мамандық', 'Специальность'),
                    [
                      (null, tr3('全部', 'Барлығы', 'Все')),
                      for (final c in tradeCodes) (c, tradeName(c)),
                    ],
                    selected: trade);
                if (mounted) setState(() => trade = v);
              }),
          const SizedBox(width: 8),
          FilterPill(
              label: region == null
                  ? tr3('地区', 'Аймақ', 'Район')
                  : regionName(region!),
              selected: region != null,
              icon: Icons.place_outlined,
              onTap: () async {
                final v = await pickOne<String?>(
                    context,
                    tr3('地区', 'Аймақ', 'Район'),
                    [
                      (null, tr3('全部', 'Барлығы', 'Все')),
                      for (final c in regionCodes) (c, regionName(c)),
                    ],
                    selected: region);
                if (mounted) setState(() => region = v);
              }),
          if (people) ...[
            const SizedBox(width: 8),
            FilterPill(
                label: tr3('现在可接', 'Қазір бос', 'Свободен сейчас'),
                selected: availableNow,
                onTap: () => setState(() => availableNow = !availableNow)),
            const SizedBox(width: 8),
            FilterPill(
                label: kind == null
                    ? tr3('个人／团队', 'Жеке / бригада', 'Мастер / бригада')
                    : profileKindName(kind!),
                selected: kind != null,
                onTap: () => setState(() => kind = switch (kind) {
                      null => ProfileKind.individual,
                      ProfileKind.individual => ProfileKind.team,
                      ProfileKind.team => null,
                    })),
          ],
        ]));
    final search = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
            decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.line),
                boxShadow: t.softShadow),
            child: TextField(
                controller: query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    prefixIcon: const Icon(Icons.search),
                    hintText: people
                        ? tr3('搜索工人、施工队', 'Шебер не бригада іздеу',
                            'Поиск мастеров и бригад')
                        : tr3('搜索需求，如“砌墙”', 'Тапсырыс іздеу',
                            'Поиск заявок, напр. «кладка»'),
                    suffixIcon: query.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(query.clear))))));
    final toggle = Row(children: [
      for (final (isPeople, icon, label) in [
        (false, Icons.work_outline, tr3('找活', 'Жұмыс табу', 'Найти работу')),
        (true, Icons.groups_outlined, tr3('找人', 'Адам табу', 'Найти мастера')),
      ])
        Expanded(
            child: InkWell(
                onTap: () => setState(() => people = isPeople),
                child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: people == isPeople ? t.ink : t.line,
                                width: people == isPeople ? 2 : 1))),
                    child: Column(children: [
                      Icon(icon, color: people == isPeople ? t.ink : t.muted),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: people == isPeople ? t.ink : t.muted)),
                    ])))),
    ]);
    final list = people
        ? Live<List<ServiceProfile>>(
            load: (r) => r.searchProfiles(ProfileFilter(
                kind: kind,
                trade: trade,
                region: region,
                availableNow: availableNow,
                query: query.text)),
            builder: (context, list) => list.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title:
                        tr3('没有符合条件的人', 'Сәйкес адам жоқ', 'Никого не нашли'),
                    body: tr3('试试放宽地区或工种', 'Сүзгіні кеңейтіп көріңіз',
                        'Попробуйте смягчить фильтры'))
                : Column(children: [
                    for (final p in list)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ProfileCard(
                              profile: p,
                              onTap: () => pushPage<void>(context,
                                  (_) => ProfilePage(profileId: p.id)))),
                  ]))
        : Live<(List<Demand>, Set<String>)>(
            load: (r) async => (
                  await r.searchDemands(DemandFilter(
                      type: type,
                      trade: trade,
                      region: region,
                      query: query.text)),
                  await r.favourites(),
                ),
            builder: (context, data) {
              final (list, favs) = data;
              if (list.isEmpty)
                return EmptyState(
                    icon: Icons.search_off,
                    title: tr3('暂时没有符合条件的需求', 'Сәйкес тапсырыс жоқ',
                        'Нет подходящих заявок'),
                    body: tr3('换个地区或工种看看', 'Аймақ не мамандықты өзгертіңіз',
                        'Измените район или специальность'));
              return LayoutBuilder(builder: (context, c) {
                final columns = c.maxWidth > 900
                    ? 3
                    : c.maxWidth > 560
                        ? 2
                        : 1;
                final w = (c.maxWidth - 16 * (columns - 1)) / columns;
                return Wrap(spacing: 16, runSpacing: 16, children: [
                  for (final d in list)
                    SizedBox(
                        width: w,
                        child: DemandCard(
                            demand: d,
                            favourite: favs.contains(d.id),
                            onFavourite: () => attempt(context,
                                () => context.repos.toggleFavourite(d.id)),
                            onTap: () => pushPage<void>(context,
                                (_) => DemandDetailPage(demandId: d.id)))),
                ]);
              });
            });
    return Scaffold(
        floatingActionButton: people
            ? null
            : FloatingActionButton.extended(
                onPressed: publish,
                icon: const Icon(Icons.add),
                label: Text(tr3('发布需求', 'Тапсырыс беру', 'Разместить заявку'))),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: CustomScrollView(slivers: [
                      SliverToBoxAdapter(
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                              child: Row(children: [
                                Expanded(
                                    child: Text('Yusal',
                                        style: TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            color: t.accent,
                                            letterSpacing: -0.5))),
                                const InboxButton(),
                              ]))),
                      SliverToBoxAdapter(child: search),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      SliverToBoxAdapter(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: toggle)),
                      const SliverToBoxAdapter(child: SizedBox(height: 14)),
                      SliverToBoxAdapter(child: filters),
                      SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
                          sliver: SliverToBoxAdapter(child: list)),
                    ])))));
  }
}
