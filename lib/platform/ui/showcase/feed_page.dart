import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../chat/inbox_page.dart';
import '../join/join_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'share_showcase_page.dart';
import 'showcase_card.dart';
import 'showcase_detail_page.dart';

/// A category of the feed's icon strip.
typedef _Category = ({String key, IconData icon, String label});

/// Home: house designs people made and published. Browse by style, like,
/// rate and comment; the ones that are hiring take builders straight to
/// their open demands.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  String category = 'all';
  ShowcaseSort sort = ShowcaseSort.latest;
  final query = TextEditingController();
  bool searching = false;

  List<_Category> get categories => [
        (
          key: 'all',
          icon: Icons.apps_rounded,
          label: tr3('全部', 'Барлығы', 'Все')
        ),
        (
          key: 'hiring',
          icon: Icons.handyman_outlined,
          label: tr3('招人中', 'Адам керек', 'Ищут мастеров')
        ),
        (
          key: 'kazakh',
          icon: Icons.cottage_outlined,
          label: styleName('kazakh')
        ),
        (key: 'modern', icon: Icons.villa_outlined, label: styleName('modern')),
        (key: 'wood', icon: Icons.forest_outlined, label: styleName('wood')),
        (key: 'brick', icon: Icons.foundation, label: styleName('brick')),
        (
          key: 'two',
          icon: Icons.stairs_outlined,
          label: tr3('两层', 'Екі қабат', 'Два этажа')
        ),
        (
          key: 'compact',
          icon: Icons.house_siding_outlined,
          label: styleName('compact')
        ),
        (
          key: 'family',
          icon: Icons.family_restroom_outlined,
          label: styleName('family')
        ),
      ];

  ShowcaseFilter get filter => ShowcaseFilter(
      style: showcaseStyles.contains(category) ? category : null,
      floors: category == 'two' ? 2 : null,
      hiringOnly: category == 'hiring',
      query: query.text,
      sort: sort);

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> share() => shareMyDesign(context);

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    AppScope.watch(context);
    final wide = MediaQuery.sizeOf(context).width > 700;
    final header = Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
        child: Row(children: [
          Icon(Icons.cabin_rounded, color: t.accent, size: 30),
          const SizedBox(width: 6),
          Text('Yusal',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: t.accent,
                  letterSpacing: -0.5)),
          const Spacer(),
          if (wide)
            TextButton(
                onPressed: () =>
                    pushPage<void>(context, (_) => const JoinPage()),
                child: Text(tr3('入驻接活', 'Шебер болу', 'Стать мастером'))),
          const InboxButton(),
        ]));
    final search = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Material(
            color: t.card,
            elevation: 0,
            shape: StadiumBorder(side: BorderSide(color: t.line)),
            shadowColor: t.shadow,
            child: Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: t.softShadow),
                child: searching
                    ? TextField(
                        controller: query,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            prefixIcon: const Icon(Icons.search),
                            hintText: tr3(
                                '搜索房子，如“两层”“锅炉房”', 'Үй іздеу', 'Поиск домов'),
                            suffixIcon: IconButton(
                                tooltip: tr3('清除', 'Тазалау', 'Очистить'),
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                      query.clear();
                                      searching = false;
                                    }))))
                    : InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setState(() => searching = true),
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                            child: Row(children: [
                              const Icon(Icons.search, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        tr3(
                                            '想盖什么样的房子？',
                                            'Қандай үй салғыңыз келеді?',
                                            'Какой дом хотите построить?'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14)),
                                    Text(
                                        tr3(
                                            '风格 · 层数 · 地区',
                                            'Стиль · қабат · аймақ',
                                            'Стиль · этажи · район'),
                                        style: TextStyle(
                                            color: t.muted, fontSize: 12)),
                                  ])),
                              Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: t.line)),
                                  child: PopupMenuButton<ShowcaseSort>(
                                      tooltip:
                                          tr3('排序', 'Сұрыптау', 'Сортировка'),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.tune, size: 18),
                                      initialValue: sort,
                                      onSelected: (v) =>
                                          setState(() => sort = v),
                                      itemBuilder: (_) => [
                                            for (final (v, label) in [
                                              (
                                                ShowcaseSort.latest,
                                                tr3('最新发布', 'Жаңа', 'Новые')
                                              ),
                                              (
                                                ShowcaseSort.popular,
                                                tr3('最受欢迎', 'Танымал',
                                                    'Популярные')
                                              ),
                                              (
                                                ShowcaseSort.topRated,
                                                tr3('评分最高', 'Жоғары баға',
                                                    'Высокий рейтинг')
                                              ),
                                            ])
                                              CheckedPopupMenuItem(
                                                  value: v,
                                                  checked: v == sort,
                                                  child: Text(label)),
                                          ])),
                            ]))))));
    final strip = SizedBox(
        height: 70,
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final c in categories)
                _CategoryTab(
                    icon: c.icon,
                    label: c.label,
                    selected: category == c.key,
                    onTap: () => setState(() => category = c.key)),
            ]));
    final grid = Live<(List<Showcase>, Set<String>, Map<String, String>)>(
        load: (r) async {
      final list = await r.showcases(filter);
      final liked = await r.likedShowcases();
      final names = <String, String>{};
      for (final id in {for (final s in list) s.ownerId}) {
        names[id] = deletedName(await r.account(id));
      }
      return (list, liked, names);
    }, builder: (context, data) {
      final (list, liked, names) = data;
      if (list.isEmpty)
        return EmptyState(
            icon: Icons.other_houses_outlined,
            title: tr3('这里还没有房子', 'Әзірге үй жоқ', 'Пока нет домов'),
            body: tr3('换个分类看看，或者发布你的第一套设计', 'Басқа санатты көріңіз',
                'Выберите другую категорию или опубликуйте свой проект'));
      return LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth > 1000
            ? 4
            : c.maxWidth > 720
                ? 3
                : c.maxWidth > 460
                    ? 2
                    : 1;
        final w = (c.maxWidth - 20 * (columns - 1)) / columns;
        return Wrap(spacing: 20, runSpacing: 26, children: [
          for (final s in list)
            SizedBox(
                width: w,
                child: ShowcaseCard(
                    showcase: s,
                    ownerName: names[s.ownerId] ?? '—',
                    liked: liked.contains(s.id),
                    onLike: () =>
                        attempt(context, () => context.repos.toggleLike(s.id)),
                    onTap: () => pushPage<void>(
                        context, (_) => ShowcaseDetailPage(showcaseId: s.id)))),
        ]);
      });
    });
    final promo = _Promo(
        icon: Icons.architecture,
        title: tr3(
            '从长宽开始，设计你自己的家', 'Өз үйіңізді жобалаңыз', 'Спроектируйте свой дом'),
        body: tr3(
            '画好后发布到这里：让大家看见、打分评论，再为它招工人、包工头和工程师。',
            'Жариялаңыз: басқалар көреді, бағалайды, сосын шебер табасыз.',
            'Опубликуйте: другие увидят и оценят, а вы найдёте мастеров.'),
        primary: (
          tr3('开始设计', 'Бастау', 'Начать'),
          () => ShellNav.goFrom(context, ShellTab.design)
        ),
        secondary: (
          tr3('发布我的设计', 'Жариялау', 'Опубликовать'),
          share
        ));
    final join = _Promo(
        icon: Icons.engineering,
        title: tr3('你是工人、包工头或工程师？', 'Сіз шебер, бригадир не инженерсіз бе?',
            'Вы мастер, прораб или инженер?'),
        body: tr3(
            '入驻 Yusal：在真实的房子设计旁接活，工程量从图纸来，报价更清楚。',
            'Yusal-ға қосылыңыз: нақты жобалар бойынша жұмыс табыңыз.',
            'Присоединяйтесь: работа по реальным проектам с понятными объёмами.'),
        primary: (
          tr3('立即入驻', 'Қосылу', 'Присоединиться'),
          () => pushPage<void>(context, (_) => const JoinPage())
        ),
        secondary: (
          tr3('看招工', 'Жұмыстар', 'Смотреть работу'),
          () => ShellNav.goFrom(context, ShellTab.work)
        ),
        soft: true);
    final browsing = category == 'all' && query.text.isEmpty;
    return Scaffold(
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: () async => setState(() {}),
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                      child: Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1280),
                              child: Column(children: [
                                header,
                                search,
                                const SizedBox(height: 8),
                                strip,
                              ])))),
                  SliverToBoxAdapter(child: Divider(color: t.line, height: 1)),
                  SliverToBoxAdapter(
                      child: Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1280),
                              child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 20, 20, 32),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (browsing) ...[
                                          promo,
                                          const SizedBox(height: 26),
                                        ],
                                        grid,
                                        if (browsing) ...[
                                          const SizedBox(height: 32),
                                          join,
                                        ],
                                      ]))))),
                ]))));
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final color = selected ? t.ink : t.muted;
    return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: selected ? t.ink : Colors.transparent,
                            width: 2))),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 24, color: color),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: color)),
                    ]))));
  }
}

class _Promo extends StatelessWidget {
  const _Promo(
      {required this.icon,
      required this.title,
      required this.body,
      required this.primary,
      required this.secondary,
      this.soft = false});
  final IconData icon;
  final String title, body;
  final (String, VoidCallback) primary, secondary;
  final bool soft;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final bg = soft ? t.surface : t.accentSoft;
    return Container(
        padding: const EdgeInsets.all(20),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 48,
              height: 48,
              decoration:
                  BoxDecoration(color: t.accent, shape: BoxShape.circle),
              child: Icon(icon, color: t.accentInk)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.25)),
                const SizedBox(height: 6),
                Text(body, style: TextStyle(color: t.muted, height: 1.45)),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
                  OutlinedButton(
                      onPressed: secondary.$2, child: Text(secondary.$1)),
                ]),
              ])),
        ]));
  }
}
