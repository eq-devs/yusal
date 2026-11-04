import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/settings.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../cards.dart';
import '../design/plan_viewer.dart';
import '../chat/chat_page.dart';
import '../demand/demand_detail_page.dart';
import '../demand/publish_page.dart';
import '../l10n.dart';
import '../links.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'house_card.dart';

/// One house: the plan, the facts, the story, the people recruiting for
/// it, and what others think. The owner recruits from here; a
/// professional applies or writes from here.
class PostPage extends StatelessWidget {
  const PostPage({super.key, required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    return Live<
            (
              HousePost?,
              bool,
              List<Demand>,
              List<PostComment>,
              DesignSnapshot?
            )>(
        reloadKey: postId,
        load: (r) async {
          final p = await r.post(postId);
          if (p == null)
            return (null, false, const <Demand>[], const <PostComment>[], null);
          return (
            p,
            await r.liked(postId),
            await r.demandsForPost(postId),
            await r.comments(postId),
            await r.snapshot(p.snapshotId, postId: p.id)
          );
        },
        builder: (context, data) {
          final (p, liked, demands, comments, snap) = data;
          if (p == null)
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
          final me = context.repos.currentAccount;
          final mine = me?.id == p.ownerId;
          final image = p.preview == null
              ? null
              : MemoryImage(Uint8List.fromList(p.preview!));
          final open =
              demands.where((d) => d.status == DemandStatus.open).toList();

          Future<void> contact() async {
            if (!await requireLogin(context) || !context.mounted) return;
            final conv = await attempt(
                context, () => context.repos.openConversation(p.ownerId));
            if (conv != null && context.mounted)
              await pushPage<void>(
                  context, (_) => ChatPage(conversationId: conv.id));
          }

          Future<void> recruit() async {
            if (snap == null) return;
            await pushPage<void>(
                context,
                (_) =>
                    PublishPage(snapshot: snap, designProjectId: p.projectId));
          }

          Future<void> share() async {
            if (context.isDemo) {
              toast(
                  context,
                  tr3(
                      '演示分享：新发布作品仅当前会话可见，链接不能跨设备打开。',
                      'Демо: жаңа жарияланымдар басқа құрылғыда ашылмайды.',
                      'Демо: новые публикации не открываются на других устройствах.'));
            }
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
              if (context.mounted)
                toast(
                    context,
                    context.isDemo
                        ? tr3(
                            '已复制演示链接；新作品仅本次会话可见',
                            'Демо сілтеме көшірілді; жаңа жоба тек осы сеанста',
                            'Демо-ссылка скопирована; новые проекты доступны только в этом сеансе')
                        : tr3(
                            '已复制，任何人打开都能看',
                            'Көшірілді, кез келген адам аша алады',
                            'Скопировано, откроется у любого'));
            } else {
              try {
                await SharePlus.instance
                    .share(ShareParams(text: '${p.title}\n$link'));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted)
                  toast(
                      context,
                      tr3('此设备不支持系统分享，已复制链接', 'Сілтеме көшірілді',
                          'Ссылка скопирована'));
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
                    () => context.repos.updatePost(
                        p.copyWith(title: title, story: story ?? p.story)));
              case 'builders':
                await attempt(
                    context,
                    () => context.repos.updatePost(
                        p.copyWith(openForBuilders: !p.openForBuilders)));
              case 'hide':
                if (await confirmDialog(
                        context, tr3('下架这栋房子？', 'Жасыру?', 'Скрыть дом?'),
                        danger: true) &&
                    context.mounted) {
                  await attempt(context, () => context.repos.hidePost(p.id));
                  if (context.mounted) Navigator.of(context).pop();
                }
              case 'report':
                final reason =
                    await askText(context, tr3('举报原因', 'Себебі', 'Причина'));
                if (reason != null && context.mounted)
                  await attempt(
                      context,
                      () => context.repos.report(ReportTarget.account,
                          p.ownerId, '[post ${p.id}] $reason'),
                      success: tr3('已收到举报', 'Қабылданды', 'Жалоба отправлена'));
            }
          }

          final fromLink = !Navigator.of(context).canPop();
          return Scaffold(
              body: CustomScrollView(slivers: [
                SliverAppBar(
                    pinned: true,
                    expandedHeight: 280,
                    backgroundColor: t.bg,
                    // Opened from a shared link: no page to go back to, so
                    // offer the home feed instead.
                    leading: fromLink
                        ? IconButton(
                            tooltip: tr3('首页', 'Басты бет', 'Главная'),
                            icon: const Icon(Icons.home_outlined),
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(platformRoute(
                                    (_) => const PlatformShell())))
                        : null,
                    actions: [
                      IconButton(
                          tooltip: tr3('分享', 'Бөлісу', 'Поделиться'),
                          icon: const Icon(Icons.ios_share),
                          onPressed: share),
                      IconButton(
                          icon: Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                              color: liked ? t.accent : null),
                          onPressed: () => attempt(
                              context, () => context.repos.toggleLike(p.id))),
                      IconButton(
                          icon: const Icon(Icons.more_horiz), onPressed: more),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                        background: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                            child: Cover(
                                icon: Icons.home_outlined,
                                seed: p.id,
                                height: 300,
                                image: image)))),
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
                                      Text(p.title, style: display(size: 26)),
                                      const SizedBox(height: 4),
                                      Text(houseFacts(p),
                                          style: TextStyle(
                                              color: t.muted, fontSize: 15)),
                                      const SizedBox(height: 6),
                                      Row(children: [
                                        if (p.rating != null) ...[
                                          Icon(Icons.star,
                                              size: 16, color: t.ink),
                                          const SizedBox(width: 4),
                                          Text(
                                              '${p.rating!.toStringAsFixed(1)} · ${p.ratingCount} ${tr3('个评分', 'баға', 'оценок')}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 14),
                                        ],
                                        Icon(Icons.favorite,
                                            size: 15, color: t.faint),
                                        const SizedBox(width: 4),
                                        Text('${p.likeCount}',
                                            style: TextStyle(color: t.muted)),
                                      ]),
                                      if (p.tags.isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 10),
                                            child: Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  for (final tag in p.tags)
                                                    StatusPill(postTagName(tag))
                                                ])),
                                      const Divider(height: 32),
                                      // Owner.
                                      Live<Account?>(
                                          load: (r) => r.account(p.ownerId),
                                          builder: (context, a) =>
                                              Row(children: [
                                                Avatar(a?.displayName ?? '',
                                                    size: 44),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                      Text(deletedName(a),
                                                          style:
                                                              const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  fontSize:
                                                                      15)),
                                                      Text(
                                                          mine
                                                              ? tr3(
                                                                  '这是你的设计',
                                                                  'Сіздің жобаңыз',
                                                                  'Ваш проект')
                                                              : tr3(
                                                                  '设计者 · ${fmtDay(p.createdAt)} 发布',
                                                                  'Автор',
                                                                  'Автор · ${fmtDay(p.createdAt)}'),
                                                          style: TextStyle(
                                                              color: t.muted,
                                                              fontSize: 13)),
                                                    ])),
                                                if (!mine)
                                                  OutlinedButton(
                                                      onPressed: contact,
                                                      child: Text(tr3('私信',
                                                          'Жазу', 'Написать'))),
                                              ])),
                                      if (p.story.isNotEmpty) ...[
                                        const SizedBox(height: 18),
                                        Text(p.story,
                                            style: const TextStyle(
                                                fontSize: 16, height: 1.5)),
                                      ],
                                      PlanAttachment(snapshot: snap),
                                      // Facts from the design.
                                      SectionTitle(tr3('设计数据', 'Жоба деректері',
                                          'Данные проекта')),
                                      _Facts(post: p, snapshot: snap),
                                      // Recruiting.
                                      SectionTitle(
                                          tr3('为这栋房子找人', 'Осы үйге адам іздеу',
                                              'Кто нужен для этого дома'),
                                          trailing: mine && snap != null
                                              ? TextButton.icon(
                                                  onPressed: recruit,
                                                  icon: const Icon(Icons.add,
                                                      size: 18),
                                                  label: Text(tr3(
                                                      '招人', 'Іздеу', 'Найти')))
                                              : null),
                                      if (demands.isEmpty)
                                        Text(
                                            mine
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
                                      // Reviews.
                                      SectionTitle(
                                          '${tr3('评价', 'Пікірлер', 'Отзывы')} · ${comments.length}'),
                                      if (!mine) _CommentBox(post: p),
                                      if (comments.isEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                                tr3(
                                                    '还没有评价。第一个说说看法吧。',
                                                    'Әлі пікір жоқ.',
                                                    'Отзывов пока нет.'),
                                                style:
                                                    TextStyle(color: t.muted))),
                                      for (final c in comments)
                                        _CommentTile(
                                            comment: c,
                                            canDelete:
                                                mine || c.authorId == me?.id),
                                    ]))))),
              ]),
              bottomNavigationBar: mine || open.isEmpty && !p.openForBuilders
                  ? null
                  : ActionBar(
                      child: Row(children: [
                      Expanded(
                          child: Text(
                              open.isNotEmpty
                                  ? tr3(
                                      '在招 ${open.length} 个需求',
                                      '${open.length} тапсырыс',
                                      'Открыто заявок: ${open.length}')
                                  : tr3('设计者在找施工方', 'Құрылысшы іздейді',
                                      'Ищет строителей'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      FilledButton(
                          onPressed: open.length == 1
                              ? () => pushPage<void>(
                                  context,
                                  (_) =>
                                      DemandDetailPage(demandId: open.first.id))
                              : open.isEmpty
                                  ? contact
                                  : () => pushPage<void>(
                                      context,
                                      (_) => DemandDetailPage(
                                          demandId: open.first.id)),
                          child: Text(open.isEmpty
                              ? tr3('我能建这栋房子', 'Мен сала аламын',
                                  'Я могу построить')
                              : tr3(
                                  '去报名 / 报价', 'Өтінім беру', 'Откликнуться'))),
                    ])));
        });
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.post, required this.snapshot});
  final HousePost post;
  final DesignSnapshot? snapshot;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    Widget cell(IconData icon, String value, String label) => Expanded(
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: t.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Icon(icon, color: t.accent),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              Text(label, style: TextStyle(color: t.muted, fontSize: 12)),
            ])));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        cell(Icons.square_foot, '${post.area.round()} m²',
            tr3('建筑面积', 'Ауданы', 'Площадь')),
        const SizedBox(width: 8),
        cell(Icons.layers_outlined, '${post.floors}',
            tr3('层数', 'Қабат', 'Этажей')),
        const SizedBox(width: 8),
        cell(Icons.meeting_room_outlined, '${post.rooms}',
            tr3('房间', 'Бөлме', 'Комнат')),
      ]),
      if (post.estimatedCost != null)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InfoRow(tr3('预估造价', 'Болжамды құн', 'Оценка стоимости'),
                '≈ ${money(post.estimatedCost)}',
                icon: Icons.payments_outlined)),
      if (snapshot != null && snapshot!.summary.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(snapshot!.summary,
                style: TextStyle(color: t.muted, fontSize: 13))),
      if (snapshot != null && snapshot!.lines.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final l in snapshot!.lines.take(6))
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                    child: Text(l.name, style: const TextStyle(fontSize: 14))),
                Text(
                    l.quantity == null
                        ? tr3('现场确认', 'Орнында', 'На месте')
                        : '${numText(l.quantity!)} ${unitLabel(l.unit)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ])),
      ],
    ]);
  }
}

/// Rate and say something. One rating per person; a new one replaces it.
class _CommentBox extends StatefulWidget {
  const _CommentBox({required this.post});
  final HousePost post;
  @override
  State<_CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends State<_CommentBox> {
  final text = TextEditingController();
  int? rating;
  bool busy = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (text.text.trim().isEmpty && rating == null) return;
    if (!await requireLogin(context) || !mounted) return;
    setState(() => busy = true);
    try {
      await context.repos.comment(widget.post.id, text.text, rating: rating);
      text.clear();
      setState(() => rating = null);
    } on ApiFailure catch (f) {
      if (mounted) toast(context, failureText(f));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return YCard(
        color: t.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (var i = 1; i <= 5; i++)
              InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () =>
                      setState(() => rating = rating == i ? null : i),
                  child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                          i <= (rating ?? 0) ? Icons.star : Icons.star_border,
                          size: 24,
                          color: t.accent))),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    rating == null
                        ? tr3('打个分', 'Бағалаңыз', 'Оценка')
                        : [
                            '',
                            tr3('不推荐', 'Ұсынбаймын', 'Не советую'),
                            tr3('一般', 'Орташа', 'Так себе'),
                            tr3('还行', 'Жақсы', 'Нормально'),
                            tr3('不错', 'Өте жақсы', 'Хорошо'),
                            tr3('很好', 'Керемет', 'Отлично'),
                          ][rating!],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 13))),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                        hintText: tr3('说说布局、造价、施工上的看法…', 'Пікіріңіз…',
                            'Что думаете о планировке, цене, стройке…')))),
            const SizedBox(width: 8),
            FilledButton(
                onPressed: busy ? null : send,
                child: Text(tr3('发布', 'Жіберу', 'Отправить'))),
          ]),
        ]));
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.canDelete});
  final PostComment comment;
  final bool canDelete;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = comment;
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Live<(Account?, List<ServiceProfile>)>(
            load: (r) async =>
                (await r.account(c.authorId), await r.profilesOf(c.authorId)),
            builder: (context, data) {
              final (a, profiles) = data;
              final pro = profiles.firstOrNull;
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                        onTap: pro == null
                            ? null
                            : () => pushPage<void>(
                                context, (_) => ProfilePage(profileId: pro.id)),
                        child: Avatar(a?.displayName ?? '',
                            size: 36, team: pro?.kind == ProfileKind.team)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Flexible(
                                child: Text(deletedName(a),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                            if (pro != null) ...[
                              const SizedBox(width: 6),
                              StatusPill(proRoleName(pro.role),
                                  color: t.accent),
                            ],
                            const SizedBox(width: 8),
                            Text(ago(c.createdAt, context.now),
                                style: TextStyle(color: t.faint, fontSize: 12)),
                          ]),
                          if (c.rating != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Stars(c.rating!.toDouble())),
                          if (c.text.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(c.text,
                                    style: const TextStyle(height: 1.4))),
                        ])),
                    if (canDelete)
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, size: 16, color: t.faint),
                          onPressed: () => attempt(context,
                              () => context.repos.deleteComment(c.id))),
                  ]);
            }));
  }
}
