import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../coop/coop_page.dart';
import '../demand/demand_detail_page.dart';
import '../home/post_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_page.dart';
import '../../../motion/motion.dart';

/// Envelope button with the unread count of chats and notices together.
class InboxButton extends StatelessWidget {
  const InboxButton({super.key});
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<int>(
        load: (r) async =>
            await r.unreadMessages() + await r.unreadNotifications(),
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
                load: (r) async =>
                    await r.unreadMessages() + await r.unreadNotifications(),
                loading: icon,
                builder: (context, unread) => Badge(
                    isLabelVisible: unread > 0,
                    backgroundColor: t.accent,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: icon)));
  }
}

/// Message centre: conversations and system notices.
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return DefaultTabController(
        length: 2,
        child: Scaffold(
            appBar: AppBar(
                title: Text(tr3('消息', 'Хабарлар', 'Сообщения')),
                actions: [
                  TextButton(
                      onPressed: () =>
                          attempt(context, () => context.repos.markAllRead()),
                      child:
                          Text(tr3('全部已读', 'Барлығы оқылды', 'Прочитать всё'))),
                ],
                bottom: TabBar(tabs: [
                  Tab(text: tr3('会话', 'Чаттар', 'Чаты')),
                  Tab(text: tr3('通知', 'Хабарламалар', 'Уведомления')),
                ])),
            body: const MotionTabView(children: [_Conversations(), _Notices()])));
  }
}

class _Conversations extends StatelessWidget {
  const _Conversations();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<(Conversation, Account?)>>(
        fadeIn: true,
        load: (r) async {
          final me = r.currentAccount?.id ?? '';
          return [
            for (final c in await r.conversations())
              (c, await r.account(c.otherSide(me)))
          ];
        },
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: Icons.forum_outlined,
                title: tr3('还没有会话', 'Чат жоқ', 'Нет чатов'),
                body: tr3('在需求或名片页点击“联系”开始沟通。', 'Тапсырыс бетінен жазыңыз.',
                    'Напишите со страницы заявки или профиля.'))
            : ListView.separated(
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
                                      TextStyle(color: t.muted, fontSize: 12)),
                            if (c.unread > 0)
                              Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: t.accent,
                                      borderRadius: BorderRadius.circular(99)),
                                  child: Text('${c.unread}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11))),
                          ]),
                      onTap: () => pushPage<void>(
                          context, (_) => ChatPage(conversationId: c.id)));
                }));
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

class _Notices extends StatelessWidget {
  const _Notices();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<AppNotification>>(
        fadeIn: true,
        load: (r) => r.notifications(),
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: Icons.notifications_none,
                title: tr3('暂无通知', 'Хабарлама жоқ', 'Нет уведомлений'))
            : ListView.separated(
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
                      onTap: () async {
                        await attempt(
                            context, () => context.repos.markRead(n.id));
                        if (!context.mounted) return;
                        await openNotice(context, n);
                      });
                }));
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
      _ => Icons.notifications_none,
    };

/// Opens the object a notice points to; closed or missing objects show
/// their own clear state on the target page.
Future<void> openNotice(BuildContext context, AppNotification n) =>
    openRef(context, n.refType, n.refId);

/// Opens the page for a referenced object (notices and tapped pushes).
Future<void> openRef(BuildContext context, RefType type, String id) =>
    switch (type) {
      RefType.cooperation =>
        pushPage<void>(context, (_) => CooperationPage(cooperationId: id)),
      RefType.conversation =>
        pushPage<void>(context, (_) => ChatPage(conversationId: id)),
      RefType.post => pushPage<void>(context, (_) => PostPage(postId: id)),
      _ => pushPage<void>(context, (_) => DemandDetailPage(demandId: id)),
    };
