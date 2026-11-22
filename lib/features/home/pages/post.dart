import 'dart:async';

import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/home/state/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/features/demand/widgets/demand_card.dart';
import 'package:yusal/shared/ui/components.dart';
import 'package:yusal/features/home/widgets/plan_viewer.dart';
import 'package:yusal/features/chat/page.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/features/demand/pages/publish.dart';
import 'package:yusal/shared/l10n/l10n.dart';
import 'package:yusal/shared/ui/links.dart';
import 'package:yusal/features/profile/page.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/features/shell/page.dart';
import 'package:yusal/shared/theme/theme.dart';
import 'package:yusal/shared/ui/widgets.dart';
import 'package:yusal/features/home/widgets/critiques.dart';
import 'package:yusal/features/home/widgets/house_card.dart';
import 'package:yusal/features/home/util/reuse.dart';
import 'package:yusal/shared/ui/house_progress.dart';
import 'package:yusal/shared/motion/motion.dart';
import 'package:yusal/features/me/pages/trust.dart';
import 'package:yusal/shared/brand/yicon.dart';

/// One house: the plan, the facts, the story, the people recruiting for
/// it, and what others think. The owner recruits from here; a
/// professional applies or writes from here.
class PostPage extends ConsumerStatefulWidget {
  const PostPage({super.key, required this.postId, this.preview});
  final String postId;

  /// The post as the list already had it: lets the page show its cover
  /// (and catch the shared-element flight) before the rest has loaded.
  final HousePost? preview;

  @override
  ConsumerState<PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<PostPage> {
  /// The cover, shared by the skeleton and the loaded page. When the house
  /// arrives the cover moves into the new page instead of being built
  /// again: a rebuilt cover would end the list card's flight half-way, the
  /// picture flashing at its landing spot while the flying copy fades.
  final _cover = GlobalKey();

  /// Where "comments" in the bottom bar scrolls to.
  final _critiques = GlobalKey();
  final _scroll = ScrollController();

  /// True once the cover has scrolled away: the bar then names the house.
  final _collapsed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _collapsed.value =
        _scroll.hasClients && _scroll.offset > _coverHeight - 40);
  }

  /// The route has slid in. One thing moves at a time: the page swaps the
  /// skeleton for the house only once it has, so the big build does not
  /// land in the middle of the slide and the cover's flight.
  bool _settledIn = false;
  bool _waiting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settledIn || _waiting) return;
    final route = ModalRoute.of(context);
    if (route?.animation?.status != AnimationStatus.forward) {
      _settledIn = true;
      return;
    }
    _waiting = true;
    _settled(route).then((_) {
      if (mounted) setState(() => _settledIn = true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _collapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    final postId = widget.postId;
    final preview = widget.preview;
    final loading = preview == null
        ? const SkeletonPage(cover: 230)
        : _PostSkeleton(post: preview, coverKey: _cover);
    // Loads while the route slides in; shown once it has.
    ref.watch(postPageProvider(postId));
    if (!_settledIn) return loading;
    return Live<PostPageData>(
        provider: postPageProvider(postId),
        loading: loading,
        builder: (context, data) {
          final (p, liked, demands, comments, snap, isPro, build) = data;
          if (p == null) {
            return PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.home_outlined,
                    title: tr3(
                        '这栋房子已经不可见', 'Үй қолжетімсіз', 'Дом больше недоступен'),
                    action: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pushNamedAndRemoveUntil('/', (_) => false),
                        child: Text(tr3('首页', 'Басты', 'Главная')))));
          }
          final me = context.session.currentAccount;
          final mine = me?.id == p.ownerId;
          final image =
              p.preview == null ? null : MemoryImage(imageBytes(p.preview!));
          final open =
              demands.where((d) => d.status == DemandStatus.open).toList();
          // Floor count is already on the fact sheet.
          final shownTags = [
            for (final tag in p.tags)
              if (tag != 'one_floor' && tag != 'two_floors') tag
          ];

          Future<void> contact() async {
            if (!await requireLogin(context) || !context.mounted) return;
            final conv = await attempt(
                context,
                () => context
                    .read(chatRepositoryProvider)
                    .openConversation(p.ownerId));
            if (conv != null && context.mounted) {
              await pushPage<void>(
                  context, (_) => ChatPage(conversationId: conv.id));
            }
          }

          Future<void> recruit() async {
            if (snap == null) return;
            await pushPage<void>(
                context,
                (_) =>
                    PublishPage(snapshot: snap, designProjectId: p.projectId));
          }

          Future<void> share() async {
            final link = houseLink(p.id);
            final c = await pickOne<String>(
                context, tr3('分享这栋房子', 'Үймен бөлісу', 'Поделиться домом'), [
              ('copy', tr3('复制链接', 'Сілтемені көшіру', 'Скопировать ссылку')),
              (
                'share',
                tr3('通过其他应用分享', 'Басқа қолданбамен бөлісу', 'Отправить через…')
              ),
            ]);
            if (c == null || !context.mounted) return;
            if (c == 'copy') {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                toast(
                    context,
                    tr3('已复制，任何人打开都能看', 'Көшірілді, кез келген адам аша алады',
                        'Скопировано, откроется у любого'));
              }
            } else {
              try {
                await SharePlus.instance
                    .share(ShareParams(text: '${p.title}\n$link'));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  toast(
                      context,
                      tr3('此设备不支持系统分享，已复制链接', 'Сілтеме көшірілді',
                          'Ссылка скопирована'));
                }
              }
            }
          }

          Future<void> more() async {
            final c = await pickOne<String>(context, p.title, [
              if (mine) ('edit', tr3('修改标题和说明', 'Өңдеу', 'Изменить описание')),
              if (mine)
                (
                  'builders',
                  p.openForBuilders
                      ? tr3('不再找施工方', 'Құрылысшы іздеуді тоқтату',
                          'Больше не ищу строителей')
                      : tr3('标记为正在找施工方', 'Құрылысшы іздеймін', 'Ищу строителей')
                ),
              if (mine)
                (
                  'build',
                  p.showBuild
                      ? tr3('不再公开谁在建和花费', 'Құрылысшыларды жасыру',
                          'Скрыть строителей и расходы')
                      : tr3('公开谁在建和花费', 'Құрылысшыларды көрсету',
                          'Показать строителей и расходы')
                ),
              if (mine) ('hide', tr3('下架这栋房子', 'Жасыру', 'Скрыть')),
              if (!mine) ('report', tr3('举报', 'Шағымдану', 'Пожаловаться')),
            ]);
            if (c == null || !context.mounted) return;
            switch (c) {
              case 'edit':
                final title = await askText(
                    context, tr3('标题', 'Атауы', 'Название'),
                    initial: p.title, lines: 1);
                if (title == null || !context.mounted) return;
                final story = await askText(
                    context, tr3('说明', 'Сипаттама', 'Описание'),
                    initial: p.story, required: false);
                if (!context.mounted) return;
                await attempt(
                    context,
                    () => context.read(postRepositoryProvider).updatePost(
                        p.copyWith(title: title, story: story ?? p.story)));
              case 'builders':
                await attempt(
                    context,
                    () => context.read(postRepositoryProvider).updatePost(
                        p.copyWith(openForBuilders: !p.openForBuilders)));
              case 'build':
                await attempt(
                    context,
                    () => context
                        .read(postRepositoryProvider)
                        .updatePost(p.copyWith(showBuild: !p.showBuild)),
                    success: p.showBuild
                        ? tr3('已不再公开', 'Жасырылды', 'Скрыто')
                        : tr3('访客现在能看到谁在建、已验收多少', 'Көрсетілді',
                            'Теперь видно, кто строит и сколько принято'));
              case 'hide':
                if (await confirmDialog(
                        context, tr3('下架这栋房子？', 'Жасыру?', 'Скрыть дом?'),
                        danger: true) &&
                    context.mounted) {
                  await attempt(
                      context,
                      () =>
                          context.read(postRepositoryProvider).hidePost(p.id));
                  if (context.mounted) Navigator.of(context).pop();
                }
              case 'report':
                await reportContent(context, ReportTarget.post, p.id);
            }
          }

          final fromLink = !Navigator.of(context).canPop();
          final visitorBar =
              !mine && !(isPro && (open.isNotEmpty || p.openForBuilders));
          void openPlan() {
            if (snap == null) return;
            Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PlanViewer(snapshot: snap)));
          }

          return Scaffold(
              body: CustomScrollView(controller: _scroll, slivers: [
                SliverAppBar(
                    pinned: true,
                    expandedHeight: _coverHeight,
                    backgroundColor: t.bg,
                    surfaceTintColor: Colors.transparent,
                    titleSpacing: 0,
                    title: ValueListenableBuilder<bool>(
                        valueListenable: _collapsed,
                        // Built only once collapsed: while the big title
                        // is on screen there is just one title.
                        builder: (context, collapsed, _) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: collapsed
                                ? Text(p.title,
                                    key: const ValueKey('bar-title'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: YFont.body,
                                        fontWeight: FontWeight.w700))
                                : const SizedBox.shrink())),
                    // Opened from a shared link: no page to go back to, so
                    // offer the home feed instead.
                    // Every control sits on a round backing: the cover is
                    // a light drawing in both themes.
                    leading: _PostLeading(fromLink: fromLink),
                    actions: [
                      IconAction(
                          label: tr3('分享', 'Бөлісу', 'Поделиться'),
                          icon: const YusalIcon(YIcon.share, size: 20),
                          onPressed: share),
                      if (!visitorBar)
                        OptimisticLike(
                            liked: liked,
                            toggle: () => attempt(
                                context,
                                () => context
                                    .read(postRepositoryProvider)
                                    .toggleLike(p.id)),
                            builder: (context, liked, toggle) => IconAction(
                                label: liked
                                    ? tr3('取消喜欢', 'Ұнатуды алу', 'Убрать лайк')
                                    : tr3('喜欢', 'Ұнайды', 'Нравится'),
                                color: liked ? t.accent : null,
                                icon: PopOnActive(
                                    active: liked,
                                    child: Icon(
                                        liked
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 20)),
                                onPressed: toggle)),
                      IconAction(
                          label: tr3('更多', 'Тағы', 'Ещё'),
                          icon: const Icon(Icons.more_horiz, size: 20),
                          onPressed: more),
                      const SizedBox(width: YSpace.sm),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                        background: _CoverFrame(
                            onTap: snap == null ? null : openPlan,
                            child: _PostCover(
                                key: _cover, post: p, image: image)))),
                SliverToBoxAdapter(
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 18, 20, 120),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p.title, style: display()),
                                      const SizedBox(height: 8),
                                      _MetaLine(post: p),
                                      if (shownTags.isNotEmpty ||
                                          p.reuseCount > 0)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 10),
                                            child: Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  for (final tag in shownTags)
                                                    StatusPill(
                                                        postTagName(tag)),
                                                  if (p.reuseCount > 0)
                                                    StatusPill(
                                                        reusedTimes(
                                                            p.reuseCount),
                                                        color: t.accent),
                                                ])),
                                      const SizedBox(height: 16),
                                      // Who and what they say, before the
                                      // numbers: the post reads like a post.
                                      _Byline(
                                          post: p,
                                          mine: mine,
                                          onContact: contact),
                                      if (p.story.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        _Story(text: p.story),
                                      ],
                                      const SizedBox(height: 20),
                                      _FactSheet(post: p, snapshot: snap),
                                      const SizedBox(height: 16),
                                      // Shared to hear opinions: the ask
                                      // replaces the build progress.
                                      if (!p.openForBuilders &&
                                          demands.isEmpty &&
                                          build == null)
                                        FeedbackAsk(post: p)
                                      else
                                        HouseProgress(
                                            stage: build?.finished == true
                                                ? HouseStage.done
                                                : build != null
                                                    ? HouseStage.building
                                                    : stageFromDemands(
                                                        demands)),
                                      if (open.isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: Row(children: [
                                              Icon(Icons.campaign_outlined,
                                                  size: 18, color: t.accent),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                  child: Text(
                                                      '${tr3('正在招：', 'Іздеуде: ', 'Ищут: ')}${open.map((d) => d.current.title).join(listSep)}',
                                                      style: TextStyle(
                                                          color: t.accent,
                                                          fontWeight: FontWeight
                                                              .w600))),
                                            ])),
                                      PlanAttachment(snapshot: snap),
                                      // Facts from the design.
                                      if (snap != null &&
                                          snap.lines.isNotEmpty) ...[
                                        SectionTitle(tr3(
                                            '工程量', 'Көлемдер', 'Объёмы работ')),
                                        _Quantities(snapshot: snap),
                                      ],
                                      // Recruiting; a house shared only to
                                      // hear opinions skips it.
                                      if (p.openForBuilders ||
                                          demands.isNotEmpty ||
                                          build != null) ...[
                                        SectionTitle(
                                            tr3('这栋房子在招谁', 'Бұл үйге кім керек',
                                                'Кто нужен для этого дома'),
                                            trailing: mine && snap != null
                                                ? TextButton.icon(
                                                    onPressed: recruit,
                                                    icon: const Icon(Icons.add,
                                                        size: 18),
                                                    label: Text(tr3('招人',
                                                        'Іздеу', 'Найти')))
                                                : null),
                                        if (demands.isEmpty)
                                          Text(
                                              build != null &&
                                                      build.builders.isNotEmpty
                                                  ? tr3(
                                                      '已发布的阶段都有人在做了。需要下一个阶段时再招人。',
                                                      'Барлық кезеңнің орындаушысы бар.',
                                                      'На все этапы уже есть исполнители.')
                                                  : mine
                                                      ? tr3(
                                                          '还没有为这栋房子发布过需求。点“招人”，工程量会从设计里自动带出来。',
                                                          'Әлі тапсырыс жоқ. «Іздеу» басыңыз.',
                                                          'Заявок пока нет. Нажмите «Найти», объёмы подставятся из проекта.')
                                                      : p.openForBuilders
                                                          ? tr3(
                                                              '设计者正在找施工方，但还没发布具体需求。可以先私信。',
                                                              'Иесі құрылысшы іздейді. Жазып көріңіз.',
                                                              'Автор ищет строителей, но заявки ещё нет. Напишите ему.')
                                                          : tr3(
                                                              '暂时没有在招的人。',
                                                              'Қазір іздемейді.',
                                                              'Сейчас никого не ищет.'),
                                              style: TextStyle(color: t.muted)),
                                        for (final d in demands)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: DemandCard(
                                                  compact: true,
                                                  demand: d,
                                                  onTap: () => pushPage<void>(
                                                      context,
                                                      (_) => DemandDetailPage(
                                                          demandId: d.id)))),
                                      ],
                                      if (build != null)
                                        _BuildSection(
                                            info: build,
                                            mine: mine,
                                            shown: p.showBuild),
                                      // Critiques.
                                      CritiqueSection(
                                          key: _critiques,
                                          post: p,
                                          comments: comments,
                                          mine: mine,
                                          meId: me?.id),
                                    ]))))),
              ]),
              bottomNavigationBar: _bottomBar(context,
                  post: p,
                  mine: mine,
                  isPro: isPro,
                  liked: liked,
                  open: open,
                  canReuse: snap?.planJson != null,
                  recruit: snap == null ? null : recruit,
                  building: build != null && build.builders.isNotEmpty,
                  contact: contact));
        });
  }

  /// One fixed action bar whose main button depends on who is looking:
  /// the owner manages recruiting, a pro quotes, a visitor starts their own
  /// house from this one.
  Widget? _bottomBar(BuildContext context,
      {required HousePost post,
      required bool mine,
      required bool isPro,
      required bool liked,
      required List<Demand> open,
      required bool canReuse,
      required VoidCallback? recruit,
      bool building = false,
      required VoidCallback contact}) {
    final t = YTokens.of(context);
    Future<void> openDemand() async {
      final d = open.length == 1
          ? open.first
          : await pickOne<Demand>(
              context,
              tr3('选一个阶段', 'Кезеңді таңдаңыз', 'Выберите этап'),
              [for (final d in open) (d, d.current.title)]);
      if (d != null && context.mounted) {
        await pushPage<void>(context, (_) => DemandDetailPage(demandId: d.id));
      }
    }

    final String summary;
    final Widget main;
    if (mine && !post.openForBuilders && open.isEmpty && !building) {
      // Shared to hear opinions: show how it is going and offer the step
      // to building when the author is ready.
      summary = post.commentCount == 0
          ? tr3('等大家点评', 'Пікір күтілуде', 'Ждём отзывов')
          // commentCount includes replies, unlike the critiques header.
          : tr3(
              '${post.commentCount} 条点评和回复',
              '${post.commentCount} пікір мен жауап',
              'Отзывов и ответов: ${post.commentCount}');
      main = FilledButton(
          key: const Key('post-ready-to-build'),
          onPressed: recruit == null
              ? null
              : () async {
                  final ok = await attempt(
                      context,
                      () => context
                          .read(postRepositoryProvider)
                          .updatePost(post.copyWith(openForBuilders: true)));
                  if (ok != null) recruit();
                },
          child: Text(tr3('准备开建？为它找人', 'Салуға дайынсыз ба?',
              'Готовы строить? Найти мастеров')));
    } else if (mine) {
      if (open.isEmpty && recruit == null) return null;
      summary = open.isEmpty
          ? building
              ? tr3('施工中', 'Құрылыс жүріп жатыр', 'Идёт стройка')
              : tr3('还没为它找人', 'Әлі ешкім ізделмейді', 'Пока никого не ищете')
          : tr3('在招 ${open.length} 个阶段', '${open.length} кезең ашық',
              'Открыто этапов: ${open.length}');
      main = FilledButton(
          key: const Key('post-main-action'),
          onPressed: open.isEmpty ? recruit : openDemand,
          child: Text(open.isEmpty
              ? building
                  ? tr3('招下一个阶段', 'Келесі кезең', 'Следующий этап')
                  : tr3('为这栋房子找人', 'Адам іздеу', 'Найти мастеров')
              : tr3('管理找人', 'Іздеуді басқару', 'Управлять поиском')));
    } else if (isPro && (open.isNotEmpty || post.openForBuilders)) {
      summary = open.isNotEmpty
          ? tr3('${open.length} 个阶段在招人', '${open.length} кезең ашық',
              'Открыто этапов: ${open.length}')
          : tr3('房主在找施工方', 'Құрылысшы іздейді', 'Ищет строителей');
      main = FilledButton(
          key: const Key('post-main-action'),
          onPressed: open.isEmpty ? contact : openDemand,
          child: Text(open.isEmpty
              ? tr3('我能建这栋房子', 'Мен сала аламын', 'Я могу построить')
              : tr3('去报名 / 报价', 'Өтінім беру', 'Откликнуться')));
    } else {
      // A visitor: like and comment sit in the bar with their counts, as
      // in any feed; the main button starts their own house from this one.
      final like = OptimisticLike(
          liked: liked,
          toggle: () => attempt(context,
              () => context.read(postRepositoryProvider).toggleLike(post.id)),
          builder: (context, liked, toggle) => _CountAction(
              tooltip: tr3('收藏', 'Сақтау', 'Сохранить'),
              count: post.likeCount,
              color: liked ? t.accent : null,
              icon: PopOnActive(
                  active: liked,
                  child: Icon(liked ? Icons.favorite : Icons.favorite_border,
                      size: 22, color: liked ? t.accent : null)),
              onTap: toggle));
      final comment = _CountAction(
          key: const Key('post-comment'),
          tooltip: tr3('写点评', 'Пікір жазу', 'Написать отзыв'),
          count: post.commentCount,
          icon: const Icon(Icons.chat_bubble_outline, size: 21),
          onTap: () => openCritiqueComposer(context, post));
      return ActionBar(
          child: Row(children: [
        if (canReuse) ...[
          like,
          comment,
          const SizedBox(width: 8),
          Expanded(
              child: FilledButton.icon(
                  key: const Key('post-main-action'),
                  onPressed: () => startFromPost(context, post),
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                  label: Text(startFromThis(),
                      maxLines: 1, overflow: TextOverflow.ellipsis))),
        ] else ...[
          Expanded(
              child: InkWell(
                  borderRadius: BorderRadius.circular(YRadius.pill),
                  onTap: () => openCritiqueComposer(context, post),
                  child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(YRadius.pill)),
                      child: Text(tr3('说说你的看法…', 'Пікіріңіз…', 'Что думаете?'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.muted))))),
          const SizedBox(width: 4),
          like,
          comment,
        ],
      ]));
    }
    return ActionBar(
        child: Row(children: [
      Expanded(
          child: Text(summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
      const SizedBox(width: 12),
      // The button takes the width its words need (up to most of the
      // bar) rather than half of it, where a long label broke in two.
      ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.62),
          child: main),
    ]));
  }
}

/// "谁在建这栋房子": the pros on it and what has been inspected so far.
class _BuildSection extends StatelessWidget {
  const _BuildSection(
      {required this.info, required this.mine, required this.shown});
  final PostBuild info;
  final bool mine;
  final bool shown;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final b = info;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(b.finished
          ? tr3('谁建了这栋房子', 'Бұл үйді кім салды', 'Кто построил этот дом')
          : tr3('谁在建这栋房子', 'Бұл үйді кім салып жатыр', 'Кто строит этот дом')),
      if (mine && !shown)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Hint(tr3(
                '只有你能看到这一段。可以在右上角“…”里公开给访客。',
                'Мұны тек сіз көресіз.',
                'Видите только вы. Откройте через «…».'))),
      if (b.agreedAmount > 0)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                tr3(
                    '已验收 ${money(b.acceptedAmount)} / 约定 ${money(b.agreedAmount)}',
                    '${money(b.acceptedAmount)} / ${money(b.agreedAmount)} қабылданды',
                    'Принято ${money(b.acceptedAmount)} из ${money(b.agreedAmount)}'),
                style: const TextStyle(fontWeight: FontWeight.w600))),
      for (final x in b.builders)
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(x.profile.name),
            title: Text(x.profile.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${x.scope} · ${x.ended ? tr3('已完工', 'Аяқталды', 'Завершено') : tr3('施工中', 'Жүріп жатыр', 'В работе')}',
                style: TextStyle(color: t.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushPage<void>(
                context, (_) => ProfilePage(profileId: x.profile.id))),
      Text(
          tr3(
              '金额来自双方确认的约定和节点验收记录，Yusal 不经手付款。',
              'Сомалар келісім мен қабылдау жазбаларынан.',
              'Суммы из соглашений и записей приёмки; Yusal не принимает платежи.'),
          style: TextStyle(color: t.muted, fontSize: YFont.caption)),
    ]);
  }
}

/// The house at a glance, right under the title: size, floors, rooms,
/// footprint and the estimate, so a visitor never has to scroll for them.
class _FactSheet extends StatelessWidget {
  const _FactSheet({required this.post, required this.snapshot});
  final HousePost post;
  final DesignSnapshot? snapshot;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    Widget cell(IconData icon, String value, String label) => Expanded(
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(YRadius.control)),
            child: Column(children: [
              Icon(icon, color: t.accent),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: YFont.body,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Text(label,
                  style: TextStyle(color: t.muted, fontSize: YFont.caption)),
            ])));
    final summary = snapshot?.summary ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        cell(Icons.square_foot, '${post.area.round()} $sqm',
            tr3('建筑面积', 'Ауданы', 'Площадь')),
        const SizedBox(width: 8),
        cell(Icons.layers_outlined, '${post.floors}',
            tr3('层数', 'Қабат', 'Этажей')),
        const SizedBox(width: 8),
        cell(Icons.meeting_room_outlined, '${post.rooms}',
            tr3('房间', 'Бөлме', 'Комнат')),
      ]),
      if (post.estimatedCost != null)
        Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: t.accentSoft,
                borderRadius: BorderRadius.circular(YRadius.control)),
            child: Row(children: [
              YusalIcon(YIcon.budget, color: t.accent),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(tr3('预估造价', 'Болжамды құн', 'Оценка стоимости'),
                      style: TextStyle(color: t.muted))),
              Text('≈ ${money(post.estimatedCost)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: YFont.body,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ])),
      if (summary.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(summary,
                style: TextStyle(color: t.muted, fontSize: YFont.small))),
    ]);
  }
}

/// The first lines of the design's bill of quantities.
class _Quantities extends StatelessWidget {
  const _Quantities({required this.snapshot});
  final DesignSnapshot snapshot;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in snapshot.lines.take(6))
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                    child: Text(l.name,
                        style: const TextStyle(fontSize: YFont.label))),
                Text(
                    l.quantity == null
                        ? tr3('现场确认', 'Орнында', 'На месте')
                        : '${numText(l.quantity!)} ${unitLabel(l.unit)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: YFont.label,
                        fontFeatures: YText.tabular)),
              ])),
      ]);
}

/// Rate and say something. One rating per person; a new one replaces it.

/// Back, or "home" when the page was opened from a shared link and has
/// nothing to go back to.
class _PostLeading extends StatelessWidget {
  const _PostLeading({required this.fromLink});
  final bool fromLink;
  @override
  Widget build(BuildContext context) => Center(
      child: fromLink
          ? IconAction(
              label: tr3('首页', 'Басты бет', 'Главная'),
              icon: const Icon(Icons.home_outlined, size: 20),
              onPressed: () => Navigator.of(context)
                  .pushReplacement(platformRoute((_) => const PlatformShell())))
          : IconAction(
              label: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => Navigator.maybePop(context)));
}

/// The house page's cover: where a tapped list card's picture lands.
/// Completes once [route] has finished coming in (at once if it has).
Future<void> _settled(ModalRoute<Object?>? route) {
  final a = route?.animation;
  if (a == null || a.status != AnimationStatus.forward) return Future.value();
  final done = Completer<void>();
  void listen(AnimationStatus s) {
    if (s == AnimationStatus.forward) return;
    a.removeStatusListener(listen);
    done.complete();
  }

  a.addStatusListener(listen);
  return done.future;
}

class _PostCover extends StatelessWidget {
  const _PostCover(
      {super.key, required this.post, this.image, this.loading = false});
  final HousePost post;
  final ImageProvider? image;
  final bool loading;
  @override
  Widget build(BuildContext context) => HeroTarget(
      heroKey: houseHeroKey(post.id),
      // The plan sits contained on its sheet in both places: laid out at
      // each frame's size it morphs exactly, where cropping would make it
      // jump as the flight starts.
      cropInFlight: false,
      child: Cover(
          icon: Icons.home_outlined,
          seed: post.id,
          height: 300,
          image: image,
          child: image == null && !loading && post.snapshotId.isNotEmpty
              ? PlanCover(snapshotId: post.snapshotId, postId: post.id)
              : null));
}

/// While the house loads: the same app bar and cover, so the page does
/// not jump when the rest arrives.
class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton({required this.post, required this.coverKey});
  final HousePost post;
  final GlobalKey coverKey;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Scaffold(
        body: CustomScrollView(slivers: [
      SliverAppBar(
          pinned: true,
          expandedHeight: _coverHeight,
          backgroundColor: t.bg,
          surfaceTintColor: Colors.transparent,
          leading: _PostLeading(fromLink: !Navigator.of(context).canPop()),
          flexibleSpace: FlexibleSpaceBar(
              background: _CoverFrame(
                  child: PostPicture(
                      post: post,
                      builder: (context, image, loading) => _PostCover(
                          key: coverKey,
                          post: post,
                          image: image,
                          loading: loading))))),
      SliverToBoxAdapter(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(post.title, style: display()),
                            const SizedBox(height: YSpace.xl),
                            const SkeletonList(count: 4),
                          ]))))),
    ]));
  }
}

/// Height of the cover while the page is at the top: the drawing gets most
/// of the first screen, as a photo does in a feed post.
const double _coverHeight = 340;

/// The cover's frame: the drawing sits below the status bar and the back /
/// share controls instead of under them, on the same paper as the sheet,
/// and a tap opens the full drawings.
class _CoverFrame extends StatelessWidget {
  const _CoverFrame({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight - 8;
    return ColoredBox(
        color: YTokens.paper,
        child: Padding(
            padding: EdgeInsets.only(top: top),
            child: Semantics(
                button: onTap != null,
                label: onTap == null
                    ? null
                    : tr3('查看图纸', 'Сызбаны көру', 'Посмотреть чертежи'),
                child: GestureDetector(onTap: onTap, child: child))));
  }
}

/// Region, rating and likes on one line under the title.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.post});
  final HousePost post;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final muted = TextStyle(color: t.muted, fontSize: YFont.small);
    Widget dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: muted));
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      YusalIcon(YIcon.nearby, size: 15, color: t.muted),
      const SizedBox(width: 2),
      Text(regionName(post.region), style: muted),
      if (post.rating != null) ...[
        dot(),
        Icon(Icons.star_rounded, size: 15, color: t.accent),
        const SizedBox(width: 2),
        Text('${post.rating!.toStringAsFixed(1)} (${post.ratingCount})',
            style: muted.copyWith(color: t.ink, fontWeight: FontWeight.w600)),
      ],
      if (post.likeCount > 0) ...[
        dot(),
        Text(
            tr3('${post.likeCount} 人喜欢', '${post.likeCount} ұнатты',
                'Нравится: ${post.likeCount}'),
            style: muted),
      ],
    ]);
  }
}

/// The author, right under the title, with a way to write to them.
class _Byline extends StatelessWidget {
  const _Byline(
      {required this.post, required this.mine, required this.onContact});
  final HousePost post;
  final bool mine;
  final VoidCallback onContact;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<Account?>(
        provider: accountProvider(post.ownerId),
        loading: const SkeletonRow(avatar: true, avatarSize: 36),
        builder: (context, a) => Row(children: [
              Avatar(a?.displayName ?? '', size: 36),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(deletedName(a),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: YFont.label)),
                    Text(
                        mine
                            ? tr3('这是你的设计', 'Сіздің жобаңыз', 'Ваш проект')
                            : tr3('设计者 · ${fmtDay(post.createdAt)} 发布', 'Автор',
                                'Автор · ${fmtDay(post.createdAt)}'),
                        style:
                            TextStyle(color: t.muted, fontSize: YFont.caption)),
                  ])),
              if (!mine)
                OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: onContact,
                    icon: const Icon(Icons.chat_outlined, size: 16),
                    label: Text(tr3('私信', 'Жазу', 'Написать'))),
            ]));
  }
}

/// The author's words. A long story folds after a few lines so the facts
/// and the drawings stay close; one tap opens the rest.
class _Story extends StatefulWidget {
  const _Story({required this.text});
  final String text;
  @override
  State<_Story> createState() => _StoryState();
}

class _StoryState extends State<_Story> {
  bool open = false;
  static const _lines = 6;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    const style = TextStyle(fontSize: YFont.body, height: 1.6);
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context))
        ..layout(maxWidth: c.maxWidth);
      final long = tp.didExceedMaxLines;
      tp.dispose();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.text,
            style: style,
            maxLines: open || !long ? null : _lines,
            overflow: open || !long ? null : TextOverflow.ellipsis),
        if (long)
          TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  foregroundColor: t.accent),
              onPressed: () => setState(() => open = !open),
              child: Text(open
                  ? tr3('收起', 'Жию', 'Свернуть')
                  : tr3('展开全文', 'Толығырақ', 'Читать полностью'))),
      ]);
    });
  }
}

/// An icon with its count beside it, as in a feed's action bar.
class _CountAction extends StatelessWidget {
  const _CountAction(
      {super.key,
      required this.tooltip,
      required this.count,
      required this.icon,
      required this.onTap,
      this.color});
  final String tooltip;
  final int count;
  final Widget icon;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Tooltip(
        message: tooltip,
        child: Semantics(
            button: true,
            label: tooltip,
            excludeSemantics: true,
            child: InkWell(
                borderRadius: BorderRadius.circular(YRadius.pill),
                onTap: onTap,
                child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: 44, minWidth: 44),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          icon,
                          if (count > 0) ...[
                            const SizedBox(width: 4),
                            Text('$count',
                                style: TextStyle(
                                    color: color ?? t.ink,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: YText.tabular)),
                          ],
                        ]))))));
  }
}
