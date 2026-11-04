import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../chat/inbox_page.dart';
import '../discover/discover_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'house_card.dart';
import 'post_page.dart';
import 'reuse.dart';

/// First tab: houses people designed, newest first. Look, like, rate,
/// comment; owners recruit from their house, professionals offer to build.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onDesign, this.embedded = false});

  /// Jumps to the design tab (the "design your own" call to action).
  final VoidCallback? onDesign;

  /// Shown as the "houses" segment of Discover, which owns the header,
  /// the create button and the links to work and people.
  final bool embedded;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FeedFilter filter = const FeedFilter();
  final search = TextEditingController();
  Timer? _searchTimer;
  int _retry = 0;

  void searchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => filter = FeedFilter(
          region: filter.region,
          sort: filter.sort,
          openForBuilders: filter.openForBuilders,
          query: value.trim()));
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  void set(FeedFilter f) {
    _searchTimer?.cancel();
    setState(() => filter = FeedFilter(
        region: f.region,
        sort: f.sort,
        openForBuilders: f.openForBuilders,
        query: search.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    return Scaffold(
        body: SafeArea(
            top: !widget.embedded,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: CustomScrollView(slivers: [
                      SliverToBoxAdapter(
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!widget.embedded) ...[
                                      Row(children: [
                                        Expanded(
                                            child: Text('Yusal',
                                                style: wordmark(t.accent))),
                                        const InboxButton(),
                                      ]),
                                      const SizedBox(height: 4),
                                    ],
                                    Text(
                                        widget.embedded
                                            ? tr3(
                                                '挑一套，用它开始你的房子',
                                                'Үлгі таңдап, өз үйіңізді бастаңыз',
                                                'Выберите дом и начните свой с него')
                                            : tr3(
                                                '看看大家设计的房子',
                                                'Адамдар жобалаған үйлер',
                                                'Дома, которые спроектировали люди'),
                                        style: display(size: 24)),
                                    const SizedBox(height: 12),
                                    // Search pill, Airbnb style.
                                    Material(
                                        color: t.card,
                                        elevation: 0,
                                        shape: StadiumBorder(
                                            side: BorderSide(color: t.line)),
                                        shadowColor: t.shadow,
                                        child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16),
                                            child: Row(children: [
                                              Icon(Icons.search, color: t.ink),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                  child: TextField(
                                                      controller: search,
                                                      onChanged: searchChanged,
                                                      decoration: InputDecoration(
                                                          border:
                                                              InputBorder.none,
                                                          filled: false,
                                                          hintText: tr3(
                                                              '搜索房子、地区',
                                                              'Үй не аймақ іздеу',
                                                              'Дом или район'),
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical:
                                                                      14)))),
                                            ]))),
                                    const SizedBox(height: 12),
                                    SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(children: [
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: PopupMenuButton<FeedSort>(
                                              tooltip: tr3('排序', 'Сұрыптау',
                                                  'Сортировка'),
                                              initialValue: filter.sort,
                                              onSelected: (sort) => set(
                                                  FeedFilter(
                                                      region: filter.region,
                                                      sort: sort,
                                                      openForBuilders: filter
                                                          .openForBuilders)),
                                              itemBuilder: (_) => [
                                                for (final sort
                                                    in FeedSort.values)
                                                  CheckedPopupMenuItem(
                                                      value: sort,
                                                      checked:
                                                          sort == filter.sort,
                                                      child: Text(
                                                          feedSortName(sort)))
                                              ],
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 14),
                                                  child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(feedSortName(
                                                            filter.sort)),
                                                        const Icon(
                                                            Icons.expand_more,
                                                            size: 18)
                                                      ])),
                                            ),
                                          ),
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8),
                                              child: FilterPill(
                                                  label: tr3(
                                                      '正在找施工方',
                                                      'Құрылысшы іздейді',
                                                      'Ищут строителей'),
                                                  selected:
                                                      filter.openForBuilders,
                                                  onTap: () => set(FeedFilter(
                                                      region: filter.region,
                                                      sort: filter.sort,
                                                      query: filter.query,
                                                      openForBuilders: !filter
                                                          .openForBuilders)))),
                                          FilterPill(
                                              label: filter.region == null
                                                  ? tr3('地区', 'Аймақ', 'Район')
                                                  : regionName(filter.region!),
                                              selected: filter.region != null,
                                              onTap: () async {
                                                final r = await pickOne<
                                                        String?>(
                                                    context,
                                                    tr3('地区', 'Аймақ', 'Район'),
                                                    [
                                                      (
                                                        null,
                                                        tr3('全部', 'Барлығы',
                                                            'Все')
                                                      ),
                                                      for (final c
                                                          in regionCodes)
                                                        (c, regionName(c)),
                                                    ],
                                                    selected: filter.region);
                                                if (context.mounted)
                                                  set(FeedFilter(
                                                      region: r,
                                                      sort: filter.sort,
                                                      query: filter.query,
                                                      openForBuilders: filter
                                                          .openForBuilders));
                                              }),
                                        ])),
                                    if (!widget.embedded) ...[
                                      const SizedBox(height: 8),
                                      _ProBanner(),
                                    ],
                                  ]))),
                      Live<(List<HousePost>, Set<String>)>(
                          reloadKey: (
                            filter.region,
                            filter.sort,
                            filter.query,
                            filter.openForBuilders,
                            _retry
                          ),
                          error: (context, error) => SliverToBoxAdapter(
                              child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: EmptyState(
                                      icon: Icons.wifi_off_outlined,
                                      title: tr3(
                                          '暂时无法加载房子',
                                          'Үйлерді жүктеу мүмкін болмады',
                                          'Не удалось загрузить дома'),
                                      action: OutlinedButton(
                                          onPressed: () =>
                                              setState(() => _retry++),
                                          child: Text(tr3(
                                              '重试', 'Қайталау', 'Повторить')))))),
                          load: (r) async => (
                                await r.feed(filter),
                                (await r.likedPosts()).toSet()
                              ),
                          loading: const SliverToBoxAdapter(
                              child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(child: CircularProgressIndicator()))),
                          refreshError: (context, data, error, retry) => SliverMainAxisGroup(slivers: [
                                SliverToBoxAdapter(
                                    child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Wrap(
                                            spacing: 12,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(tr3(
                                                  '刷新失败，正在显示上次结果',
                                                  'Жаңарту сәтсіз, алдыңғы нәтиже көрсетілді',
                                                  'Не удалось обновить. Показаны прошлые результаты.')),
                                              OutlinedButton(
                                                  onPressed: retry,
                                                  child: Text(tr3('重试',
                                                      'Қайталау', 'Повторить')))
                                            ]))),
                                feed(context, data),
                              ]),
                          builder: feed),
                    ])))),
        floatingActionButton: widget.embedded
            ? null
            : FloatingActionButton.extended(
                onPressed: widget.onDesign,
                icon: const Icon(Icons.architecture),
                label: Text(
                    tr3('设计我的房子', 'Үйімді жобалау', 'Спроектировать дом'))));
  }

  Widget feed(BuildContext context, (List<HousePost>, Set<String>) data) {
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final (posts, liked) = data;
    if (posts.isEmpty)
      return SliverToBoxAdapter(
          child: EmptyState(
              icon: Icons.home_outlined,
              title: tr3('还没有符合条件的房子', 'Үй табылмады', 'Домов не найдено'),
              body: tr3('换个筛选，或者发布你自己的设计。', 'Сүзгіні өзгертіңіз.',
                  'Измените фильтр или опубликуйте свой проект.')));
    Widget card(HousePost p) => HouseCard(
        post: p,
        liked: liked.contains(p.id),
        onLike: () => attempt(context, () => context.repos.toggleLike(p.id)),
        onReuse: () => startFromPost(context, p),
        onTap: () => pushPage<void>(context, (_) => PostPage(postId: p.id)));
    if (wide)
      return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  // Larger text needs wider cards, not only taller rows.
                  maxCrossAxisExtent:
                      340 * MediaQuery.textScalerOf(context).scale(1),
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 20,
                  mainAxisExtent: 520 +
                      (MediaQuery.textScalerOf(context).scale(100) - 100) *
                          2.6),
              delegate: SliverChildBuilderDelegate(
                  (context, i) => card(posts[i]),
                  childCount: posts.length)));
    return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        sliver: SliverList.separated(
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 28),
            itemBuilder: (context, i) => card(posts[i])));
  }
}

/// One line for professionals: find work around these houses.
class _ProBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return InkWell(
        borderRadius: BorderRadius.circular(yRadius),
        onTap: () =>
            pushPage<void>(context, (_) => const DiscoverPage(pushed: true)),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: t.surface, borderRadius: BorderRadius.circular(yRadius)),
            child: Row(children: [
              Icon(Icons.handyman_outlined, color: t.accent),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      tr3('找人／找活 · 查看专业人士与施工需求', 'Маман / жұмыс табу',
                          'Найти мастера или работу'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14))),
              Icon(Icons.chevron_right, color: t.muted),
            ])));
  }
}
