import 'dart:async';

import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../coop/coop_page.dart';
import '../demand/demand_detail_page.dart';
import '../home/post_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../components.dart';
import '../widgets.dart';
import 'chat_page.dart';
import '../../../motion/motion.dart';
import '../me/trust_pages.dart';
import '../profile/profile_page.dart';

/// Unread chats and notices together, asked for at the same time.
Future<int> _unread(PlatformRepositories r) async {
  final counts =
      await Future.wait([r.unreadMessages(), r.unreadNotifications()]);
  return counts[0] + counts[1];
}

/// Envelope button with the unread count of chats and notices together.
class InboxButton extends StatelessWidget {
  const InboxButton({super.key});
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<int>(
        load: _unread,
        loading: const SizedBox(width: 48),
        builder: (context, unread) => IconButton(
            tooltip: tr3('消息', 'Хабарлар', 'Сообщения'),
            onPressed: () async {
              if (await requireLogin(context) && context.mounted)
                await pushPage<void>(context, (_) => const InboxPage());
            },
            icon: Badge(
                isLabelVisible: unread > 0,
                backgroundColor: t.accent,
                textColor: t.accentInk,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: const Icon(Icons.mail_outline))));
  }
}

/// The Messages tab icon with the unread count of chats and notices.
class InboxNavIcon extends StatelessWidget {
  const InboxNavIcon({super.key, this.selected = false});
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline);
    final t = YTokens.of(context);
    return OnChange(
        builder: (context) => context.repos.currentAccount == null
            ? icon
            : Live<int>(
                load: _unread,
                loading: icon,
                builder: (context, unread) => Badge(
                    isLabelVisible: unread > 0,
                    backgroundColor: t.accent,
                    textColor: t.accentInk,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: icon)));
  }
}

/// Message centre: conversations and system notices. Signed out, it says
/// what messages are for and offers to sign in.
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final title = Text(tr3('消息', 'Хабарлар', 'Сообщения'));
    return OnChange(builder: (context) {
      if (context.repos.currentAccount == null)
        return Scaffold(
            appBar: AppBar(title: title),
            body: SignInPrompt(
                icon: Icons.forum_outlined,
                text: tr3('登录后查看消息', 'Хабарларды көру үшін кіріңіз',
                    'Войдите, чтобы видеть сообщения'),
                body: tr3(
                    '和房主、师傅的聊天，以及报价、验收等通知都在这里。',
                    'Үй иелері мен шеберлермен чаттар, ұсыныстар мен қабылдау туралы хабарламалар осында.',
                    'Здесь чаты с владельцами и мастерами, уведомления о предложениях и приёмке.')));
      return DefaultTabController(
          length: 2,
          child: Scaffold(
              appBar: AppBar(
                  title: title,
                  actions: [
                    IconButton(
                        tooltip: tr3('全部已读', 'Барлығы оқылды', 'Прочитать всё'),
                        icon: const Icon(Icons.done_all),
                        onPressed: () => attempt(
                            context, () => context.repos.markAllRead())),
                    const SizedBox(width: YSpace.xs),
                  ],
                  bottom: TabBar(tabs: [
                    Tab(text: tr3('会话', 'Чаттар', 'Чаты')),
                    Tab(text: tr3('通知', 'Хабарламалар', 'Уведомления')),
                  ])),
              body: const MotionTabView(
                  children: [_Conversations(), _Notices()])));
    });
  }
}

// Stateful so each copy of the page has its own pull-to-refresh: the
// Messages tab and an inbox opened from the mail button live at once.
class _Conversations extends StatefulWidget {
  const _Conversations();
  @override
  State<_Conversations> createState() => _ConversationsState();
}

class _ConversationsState extends State<_Conversations> {
  final _refresh = LiveRefresh();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<(Conversation, Account?)>>(
        fadeIn: true,
        refresh: _refresh,
        loading: const SkeletonList(
            count: 4,
            avatar: true,
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        load: (r) async {
          final me = r.currentAccount?.id ?? '';
          final list = await r.conversations();
          final others = await Future.wait(
              [for (final c in list) r.account(c.otherSide(me))]);
          return [for (var i = 0; i < list.length; i++) (list[i], others[i])];
        },
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: Icons.forum_outlined,
                title: tr3('还没有会话', 'Чат жоқ', 'Нет чатов'),
                body: tr3('在需求或名片页点击“联系”开始沟通。', 'Тапсырыс бетінен жазыңыз.',
                    'Напишите со страницы заявки или профиля.'))
            : RefreshIndicator(
                onRefresh: _refresh.call,
                child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final (c, other) = list[i];
                  final last = c.lastMessage;
                  return ListTile(
                      leading: Avatar(deletedName(other), size: 48),
                      title: Text(deletedName(other),
                          style: TextStyle(
                              fontWeight: c.unread > 0
                                  ? FontWeight.w800
                                  : FontWeight.w600)),
                      subtitle: Text(last == null ? '' : messagePreview(last),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (last != null)
                              Text(ago(last.sentAt, context.now),
                                  style:
                                      TextStyle(color: t.muted, fontSize: YFont.caption)),
                            if (c.unread > 0)
                              Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: t.accent,
                                      borderRadius: BorderRadius.circular(YRadius.pill)),
                                  child: Text('${c.unread}',
                                      style: TextStyle(
                                          color: t.accentInk,
                                          fontSize: YFont.caption,
                                          fontWeight: FontWeight.w700))),
                          ]),
                      onTap: () => pushPage<void>(
                          context, (_) => ChatPage(conversationId: c.id)));
                })));
  }
}

String messagePreview(ChatMessage m) => switch (m.kind) {
      MessageKind.text => m.text,
      MessageKind.image => tr3('[图片]', '[Сурет]', '[Фото]'),
      MessageKind.demandCard => tr3('[需求卡片]', '[Тапсырыс]', '[Заявка]'),
      MessageKind.quoteCard => tr3('[报价卡片]', '[Ұсыныс]', '[Предложение]'),
      MessageKind.phoneShared => tr3('[电话号码]', '[Телефон]', '[Телефон]'),
      MessageKind.system => m.text,
    };

// Stateful so each copy of the page has its own pull-to-refresh: the
// Messages tab and an inbox opened from the mail button live at once.
class _Notices extends StatefulWidget {
  const _Notices();
  @override
  State<_Notices> createState() => _NoticesState();
}

class _NoticesState extends State<_Notices> {
  final _refresh = LiveRefresh();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<AppNotification>>(
        fadeIn: true,
        refresh: _refresh,
        loading: const SkeletonList(
            count: 4, padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        load: (r) => r.notifications(),
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: Icons.notifications_none,
                title: tr3('暂无通知', 'Хабарлама жоқ', 'Нет уведомлений'))
            : RefreshIndicator(
                onRefresh: _refresh.call,
                child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final n = list[i];
                  return ListTile(
                      leading: Icon(noticeIcon(n.kind),
                          color: n.read ? t.muted : t.accent),
                      title: Text(noticeText(n),
                          style: TextStyle(
                              fontWeight:
                                  n.read ? FontWeight.w400 : FontWeight.w700)),
                      subtitle: Text(ago(n.createdAt, context.now)),
                      onTap: () {
                        // Open at once; the read mark follows in the
                        // background instead of holding the tap.
                        if (!n.read) {
                          unawaited(context.repos
                              .markRead(n.id)
                              .catchError((Object _) {}));
                        }
                        openNotice(context, n);
                      });
                })));
  }
}

IconData noticeIcon(NoticeKind k) => switch (k) {
      NoticeKind.newApplication => Icons.inbox_outlined,
      NoticeKind.confirmRequest ||
      NoticeKind.agreementChange =>
        Icons.handshake_outlined,
      NoticeKind.cooperationConfirmed ||
      NoticeKind.reviewApproved =>
        Icons.check_circle_outline,
      NoticeKind.cooperationDeclined ||
      NoticeKind.reviewRejected =>
        Icons.cancel_outlined,
      NoticeKind.endRequest || NoticeKind.ended => Icons.flag_outlined,
      NoticeKind.reviewReceived => Icons.star_outline,
      NoticeKind.postLiked => Icons.favorite_border,
      NoticeKind.postReused => Icons.content_copy_outlined,
      NoticeKind.milestoneRequested ||
      NoticeKind.milestoneAnswered =>
        Icons.fact_check_outlined,
      NoticeKind.workLogged => Icons.event_available_outlined,
      NoticeKind.postCommented ||
      NoticeKind.commentReplied =>
        Icons.chat_bubble_outline,
      NoticeKind.commentHelpful => Icons.thumb_up_alt_outlined,
      NoticeKind.outcomeFollowUp => Icons.help_outline,
      NoticeKind.contentRemoved ||
      NoticeKind.accountRestricted =>
        Icons.gpp_maybe_outlined,
      NoticeKind.reportResolved => Icons.flag_outlined,
      NoticeKind.accountRestored || NoticeKind.appealAnswered => Icons.gavel_outlined,
      NoticeKind.verificationApproved ||
      NoticeKind.verificationRejected =>
        Icons.verified_outlined,
      NoticeKind.newDemandMatch => Icons.notifications_active_outlined,
      _ => Icons.notifications_none,
    };

/// Opens the object a notice points to; closed or missing objects show
/// their own clear state on the target page.
Future<void> openNotice(BuildContext context, AppNotification n) async {
  if (n.kind == NoticeKind.contentRemoved ||
      n.kind == NoticeKind.accountRestricted) {
    // A moderator's decision about my own record: say so and offer an appeal.
    final target = n.kind == NoticeKind.accountRestricted ? 'account' : n.refType.name;
    final restricted = n.kind == NoticeKind.accountRestricted;
    final v = await showDialog<String>(
        context: context,
        builder: (context) => PlatformTheme(
                child: AlertDialog(
                    title: Text(noticeText(n)),
                    content: restricted && n.title.isNotEmpty
                        ? Text('${tr3('原因', 'Себебі', 'Причина')}: ${reasonText(n.title)}')
                        : null,
                    actions: [
                  if (!restricted)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'open'),
                        child: Text(tr3('查看', 'Ашу', 'Открыть'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'appeal'),
                      child: Text(tr3('申诉', 'Шағымдану', 'Обжаловать'))),
                ])));
    if (!context.mounted) return;
    if (v == 'appeal') return appealDecision(context, target, n.refId);
    if (v == 'open') return openRef(context, n.refType, n.refId);
    return;
  }
  return openRef(context, n.refType, n.refId);
}

/// Opens the page for a referenced object (notices and tapped pushes).
Future<void> openRef(BuildContext context, RefType type, String id) =>
    switch (type) {
      RefType.cooperation =>
        pushPage<void>(context, (_) => CooperationPage(cooperationId: id)),
      RefType.conversation =>
        pushPage<void>(context, (_) => ChatPage(conversationId: id)),
      RefType.post => pushPage<void>(context, (_) => PostPage(postId: id)),
      RefType.profile => pushPage<void>(context, (_) => ProfilePage(profileId: id)),
      RefType.appeal ||
      RefType.account =>
        pushPage<void>(context, (_) => const MyAppealsPage()),
      RefType.report => Future<void>.value(),
      _ => pushPage<void>(context, (_) => DemandDetailPage(demandId: id)),
    };
