import 'dart:async';

import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/chat/state/inbox.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/coop/page.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/features/home/pages/post.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/chat/page.dart';
import 'package:yusal/features/shared/motion/motion.dart';
import 'package:yusal/features/me/pages/trust.dart';
import 'package:yusal/features/profile/page.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Envelope button with the unread count of chats and notices together.
class InboxButton extends StatelessWidget {
  const InboxButton({super.key});
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<int>(
        provider: unreadProvider,
        loading: const SizedBox(width: 48),
        builder: (context, unread) => IconButton(
            tooltip: tr3('消息', 'Хабарлар', 'Сообщения', 'Messages', ky: 'Билдирүүлөр', uz: 'Xabarlar'),
            onPressed: () async {
              if (await requireLogin(context) && context.mounted) {
                await pushPage<void>(context, (_) => const InboxPage());
              }
            },
            icon: Badge(
                isLabelVisible: unread > 0,
                backgroundColor: t.accent,
                textColor: t.accentInk,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: const Icon(YIcons.mail))));
  }
}

/// The Messages tab icon with the unread count of chats and notices.
class InboxNavIcon extends StatelessWidget {
  const InboxNavIcon({super.key, this.selected = false});
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final icon = YusalIcon(YIcon.chat, mono: !selected);
    final t = YTokens.of(context);
    return OnChange(
        builder: (context) => context.session.currentAccount == null
            ? icon
            : Live<int>(
                provider: unreadProvider,
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
    watchLang(context);
    final title = Text(tr3('消息', 'Хабарлар', 'Сообщения', 'Messages', ky: 'Билдирүүлөр', uz: 'Xabarlar'), style: display());
    return OnChange(builder: (context) {
      if (context.session.currentAccount == null) {
        return Scaffold(
            appBar: AppBar(titleSpacing: YSpace.gutter, title: title),
            body: SignInPrompt(
                icon: YIcons.chat,
                text: tr3('登录后查看消息', 'Хабарларды көру үшін кіріңіз',
                    'Войдите, чтобы видеть сообщения',
                    'Sign in to see messages', ky: 'Билдирүүлөрдү көрүү үчүн кириңиз', uz: 'Xabarlarni koʻrish uchun kiring'),
                body: tr3(
                    '和房主、师傅的聊天，以及报价、验收等通知都在这里。',
                    'Үй иелері мен шеберлермен чаттар, ұсыныстар мен қабылдау туралы хабарламалар осында.',
                    'Здесь чаты с владельцами и мастерами, уведомления о предложениях и приёмке.',
                    'Chats with owners and pros, and notifications about quotes and acceptance, live here.', ky: 'Ээлер жана адистер менен чаттар, сунуштар жана кабыл алуу жөнүндө билдирмелер ушул жерде.', uz: 'Egalar va mutaxassislar bilan chatlar, takliflar va qabul haqidagi bildirishnomalar shu yerda.')));
      }
      return DefaultTabController(
          length: 2,
          child: Scaffold(
              appBar: AppBar(
                  titleSpacing: YSpace.gutter,
                  title: title,
                  actions: [
                    IconButton(
                        tooltip: tr3('全部已读', 'Барлығы оқылды', 'Прочитать всё', 'Mark all read', ky: 'Баарын окулду деп белгилөө', uz: 'Hammasini oʻqildi deb belgilash'),
                        icon: const Icon(YIcons.check),
                        onPressed: () => attempt(
                            context,
                            () => context
                                .read(notificationRepositoryProvider)
                                .markAllRead())),
                    const SizedBox(width: YSpace.xs),
                  ],
                  bottom: TabBar(tabs: [
                    Tab(text: tr3('会话', 'Чаттар', 'Чаты', 'Chats', ky: 'Чаттар', uz: 'Chatlar')),
                    Tab(text: tr3('通知', 'Хабарламалар', 'Уведомления', 'Notifications', ky: 'Билдирмелер', uz: 'Bildirishnomalar')),
                  ])),
              body: const MotionTabView(
                  children: [_Conversations(), _Notices()])));
    });
  }
}

// Stateful so each copy of the page has its own pull-to-refresh: the
// Messages tab and an inbox opened from the mail button live at once.
class _Conversations extends StatelessWidget {
  const _Conversations();

  @override
  Widget build(BuildContext context) {
    final refresh = LiveRefresh();
    final t = YTokens.of(context);
    return Live<List<(Conversation, Account?)>>(
        fadeIn: true,
        refresh: refresh,
        loading: const SkeletonList(
            count: 4,
            avatar: true,
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        provider: conversationsProvider,
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: YIcons.chat,
                title: tr3('还没有会话', 'Чат жоқ', 'Нет чатов', 'No chats', ky: 'Чаттар жок', uz: 'Chatlar yoʻq'),
                body: tr3('在需求或名片页点击“联系”开始沟通。', 'Тапсырыс бетінен жазыңыз.',
                    'Напишите со страницы заявки или профиля.',
                    'Write from a request or profile page.', ky: 'Суроо-талаптын же профилдин бетинен жазыңыз.', uz: 'Soʻrov yoki profil sahifasidan yozing.'))
            : RefreshIndicator(
                onRefresh: refresh.call,
                child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        20, 8, 20, 8 + MediaQuery.paddingOf(context).bottom),
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
                          subtitle: Text(
                              last == null ? '' : messagePreview(last),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (last != null)
                                  Text(ago(last.sentAt, context.now),
                                      style: TextStyle(
                                          color: t.muted,
                                          fontSize: YFont.caption)),
                                if (c.unread > 0)
                                  Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: t.accent,
                                          borderRadius: BorderRadius.circular(
                                              YRadius.pill)),
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
      MessageKind.image => tr3('[图片]', '[Сурет]', '[Фото]', '[Photo]', ky: '[Сүрөт]', uz: '[Rasm]'),
      MessageKind.demandCard => tr3('[需求卡片]', '[Тапсырыс]', '[Заявка]', '[Request]', ky: '[Суроо-талап]', uz: '[Soʻrov]'),
      MessageKind.quoteCard => tr3('[报价卡片]', '[Ұсыныс]', '[Предложение]', '[Quote]', ky: '[Сунуш]', uz: '[Taklif]'),
      MessageKind.phoneShared => tr3('[电话号码]', '[Телефон]', '[Телефон]', '[Phone]', ky: '[Телефон]', uz: '[Telefon]'),
      MessageKind.system => m.text,
    };

// Stateful so each copy of the page has its own pull-to-refresh: the
// Messages tab and an inbox opened from the mail button live at once.
class _Notices extends StatelessWidget {
  const _Notices();

  @override
  Widget build(BuildContext context) {
    final refresh = LiveRefresh();
    final t = YTokens.of(context);
    return Live<List<AppNotification>>(
        fadeIn: true,
        refresh: refresh,
        loading: const SkeletonList(
            count: 4, padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        provider: noticesProvider,
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: YIcons.bell,
                title: tr3('暂无通知', 'Хабарлама жоқ', 'Нет уведомлений', 'No notifications', ky: 'Билдирмелер жок', uz: 'Bildirishnomalar yoʻq'))
            : RefreshIndicator(
                onRefresh: refresh.call,
                child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        20, 8, 20, 8 + MediaQuery.paddingOf(context).bottom),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final n = list[i];
                      return ListTile(
                          leading: Icon(noticeIcon(n.kind),
                              color: n.read ? t.muted : t.accent),
                          title: Text(noticeText(n),
                              style: TextStyle(
                                  fontWeight: n.read
                                      ? FontWeight.w400
                                      : FontWeight.w700)),
                          subtitle: Text(ago(n.createdAt, context.now)),
                          onTap: () {
                            // Open at once; the read mark follows in the
                            // background instead of holding the tap.
                            if (!n.read) {
                              context
                                  .read(notificationRepositoryProvider)
                                  .markRead(n.id)
                                  .catchError((Object _) {});
                            }
                            openNotice(context, n);
                          });
                    })));
  }
}

IconData noticeIcon(NoticeKind k) => switch (k) {
      NoticeKind.newApplication => YIcons.inbox,
      NoticeKind.confirmRequest ||
      NoticeKind.agreementChange =>
        YIcons.coop,
      NoticeKind.cooperationConfirmed ||
      NoticeKind.reviewApproved =>
        YIcons.checkCircle,
      NoticeKind.cooperationDeclined ||
      NoticeKind.reviewRejected =>
        YIcons.close,
      NoticeKind.endRequest || NoticeKind.ended => YIcons.flag,
      NoticeKind.reviewReceived => YIcons.star,
      NoticeKind.postLiked => YIcons.heart,
      NoticeKind.postReused => YIcons.copy,
      NoticeKind.milestoneRequested ||
      NoticeKind.milestoneAnswered =>
        YIcons.contract,
      NoticeKind.workLogged => YIcons.calendarCheck,
      NoticeKind.postCommented ||
      NoticeKind.commentReplied =>
        YIcons.chat,
      NoticeKind.commentHelpful => YIcons.thumb,
      NoticeKind.outcomeFollowUp => YIcons.help,
      NoticeKind.contentRemoved ||
      NoticeKind.accountRestricted =>
        Icons.gpp_maybe_outlined,
      NoticeKind.reportResolved => YIcons.flag,
      NoticeKind.accountRestored ||
      NoticeKind.appealAnswered =>
        Icons.gavel_outlined,
      NoticeKind.verificationApproved ||
      NoticeKind.verificationRejected =>
        YIcons.verified,
      NoticeKind.newDemandMatch => Icons.notifications_active_outlined,
      _ => YIcons.bell,
    };

/// Opens the object a notice points to; closed or missing objects show
/// their own clear state on the target page.
Future<void> openNotice(BuildContext context, AppNotification n) async {
  if (n.kind == NoticeKind.contentRemoved ||
      n.kind == NoticeKind.accountRestricted) {
    // A moderator's decision about my own record: say so and offer an appeal.
    final target =
        n.kind == NoticeKind.accountRestricted ? 'account' : n.refType.name;
    final restricted = n.kind == NoticeKind.accountRestricted;
    final v = await showDialog<String>(
        context: context,
        builder: (context) => PlatformTheme(
                child: AlertDialog(
                    title: Text(noticeText(n)),
                    content: restricted && n.title.isNotEmpty
                        ? Text(
                            '${tr3('原因', 'Себебі', 'Причина', 'Reason', ky: 'Себеби', uz: 'Sababi')}: ${reasonText(n.title)}')
                        : null,
                    actions: [
                  if (!restricted)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'open'),
                        child: Text(tr3('查看', 'Ашу', 'Открыть', 'Open', ky: 'Ачуу', uz: 'Ochish'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'appeal'),
                      child: Text(tr3('申诉', 'Шағымдану', 'Обжаловать', 'Appeal', ky: 'Даттануу', uz: 'Apellyatsiya'))),
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
      RefType.profile =>
        pushPage<void>(context, (_) => ProfilePage(profileId: id)),
      RefType.appeal ||
      RefType.account =>
        pushPage<void>(context, (_) => const MyAppealsPage()),
      RefType.report => Future<void>.value(),
      _ => pushPage<void>(context, (_) => DemandDetailPage(demandId: id)),
    };
