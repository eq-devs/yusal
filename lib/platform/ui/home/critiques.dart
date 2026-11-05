import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// "What the author wants to hear about": the focus topics of a shared
/// house, shown under its title.
class FeedbackAsk extends StatelessWidget {
  const FeedbackAsk({super.key, required this.post});
  final HousePost post;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Container(
        key: const Key('feedback-ask'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(yRadius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.forum_outlined, size: 18, color: t.accent),
            const SizedBox(width: 6),
            Text(tr3('作者在求点评', 'Автор пікір сұрайды', 'Автор просит отзывы'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if (post.focus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Text(tr3('最想听听：', 'Ең алдымен:', 'Важнее всего:'),
                  style: TextStyle(color: t.muted, fontSize: 13)),
              for (final f in post.focus)
                StatusPill(feedbackTopicName(f), color: t.accent),
            ]),
          ],
        ]));
  }
}

/// Critiques of a house: a composer (with topic and rating), a topic
/// filter, useful ones first, one level of replies. The author replies and
/// marks critiques useful instead of rating their own house.
class CritiqueSection extends StatefulWidget {
  const CritiqueSection(
      {super.key,
      required this.post,
      required this.comments,
      required this.mine,
      required this.meId});
  final HousePost post;
  final List<PostComment> comments;
  final bool mine;
  final String? meId;
  @override
  State<CritiqueSection> createState() => _CritiqueSectionState();
}

class _CritiqueSectionState extends State<CritiqueSection> {
  String? topic;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final all = widget.comments;
    final top = all.where((c) => c.parentId == null).toList();
    final replies = <String, List<PostComment>>{};
    for (final c in all.where((c) => c.parentId != null))
      replies.putIfAbsent(c.parentId!, () => []).add(c);
    for (final r in replies.values)
      r.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final topics = {
      for (final c in top)
        if (c.topic != null) c.topic!
    };
    final shown = top.where((c) => topic == null || c.topic == topic).toList()
      ..sort((a, b) => a.helpful == b.helpful
          ? b.createdAt.compareTo(a.createdAt)
          : (a.helpful ? -1 : 1));
    final helpful = top.where((c) => c.helpful).length;
    final asking = !widget.post.openForBuilders;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
          '${asking ? tr3('点评', 'Пікірлер', 'Отзывы') : tr3('评价', 'Пікірлер', 'Отзывы')} · ${top.length}',
          trailing: helpful > 0
              ? Text(
                  tr3('$helpful 条作者觉得有用', '$helpful пайдалы',
                      'Полезных: $helpful'),
                  style: TextStyle(color: t.muted, fontSize: 13))
              : null),
      if (!widget.mine) _CritiqueBox(post: widget.post),
      if (topics.length > 1 || (topics.isNotEmpty && topic != null))
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(
                      label: tr3('全部', 'Барлығы', 'Все'),
                      selected: topic == null,
                      onTap: () => setState(() => topic = null)),
                  for (final k in feedbackTopics)
                    if (topics.contains(k))
                      _Chip(
                          key: Key('critique-topic-$k'),
                          label:
                              '${feedbackTopicName(k)} ${top.where((c) => c.topic == k).length}',
                          selected: topic == k,
                          onTap: () =>
                              setState(() => topic = topic == k ? null : k)),
                ]))),
      if (top.isEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                widget.mine
                    ? tr3('还没有点评。分享给朋友或懂行的师傅看看。', 'Әлі пікір жоқ.',
                        'Отзывов пока нет. Поделитесь с друзьями или мастерами.')
                    : tr3('还没有点评。第一个说说看法吧。', 'Әлі пікір жоқ.',
                        'Отзывов пока нет. Будьте первым.'),
                style: TextStyle(color: t.muted))),
      for (final c in shown) ...[
        _CritiqueTile(
            comment: c,
            post: widget.post,
            canDelete: widget.mine || c.authorId == widget.meId,
            canMarkHelpful: widget.mine && c.authorId != widget.meId,
            canReply: widget.meId != null),
        for (final r in replies[c.id] ?? const <PostComment>[])
          Padding(
              padding: const EdgeInsets.only(left: 46),
              child: _CritiqueTile(
                  comment: r,
                  post: widget.post,
                  reply: true,
                  canDelete: widget.mine || r.authorId == widget.meId)),
      ],
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap()));
}

class _CritiqueBox extends StatefulWidget {
  const _CritiqueBox({required this.post});
  final HousePost post;
  @override
  State<_CritiqueBox> createState() => _CritiqueBoxState();
}

class _CritiqueBoxState extends State<_CritiqueBox> {
  final text = TextEditingController();
  int? rating;
  String? topic;
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
      await context.repos
          .comment(widget.post.id, text.text, rating: rating, topic: topic);
      text.clear();
      setState(() {
        rating = null;
        topic = null;
      });
    } on ApiFailure catch (f) {
      if (mounted) toast(context, failureText(f));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final focus = widget.post.focus;
    final order = [
      ...focus,
      for (final k in feedbackTopics)
        if (!focus.contains(k)) k
    ];
    return YCard(
        color: t.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              tr3('说说哪方面？（可选）', 'Қай жағы туралы?',
                  'О чём отзыв? (необязательно)'),
              style: TextStyle(color: t.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in order)
              ChoiceChip(
                  key: Key('critique-pick-$k'),
                  label: Text(feedbackTopicName(k)),
                  selected: topic == k,
                  showCheckmark: false,
                  avatar: focus.contains(k) && topic != k
                      ? Icon(Icons.star_rounded, size: 14, color: t.accent)
                      : null,
                  onSelected: (_) =>
                      setState(() => topic = topic == k ? null : k)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => rating = rating == i ? null : i),
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
                        ? tr3('整体打个分（可选）', 'Бағалаңыз', 'Общая оценка')
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
                    key: const Key('critique-text'),
                    controller: text,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                        hintText: topic == null
                            ? tr3('说说布局、造价、施工上的看法…', 'Пікіріңіз…',
                                'Что думаете о планировке, цене, стройке…')
                            : tr3('关于${feedbackTopicName(topic!)}，你的建议是…',
                                'Ұсынысыңыз…', 'Ваш совет…')))),
            const SizedBox(width: 8),
            FilledButton(
                key: const Key('critique-send'),
                onPressed: busy ? null : send,
                child: Text(tr3('发布', 'Жіберу', 'Отправить'))),
          ]),
        ]));
  }
}

class _CritiqueTile extends StatelessWidget {
  const _CritiqueTile(
      {required this.comment,
      required this.post,
      required this.canDelete,
      this.canMarkHelpful = false,
      this.canReply = false,
      this.reply = false});
  final PostComment comment;
  final HousePost post;
  final bool canDelete, canMarkHelpful, canReply, reply;

  Future<void> _reply(BuildContext context) async {
    final text = await askText(context, tr3('回复', 'Жауап', 'Ответить'),
        hint: tr3('补充或回答', 'Жауап', 'Ответ'));
    if (text == null || !context.mounted) return;
    await attempt(context,
        () => context.repos.comment(post.id, text, parentId: comment.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = comment;
    return Padding(
        padding: EdgeInsets.only(top: reply ? 10 : 16),
        child: Live<(Account?, List<ServiceProfile>)>(
            load: (r) async =>
                (await r.account(c.authorId), await r.profilesOf(c.authorId)),
            builder: (context, data) {
              final (a, profiles) = data;
              final pro = profiles.firstOrNull;
              final isAuthor = c.authorId == post.ownerId;
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                        onTap: pro == null
                            ? null
                            : () => pushPage<void>(
                                context, (_) => ProfilePage(profileId: pro.id)),
                        child: Avatar(a?.displayName ?? '',
                            size: reply ? 28 : 36,
                            team: pro?.kind == ProfileKind.team)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(deletedName(a),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                if (isAuthor)
                                  StatusPill(tr3('作者', 'Автор', 'Автор'),
                                      color: t.ink)
                                else if (pro != null)
                                  StatusPill(proRoleName(pro.role),
                                      color: t.accent),
                                Text(ago(c.createdAt, context.now),
                                    style: TextStyle(
                                        color: t.faint, fontSize: 12)),
                              ]),
                          if (c.helpful || c.topic != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 6, children: [
                                  if (c.helpful)
                                    StatusPill(
                                        tr3('作者觉得有用', 'Автор: пайдалы',
                                            'Автор: полезно'),
                                        color: t.ok,
                                        filled: true),
                                  if (c.topic != null)
                                    StatusPill(feedbackTopicName(c.topic!),
                                        color: t.muted),
                                ])),
                          if (c.rating != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Stars(c.rating!.toDouble())),
                          if (c.text.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(c.text,
                                    style: const TextStyle(height: 1.4))),
                          if (canReply || canMarkHelpful)
                            Wrap(spacing: 4, children: [
                              if (canReply)
                                TextButton(
                                    key: Key('critique-reply-${c.id}'),
                                    style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        foregroundColor: t.muted),
                                    onPressed: () => _reply(context),
                                    child:
                                        Text(tr3('回复', 'Жауап', 'Ответить'))),
                              if (canMarkHelpful)
                                TextButton.icon(
                                    key: Key('critique-helpful-${c.id}'),
                                    style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor:
                                            c.helpful ? t.ok : t.muted),
                                    onPressed: () => attempt(
                                        context,
                                        () => context.repos
                                            .markHelpful(c.id, !c.helpful)),
                                    icon: Icon(
                                        c.helpful
                                            ? Icons.thumb_up_alt
                                            : Icons.thumb_up_alt_outlined,
                                        size: 16),
                                    label: Text(c.helpful
                                        ? tr3('已标有用', 'Пайдалы', 'Полезно')
                                        : tr3('有用', 'Пайдалы', 'Полезно'))),
                            ]),
                        ])),
                    if (canDelete)
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr3('删除', 'Жою', 'Удалить'),
                          icon: Icon(Icons.close, size: 16, color: t.faint),
                          onPressed: () => attempt(context,
                              () => context.repos.deleteComment(c.id))),
                  ]);
            }));
  }
}
