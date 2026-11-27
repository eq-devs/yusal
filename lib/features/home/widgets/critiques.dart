import 'package:flutter/material.dart';
import 'package:yusal/features/home/state/post.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/me/pages/trust.dart';
import 'package:yusal/features/profile/page.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

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
            YusalIcon(YIcon.chat, size: 18, color: t.ink),
            const SizedBox(width: 6),
            Text(tr3('作者在求点评', 'Автор пікір сұрайды', 'Автор просит отзывы', 'The author is asking for feedback', ky: 'Автор пикир сурап жатат', uz: 'Muallif fikr soʻramoqda'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if (post.focus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Text(tr3('最想听听：', 'Ең алдымен:', 'Важнее всего:', 'Most important:', ky: 'Эң маанилүүсү:', uz: 'Eng muhimi:'),
                  style: TextStyle(color: t.muted, fontSize: YFont.small)),
              for (final f in post.focus)
                StatusPill(feedbackTopicName(f)),
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
    for (final c in all.where((c) => c.parentId != null)) {
      replies.putIfAbsent(c.parentId!, () => []).add(c);
    }
    for (final r in replies.values) {
      r.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
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
          '${asking ? tr3('点评', 'Пікірлер', 'Отзывы', 'Reviews', ky: 'Пикирлер', uz: 'Sharhlar') : tr3('评价', 'Пікірлер', 'Отзывы', 'Reviews', ky: 'Пикирлер', uz: 'Sharhlar')} · ${top.length}',
          trailing: helpful > 0
              ? Text(
                  tr3('$helpful 条作者觉得有用', '$helpful пайдалы',
                      'Полезных: $helpful',
                      'Helpful: $helpful', ky: 'Пайдалуу: $helpful', uz: 'Foydali: $helpful'),
                  style: TextStyle(color: t.muted, fontSize: YFont.small))
              : null),
      if (!widget.mine) _ComposerEntry(post: widget.post),
      if (topics.length > 1 || (topics.isNotEmpty && topic != null))
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(
                      label: tr3('全部', 'Барлығы', 'Все', 'All', ky: 'Баары', uz: 'Hammasi'),
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
                        'Отзывов пока нет. Поделитесь с друзьями или мастерами.',
                        'No reviews yet. Share it with friends or pros.', ky: 'Азырынча пикир жок. Досторуңуз же адистер менен бөлүшүңүз.', uz: 'Hozircha sharh yoʻq. Doʻstlaringiz yoki mutaxassislar bilan ulashing.')
                    : tr3('还没有点评。第一个说说看法吧。', 'Әлі пікір жоқ.',
                        'Отзывов пока нет. Будьте первым.',
                        'No reviews yet. Be the first.', ky: 'Азырынча пикир жок. Биринчи болуңуз.', uz: 'Hozircha sharh yoʻq. Birinchi boʻling.'),
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

/// Opens the critique composer in a sheet. A guest signs in first, so no
/// one types a critique only to be stopped at "send".
Future<void> openCritiqueComposer(BuildContext context, HousePost post) async {
  if (!await requireLogin(context) || !context.mounted) return;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.viewInsetsOf(sheet).bottom + 16),
          child: SingleChildScrollView(
              child: _CritiqueBox(
                  post: post,
                  autofocus: true,
                  onSent: () => Navigator.of(sheet).pop()))));
}

/// What stands in for the composer in the list: one line that looks like
/// a field. The full composer (topic, stars, text) opens in a sheet, so the
/// critiques themselves come first, not a form.
class _ComposerEntry extends StatelessWidget {
  const _ComposerEntry({required this.post});
  final HousePost post;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.session.currentAccount;
    return Semantics(
        button: true,
        label: tr3('写点评', 'Пікір жазу', 'Написать отзыв', 'Write a review', ky: 'Пикир жазуу', uz: 'Sharh yozish'),
        excludeSemantics: true,
        child: InkWell(
            key: const Key('critique-open'),
            borderRadius: BorderRadius.circular(YRadius.pill),
            onTap: () => openCritiqueComposer(context, post),
            child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(YRadius.pill)),
                child: Row(children: [
                  me == null
                      ? SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(YIcons.edit,
                              size: 18, color: t.muted))
                      : Avatar(me.displayName, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          post.focus.isEmpty
                              ? tr3('说说你的看法…', 'Пікіріңіз…', 'Что думаете?', 'What do you think?', ky: 'Эмне ойлойсуз?', uz: 'Nima deb oʻylaysiz?')
                              : tr3(
                                  '聊聊${post.focus.map(feedbackTopicName).join('、')}…',
                                  'Пікіріңіз…',
                                  'Что думаете о: ${post.focus.map(feedbackTopicName).join(', ')}?',
                                  'What do you think about: ${post.focus.map(feedbackTopicName).join(', ')}?', ky: 'Бул тууралуу эмне ойлойсуз: ${post.focus.map(feedbackTopicName).join(', ')}?', uz: 'Bu haqda nima deb oʻylaysiz: ${post.focus.map(feedbackTopicName).join(', ')}?'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.muted))),
                ]))));
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
  const _CritiqueBox({required this.post, this.autofocus = false, this.onSent});
  final HousePost post;
  final bool autofocus;
  final VoidCallback? onSent;
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
      await context
          .read(postRepositoryProvider)
          .comment(widget.post.id, text.text, rating: rating, topic: topic);
      text.clear();
      if (!mounted) return;
      setState(() {
        rating = null;
        topic = null;
      });
      widget.onSent?.call();
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          tr3('说说哪方面？（可选）', 'Қай жағы туралы?', 'О чём отзыв? (необязательно)', "What's the review about? (optional)", ky: 'Пикир эмне жөнүндө? (милдеттүү эмес)', uz: 'Sharh nima haqida? (ixtiyoriy)'),
          style: TextStyle(color: t.muted, fontSize: YFont.small)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final k in order)
          ChoiceChip(
              key: Key('critique-pick-$k'),
              label: Text(feedbackTopicName(k)),
              selected: topic == k,
              showCheckmark: false,
              avatar: focus.contains(k) && topic != k
                  ? Icon(YIcons.starFill, size: 14, color: t.accent)
                  : null,
              onSelected: (_) => setState(() => topic = topic == k ? null : k)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
              button: true,
              selected: i <= (rating ?? 0),
              label: tr3('$i 星', '$i жұлдыз', 'Оценка $i из 5', 'Rating $i of 5', ky: 'Баа: 5тен $i', uz: 'Baho: 5 dan $i'),
              child: InkWell(
                  borderRadius: BorderRadius.circular(YRadius.pill),
                  onTap: () => setState(() => rating = rating == i ? null : i),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 10),
                      child: Icon(
                          i <= (rating ?? 0) ? YIcons.starFill : YIcons.star,
                          size: 26,
                          color: t.accent)))),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
                rating == null
                    ? tr3('整体打个分（可选）', 'Бағалаңыз', 'Общая оценка', 'Overall rating', ky: 'Жалпы баа', uz: 'Umumiy baho')
                    : [
                        '',
                        tr3('不推荐', 'Ұсынбаймын', 'Не советую', "Wouldn't recommend", ky: 'Сунуштабайм', uz: 'Tavsiya qilmayman'),
                        tr3('一般', 'Орташа', 'Так себе', 'So-so', ky: 'Анча эмес', uz: 'Unchalik emas'),
                        tr3('还行', 'Жақсы', 'Нормально', 'OK', ky: 'Жаман эмес', uz: 'Yomon emas'),
                        tr3('不错', 'Өте жақсы', 'Хорошо', 'Good', ky: 'Жакшы', uz: 'Yaxshi'),
                        tr3('很好', 'Керемет', 'Отлично', 'Excellent', ky: 'Эң сонун', uz: 'Aʼlo'),
                      ][rating!],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.muted, fontSize: YFont.small))),
      ]),
      const SizedBox(height: YSpace.xs),
      // The field takes the full width; the button sits under it, so
      // the hint and the text being written are never squeezed.
      TextField(
          key: const Key('critique-text'),
          controller: text,
          autofocus: widget.autofocus,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: topic == null
                  ? tr3('说说布局、造价、施工上的看法…', 'Пікіріңіз…',
                      'Что думаете о планировке, цене, стройке…',
                      'What do you think about the layout, price, build…', ky: 'Пландоо, баа, курулуш жөнүндө эмне ойлойсуз…', uz: 'Rejalashtirish, narx, qurilish haqida nima deb oʻylaysiz…')
                  : tr3('关于${feedbackTopicName(topic!)}，你的建议是…', 'Ұсынысыңыз…',
                      'Ваш совет…',
                      'Your advice…', ky: 'Кеңешиңиз…', uz: 'Maslahatingiz…'))),
      const SizedBox(height: YSpace.md),
      Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
              key: const Key('critique-send'),
              onPressed: busy ? null : send,
              child: Text(tr3('发布', 'Жіберу', 'Отправить', 'Send', ky: 'Жөнөтүү', uz: 'Yuborish')))),
    ]);
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
  final bool canDelete;
  final bool canMarkHelpful;
  final bool canReply;
  final bool reply;

  Future<void> _reply(BuildContext context) async {
    final text = await askText(context, tr3('回复', 'Жауап', 'Ответить', 'Reply', ky: 'Жооп берүү', uz: 'Javob berish'),
        hint: tr3('补充或回答', 'Жауап', 'Ответ', 'Reply', ky: 'Жооп берүү', uz: 'Javob berish'));
    if (text == null || !context.mounted) return;
    await attempt(
        context,
        () => context
            .read(postRepositoryProvider)
            .comment(post.id, text, parentId: comment.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = comment;
    return Padding(
        padding: EdgeInsets.only(top: reply ? 10 : 16),
        child: Live<(Account?, List<ServiceProfile>)>(
            provider: authorProvider(c.authorId),
            loading: SkeletonRow(avatar: true, avatarSize: reply ? 28 : 36),
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
                                  StatusPill(tr3('作者', 'Автор', 'Автор', 'Author', ky: 'Автор', uz: 'Muallif'),
                                      color: t.ink)
                                else if (pro != null)
                                  StatusPill(proRoleName(pro.role),
                                      color: t.accent),
                                Text(ago(c.createdAt, context.now),
                                    style: TextStyle(
                                        color: t.muted,
                                        fontSize: YFont.caption)),
                              ]),
                          if (c.helpful || c.topic != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 6, children: [
                                  if (c.helpful)
                                    StatusPill(
                                        tr3('作者觉得有用', 'Автор: пайдалы',
                                            'Автор: полезно',
                                            'Author: helpful', ky: 'Автор: пайдалуу', uz: 'Muallif: foydali'),
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
                                        Text(tr3('回复', 'Жауап', 'Ответить', 'Reply', ky: 'Жооп берүү', uz: 'Javob berish'))),
                              if (canMarkHelpful)
                                TextButton.icon(
                                    key: Key('critique-helpful-${c.id}'),
                                    style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor:
                                            c.helpful ? t.ok : t.muted),
                                    onPressed: () => attempt(
                                        context,
                                        () => context
                                            .read(postRepositoryProvider)
                                            .markHelpful(c.id, !c.helpful)),
                                    icon: Icon(
                                        c.helpful
                                            ? YIcons.thumb
                                            : YIcons.thumb,
                                        size: 16),
                                    label: Text(c.helpful
                                        ? tr3('已标有用', 'Пайдалы', 'Полезно', 'Helpful', ky: 'Пайдалуу', uz: 'Foydali')
                                        : tr3('有用', 'Пайдалы', 'Полезно', 'Helpful', ky: 'Пайдалуу', uz: 'Foydali'))),
                            ]),
                        ])),
                    if (canDelete)
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr3('删除', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish'),
                          icon: Icon(YIcons.close, size: 16, color: t.faint),
                          onPressed: () => attempt(
                              context,
                              () => context
                                  .read(postRepositoryProvider)
                                  .deleteComment(c.id)))
                    else
                      IconButton(
                          key: Key('critique-report-${c.id}'),
                          visualDensity: VisualDensity.compact,
                          tooltip: tr3('举报', 'Шағым', 'Пожаловаться', 'Report', ky: 'Арыз берүү', uz: 'Shikoyat qilish'),
                          icon:
                              YusalIcon(YIcon.flag, size: 16, color: t.faint),
                          onPressed: () => reportContent(
                              context, ReportTarget.comment, c.id)),
                  ]);
            }));
  }
}
