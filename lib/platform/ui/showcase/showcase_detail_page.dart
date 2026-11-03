import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../../storage/project_store.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../backup/backup_page.dart';
import '../cards.dart';
import '../chat/chat_page.dart';
import '../demand/demand_detail_page.dart';
import '../demand/from_design_page.dart';
import '../l10n.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'plan_thumb.dart';

/// Everything about one published house: the plan, its numbers, the
/// owner's story, ratings and comments, and the demands it is hiring for.
class ShowcaseDetailPage extends StatefulWidget {
  const ShowcaseDetailPage({super.key, required this.showcaseId});
  final String showcaseId;
  @override
  State<ShowcaseDetailPage> createState() => _ShowcaseDetailPageState();
}

typedef _Data = ({
  Showcase? showcase,
  Account? owner,
  bool liked,
  List<ServiceProfile> ownerProfiles,
  List<Demand> demands,
  List<(ShowcaseComment, String)> comments,
});

class _ShowcaseDetailPageState extends State<ShowcaseDetailPage> {
  int floor = 0;

  Future<_Data> load(PlatformRepositories repos) async {
    final s = await repos.showcase(widget.showcaseId);
    if (s == null)
      return (
        showcase: null,
        owner: null,
        liked: false,
        ownerProfiles: const <ServiceProfile>[],
        demands: const <Demand>[],
        comments: const <(ShowcaseComment, String)>[]
      );
    final comments = await repos.comments(s.id);
    final names = <String, String>{};
    for (final id in {for (final c in comments) c.authorId}) {
      names[id] = deletedName(await repos.account(id));
    }
    return (
      showcase: s,
      owner: await repos.account(s.ownerId),
      liked: (await repos.likedShowcases()).contains(s.id),
      ownerProfiles: await repos.profilesOf(s.ownerId),
      demands: [
        for (final id in s.openDemandIds)
          if (await repos.demand(id) case final d?) d
      ],
      comments: [for (final c in comments) (c, names[c.authorId] ?? '—')],
    );
  }

  /// The owner's local copy of the design, if this device has it.
  Future<ProjectEntry?> localEntry(Showcase s) async {
    try {
      return (await context.projectStore.listProjects())
          .where((p) => p.id == s.projectId)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<void> hire(Showcase s) async {
    final entry = await localEntry(s);
    if (!mounted) return;
    if (entry == null) {
      toast(
          context,
          tr3('这台设备上没有这套设计，请在原设备上招人，或先从备份恢复', 'Бұл құрылғыда жоба жоқ',
              'На этом устройстве нет проекта'));
      return;
    }
    await pushPage<void>(context, (_) => FromDesignPage(entry: entry));
  }

  Future<void> copy(Showcase s) async {
    final design = decodeShowcase(s.id, s.houseText);
    if (design == null) return;
    try {
      await context.projectStore.createProject(design.$1);
    } catch (_) {
      if (mounted)
        toast(context, tr3('保存失败，请重试', 'Сақталмады', 'Не удалось сохранить'));
      return;
    }
    if (!mounted) return;
    PlatformReload.of(context)?.bump();
    toast(
        context,
        tr3('已复制到“我的设计”，可以随意修改', 'Жобаларыма көшірілді',
            'Скопировано в «Мои проекты»'));
    ShellNav.goFrom(context, ShellTab.design);
  }

  Future<void> contact(Showcase s) async {
    final conv =
        await attempt(context, () => context.repos.openConversation(s.ownerId));
    if (conv == null || !mounted) return;
    await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
  }

  Future<void> review(Showcase s, bool mine) async {
    if (!await requireLogin(context) || !mounted) return;
    final result = await showModalBottomSheet<(int?, String)>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlatformTheme(child: _ReviewSheet(canRate: !mine)));
    if (result == null || !mounted) return;
    await attempt(context,
        () => context.repos.addComment(s.id, result.$2, rating: result.$1),
        success: tr3('已发布', 'Жарияланды', 'Опубликовано'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    AppScope.watch(context);
    return Live<_Data>(
        load: load,
        builder: (context, data) {
          final s = data.showcase;
          if (s == null)
            return Scaffold(
                appBar: AppBar(),
                body: EmptyState(
                    icon: Icons.visibility_off_outlined,
                    title: tr3('这套设计已下架', 'Жоба жабылды', 'Проект снят')));
          final me = context.repos.currentAccount?.id;
          final mine = me == s.ownerId;
          final ownerName = deletedName(data.owner);
          final wide = MediaQuery.sizeOf(context).width > 760;
          final picture = Stack(children: [
            Positioned.fill(
                child: Hero(
                    tag: 'plan-${s.id}',
                    child: InteractiveViewer(
                        maxScale: 5,
                        child: PlanThumb(
                            cacheKey: s.id,
                            houseText: s.houseText,
                            floor: floor,
                            labels: true,
                            padding: 24)))),
            if (s.floors > 1)
              Positioned(
                  left: 12,
                  bottom: 12,
                  child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                          backgroundColor: t.card,
                          selectedBackgroundColor: t.ink,
                          selectedForegroundColor: t.bg),
                      segments: [
                        for (var i = 0; i < s.floors; i++)
                          ButtonSegment(
                              value: i,
                              label: Text(tr3('${i + 1} 层', '${i + 1}-қабат',
                                  '${i + 1} эт.'))),
                      ],
                      selected: {floor},
                      onSelectionChanged: (v) =>
                          setState(() => floor = v.first))),
          ]);
          final stats = Row(children: [
            for (final (value, label) in [
              (
                '${s.area.toStringAsFixed(0)} ${tr3('㎡', 'м²', 'м²')}',
                tr3('建筑面积', 'Аудан', 'Площадь')
              ),
              ('${s.floors}', tr3('层', 'Қабат', 'Этажи')),
              ('${s.rooms}', tr3('房间', 'Бөлме', 'Комнаты')),
              (
                '${numText(s.width / 1000)}×${numText(s.depth / 1000)}',
                tr3('长×宽 米', 'Ұз.×ен. м', 'Д×Ш м')
              ),
            ])
              Expanded(
                  child: Column(children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: t.muted, fontSize: 12)),
              ])),
          ]);
          final rated = data.comments.where((c) => c.$1.rating != null);
          final body =
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.title,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 6),
            Text(
                [
                  if (s.rating != null)
                    '★ ${s.rating!.toStringAsFixed(1)} · ${tr3('${s.ratingCount} 个评分', '${s.ratingCount} баға', '${s.ratingCount} оценок')}',
                  regionName(s.region),
                  '♥ ${s.likes}',
                ].join(' · '),
                style: TextStyle(color: t.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(yRadius)),
                child: stats),
            const SizedBox(height: 20),
            InkWell(
                onTap: data.ownerProfiles.isEmpty
                    ? null
                    : () => pushPage<void>(
                        context,
                        (_) => ProfilePage(
                            profileId: data.ownerProfiles.first.id)),
                child: Row(children: [
                  Avatar(ownerName, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            tr3('设计者 $ownerName', 'Жобалаушы $ownerName',
                                'Автор $ownerName'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(
                            data.ownerProfiles.isEmpty
                                ? tr3('房主 · 发布于 ${fmtDay(s.createdAt)}',
                                    'Үй иесі', 'Владелец')
                                : [
                                    for (final tr in data
                                        .ownerProfiles.first.trades
                                        .take(3))
                                      tradeName(tr)
                                  ].join(' · '),
                            style: TextStyle(color: t.muted, fontSize: 13)),
                      ])),
                  if (data.ownerProfiles.isNotEmpty)
                    const Icon(Icons.chevron_right),
                ])),
            if (s.story.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(s.story, style: const TextStyle(fontSize: 15, height: 1.6)),
            ],
            if (s.styles.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final st in s.styles)
                  Chip(
                      label: Text(styleName(st)),
                      visualDensity: VisualDensity.compact),
              ]),
            ],
            const SizedBox(height: 8),
            Divider(color: t.line, height: 32),
            SectionTitle(
                s.hiring
                    ? tr3('这套房子正在招人', 'Бұл үйге шебер керек',
                        'Для этого дома ищут мастеров')
                    : tr3('施工', 'Құрылыс', 'Стройка'),
                top: 0),
            if (data.demands.isEmpty)
              Text(
                  mine
                      ? tr3(
                          '准备开工了？从这套设计直接生成招工需求，工程量自动从图纸算出。',
                          'Жобадан тапсырыс жасаңыз — көлем автоматты.',
                          'Создайте заявку из проекта — объёмы посчитаются сами.')
                      : tr3('房主暂时还没有招人。可以先收藏，或联系房主聊聊。',
                          'Әзірге адам іздемейді.', 'Пока никого не ищут.'),
                  style: TextStyle(color: t.muted, height: 1.5))
            else
              for (final d in data.demands)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DemandCard(
                        demand: d,
                        compact: true,
                        onTap: () => pushPage<void>(
                            context, (_) => DemandDetailPage(demandId: d.id)))),
            if (mine) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                  onPressed: () => hire(s),
                  icon: const Icon(Icons.handyman_outlined),
                  label: Text(tr3('为这套房子招人', 'Шебер іздеу', 'Найти мастеров'))),
            ],
            Divider(color: t.line, height: 40),
            SectionTitle(
                s.rating == null
                    ? tr3('评价', 'Пікірлер', 'Отзывы')
                    : '★ ${s.rating!.toStringAsFixed(1)} · ${tr3('${rated.length} 个评分', '${rated.length} баға', '${rated.length} оценок')}',
                top: 0,
                trailing: TextButton(
                    onPressed: () => review(s, mine),
                    child: Text(mine
                        ? tr3('回复', 'Жауап', 'Ответить')
                        : tr3('写评价', 'Пікір жазу', 'Оставить отзыв')))),
            if (data.comments.isEmpty)
              Text(tr3('还没有评价，来做第一个吧', 'Әзірге пікір жоқ', 'Отзывов пока нет'),
                  style: TextStyle(color: t.muted)),
            for (final (c, name) in data.comments)
              _CommentTile(
                  comment: c,
                  name: name,
                  byOwner: c.authorId == s.ownerId,
                  now: context.now),
            const SizedBox(height: 24),
          ]);
          final bar = mine
              ? Row(children: [
                  Expanded(
                      child: Text(tr3('你发布的设计', 'Сіздің жобаңыз', 'Ваш проект'),
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  OutlinedButton(
                      onPressed: () async {
                        if (await confirmDialog(
                                context,
                                tr3('从首页下架？', 'Жариялауды тоқтату?',
                                    'Снять с публикации?'),
                                body: tr3('评价和点赞会一起删除，本机设计不受影响。',
                                    'Пікірлер жойылады.', 'Отзывы удалятся.'),
                                ok: tr3('下架', 'Тоқтату', 'Снять')) &&
                            context.mounted) {
                          final ok = await attempt(
                              context,
                              () => context.repos
                                  .removeShowcase(s.id)
                                  .then((_) => true));
                          if (ok == true && context.mounted)
                            Navigator.pop(context);
                        }
                      },
                      child: Text(tr3('下架', 'Тоқтату', 'Снять'))),
                  const SizedBox(width: 10),
                  FilledButton(
                      onPressed: () => hire(s),
                      child: Text(tr3('招人', 'Шебер', 'Найти'))),
                ])
              : Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () => copy(s),
                          icon: const Icon(Icons.content_copy, size: 18),
                          label: Text(tr3('复制设计', 'Көшіру', 'Копировать')))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton.icon(
                          onPressed: () => s.hiring && data.demands.isNotEmpty
                              ? pushPage<void>(
                                  context,
                                  (_) => DemandDetailPage(
                                      demandId: data.demands.first.id))
                              : contact(s),
                          icon: Icon(
                              s.hiring
                                  ? Icons.handyman
                                  : Icons.chat_bubble_outline,
                              size: 18),
                          label: Text(s.hiring
                              ? tr3('去报名', 'Өтінім беру', 'Откликнуться')
                              : tr3('联系房主', 'Жазу', 'Написать')))),
                ]);
          final likeButton = IconButton(
              tooltip: tr3('点赞', 'Ұнату', 'Нравится'),
              icon: Icon(data.liked ? Icons.favorite : Icons.favorite_border,
                  color: data.liked ? t.accent : null),
              onPressed: () =>
                  attempt(context, () => context.repos.toggleLike(s.id)));
          if (wide)
            return Scaffold(
                appBar: AppBar(actions: [likeButton]),
                bottomNavigationBar: ActionBar(child: bar),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  flex: 6,
                                  child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 8, 12, 24),
                                      child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: AspectRatio(
                                              aspectRatio: 1,
                                              child: picture)))),
                              Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 8, 24, 24),
                                      child: body)),
                            ]))));
          return Scaffold(
              bottomNavigationBar: ActionBar(child: bar),
              body: CustomScrollView(slivers: [
                SliverAppBar(
                    pinned: true,
                    expandedHeight: 340,
                    actions: [likeButton],
                    flexibleSpace: FlexibleSpaceBar(background: picture)),
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    sliver: SliverToBoxAdapter(child: body)),
              ]));
        });
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile(
      {required this.comment,
      required this.name,
      required this.byOwner,
      required this.now});
  final ShowcaseComment comment;
  final String name;
  final bool byOwner;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(name, size: 36),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (byOwner) ...[
                    const SizedBox(width: 6),
                    StatusPill(tr3('设计者', 'Автор', 'Автор'), color: t.accent),
                  ],
                  const SizedBox(width: 8),
                  Text(ago(comment.createdAt, now),
                      style: TextStyle(color: t.muted, fontSize: 12)),
                ]),
                if (comment.rating != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(
                          i <= comment.rating!
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 16,
                          color: t.accent),
                  ]),
                ],
                if (comment.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(comment.text, style: const TextStyle(height: 1.5)),
                ],
              ])),
        ]));
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.canRate});
  final bool canRate;
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int? rating;
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final ready = rating != null || text.text.trim().isNotEmpty;
    return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  widget.canRate
                      ? tr3('你觉得这套设计怎么样？', 'Жоба қалай?', 'Как вам проект?')
                      : tr3('回复大家', 'Жауап беру', 'Ответить'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              if (widget.canRate) ...[
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                        tooltip: '$i',
                        iconSize: 40,
                        onPressed: () => setState(() => rating = i),
                        icon: Icon(
                            rating != null && i <= rating!
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: t.accent)),
                ]),
              ],
              const SizedBox(height: 12),
              TextField(
                  controller: text,
                  maxLines: 4,
                  maxLength: 300,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      hintText: tr3('说说哪里好、哪里可以改进', 'Пікіріңіз', 'Ваш отзыв'))),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: ready
                      ? () => Navigator.pop(context, (rating, text.text))
                      : null,
                  child: Text(tr3('发布', 'Жариялау', 'Опубликовать'))),
            ]));
  }
}
