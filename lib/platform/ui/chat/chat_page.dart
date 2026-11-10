import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../demand/demand_detail_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../components.dart';
import '../theme.dart';
import '../widgets.dart';

class _ChatData {
  _ChatData(
      this.conversation, this.other, this.messages, this.cards, this.blocked);
  final Conversation conversation;
  final Account? other;
  final List<ChatMessage> messages;

  /// Demand titles of card messages by referenced id.
  final Map<String, String> cards;
  final bool blocked;
}

/// One conversation: text, image placeholders, demand and quote cards,
/// phone sharing on purpose, failed sends with retry, block and report.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  int seen = -1;

  Future<_ChatData> load(PlatformRepositories r) async {
    final convs = await r.conversations();
    final c = convs.firstWhere((c) => c.id == widget.conversationId,
        orElse: () => throw const ApiFailure(ApiCodes.notFound));
    final me = r.currentAccount!.id;
    final msgs = await r.messages(c.id);
    final cards = <String, String>{};
    for (final m in msgs) {
      if (m.refId == null) continue;
      if (m.kind == MessageKind.demandCard) {
        cards[m.refId!] = (await r.demand(m.refId!))?.current.title ?? '';
      } else if (m.kind == MessageKind.quoteCard) {
        final a = await r.application(m.refId!);
        if (a != null) {
          final d = await r.demand(a.demandId);
          cards[m.refId!] =
              '${d?.current.title ?? ''}|${a.demandId}|${a.current.total == null ? pricingName(a.current.pricing) : money(a.current.total)}';
        }
      }
    }
    if (c.unread > 0) await r.markConversationRead(c.id);
    return _ChatData(c, await r.account(c.otherSide(me)), msgs, cards,
        (await r.blocked()).contains(c.otherSide(me)));
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    final m = await attempt(
        context,
        () => context.repos
            .send(widget.conversationId, MessageKind.text, text: text));
    if (m == null) input.text = text;
  }

  Future<void> more(_ChatData data) async {
    final repos = context.repos;
    final choice =
        await pickOne<String>(context, tr3('发送', 'Жіберу', 'Отправить'), [
      ('image', tr3('图片', 'Сурет', 'Фото')),
      ('demand', tr3('需求卡片', 'Тапсырыс картасы', 'Карточка заявки')),
      (
        'phone',
        tr3('向对方展示我的电话', 'Телефонымды көрсету', 'Показать мой телефон')
      ),
      (
        'whatsapp',
        tr3('通过 WhatsApp 联系', 'WhatsApp арқылы', 'Связаться в WhatsApp')
      ),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'image':
        await attempt(
            context,
            () => repos.send(widget.conversationId, MessageKind.image,
                text: tr3('现场照片', 'Фото', 'Фото объекта')));
      case 'demand':
        final mine = await attempt(context, () => repos.myDemands());
        if (mine == null || !mounted) return;
        final id =
            await pickOne<String>(context, tr3('选择需求', 'Тапсырыс', 'Заявка'), [
          for (final d in mine.where((d) => d.status != DemandStatus.draft))
            (d.id, d.current.title)
        ]);
        if (id != null && mounted)
          await attempt(
              context,
              () => repos.send(widget.conversationId, MessageKind.demandCard,
                  refId: id));
      case 'phone':
        if (repos.currentAccount?.phone.isEmpty ?? true) {
          if (!await editPhone(context) ||
              !mounted ||
              (repos.currentAccount?.phone.isEmpty ?? true)) return;
        }
        if (!mounted) return;
        if (await confirmDialog(context,
                tr3('展示电话号码？', 'Телефонды көрсету?', 'Показать телефон?'),
                body: tr3(
                    '对方将看到你的完整手机号。你的手机号默认对其他人隐藏。',
                    'Екінші жақ нөміріңізді көреді.',
                    'Собеседник увидит ваш номер.')) &&
            mounted)
          await attempt(context, () => repos.sharePhone(widget.conversationId));
      case 'whatsapp':
        await confirmDialog(
            context, tr3('通过 WhatsApp 联系', 'WhatsApp', 'WhatsApp'),
            body: tr3(
                '打开 WhatsApp 会向对方暴露你的手机号。平台不把外部聊天当作成交证据，确认合作请回到 Yusal 操作。测试环境不会真正打开外部应用。',
                'WhatsApp нөміріңізді көрсетеді. Келісімді Yusal-да растаңыз.',
                'WhatsApp раскроет ваш номер. Подтверждайте сотрудничество в Yusal.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    return Live<_ChatData>(
        load: load,
        loading: const SkeletonPage(avatar: true),
        error: (context, e) => PageScaffold(
            title: '',
            body: EmptyState(icon: Icons.error_outline, title: failureText(e))),
        builder: (context, data) {
          final me = context.repos.currentAccount?.id;
          final name = deletedName(data.other);
          return Scaffold(
              appBar: AppBar(
                  title: Row(children: [
                    Avatar(name, size: 32),
                    const SizedBox(width: 10),
                    Flexible(
                        child: Text(name, overflow: TextOverflow.ellipsis)),
                  ]),
                  actions: [
                    PopupMenuButton<String>(
                        onSelected: (v) async {
                          final other = data.conversation.otherSide(me ?? '');
                          if (v == 'block')
                            await attempt(
                                context, () => context.repos.block(other),
                                success:
                                    tr3('已拉黑', 'Бұғатталды', 'Заблокировано'));
                          if (v == 'unblock')
                            await attempt(
                                context, () => context.repos.unblock(other));
                          if (v == 'report' && context.mounted) {
                            final reason = await askText(
                                context, tr3('举报', 'Шағым', 'Жалоба'));
                            if (reason != null && context.mounted)
                              await attempt(
                                  context,
                                  () => context.repos.report(
                                      ReportTarget.account, other, reason),
                                  success:
                                      tr3('已提交', 'Жіберілді', 'Отправлено'));
                          }
                        },
                        itemBuilder: (context) => [
                              PopupMenuItem(
                                  value: data.blocked ? 'unblock' : 'block',
                                  child: Text(data.blocked
                                      ? tr3('取消拉黑', 'Бұғаттан шығару',
                                          'Разблокировать')
                                      : tr3(
                                          '拉黑', 'Бұғаттау', 'Заблокировать'))),
                              PopupMenuItem(
                                  value: 'report',
                                  child:
                                      Text(tr3('举报', 'Шағым', 'Пожаловаться'))),
                            ]),
                  ]),
              body: Column(children: [
                if (data.conversation.demandId != null)
                  Material(
                      color: t.surface,
                      child: ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                              tr3('关于一个需求', 'Тапсырыс туралы', 'По заявке')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => pushPage<void>(
                              context,
                              (_) => DemandDetailPage(
                                  demandId: data.conversation.demandId!)))),
                Expanded(
                    child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: data.messages.length,
                        itemBuilder: (context, i) {
                          final m = data.messages[data.messages.length - 1 - i];
                          return _Bubble(
                              message: m,
                              mine: m.senderId == me,
                              cards: data.cards);
                        })),
                if (data.blocked)
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Hint(tr3('你已拉黑对方，无法发送消息。', 'Сіз бұғаттадыңыз.',
                          'Вы заблокировали собеседника.'))),
                if (!data.blocked)
                  SafeArea(
                      top: false,
                      child: Container(
                          decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: t.line))),
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          child: Row(children: [
                            IconButton(
                                tooltip: tr3('更多', 'Тағы', 'Ещё'),
                                onPressed: () => more(data),
                                icon: const Icon(Icons.add_circle_outline)),
                            Expanded(
                                child: TextField(
                                    controller: input,
                                    minLines: 1,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => send(),
                                    decoration: InputDecoration(
                                        hintText: tr3('输入消息', 'Хабар жазыңыз',
                                            'Сообщение'),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 10),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(YRadius.pill)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(YRadius.pill),
                                            borderSide:
                                                BorderSide(color: t.line)),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(YRadius.pill),
                                            borderSide:
                                                BorderSide(color: t.ink))))),
                            const SizedBox(width: 6),
                            IconButton.filled(
                                tooltip: tr3('发送', 'Жіберу', 'Отправить'),
                                style: IconButton.styleFrom(
                                    backgroundColor: t.accent),
                                onPressed: send,
                                icon: Icon(Icons.arrow_upward,
                                    color: t.accentInk)),
                          ]))),
              ]));
        });
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.message, required this.mine, required this.cards});
  final ChatMessage message;
  final bool mine;
  final Map<String, String> cards;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final m = message;
    Widget content;
    switch (m.kind) {
      case MessageKind.text:
      case MessageKind.system:
        content = Text(m.text,
            style: TextStyle(color: mine ? t.bg : t.ink, height: 1.35));
      case MessageKind.image:
        content =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 180,
              height: 120,
              decoration: BoxDecoration(
                  color: t.line, borderRadius: BorderRadius.circular(YRadius.control)),
              child: Icon(Icons.image_outlined, size: 40, color: t.muted)),
          if (m.text.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.text,
                    style: TextStyle(
                        color: mine ? t.bg : t.ink, fontSize: YFont.caption))),
        ]);
      case MessageKind.demandCard:
      case MessageKind.quoteCard:
        final info = (cards[m.refId] ?? '').split('|');
        final demandId = m.kind == MessageKind.demandCard
            ? m.refId
            : (info.length > 1 ? info[1] : null);
        content = InkWell(
            onTap: demandId == null
                ? null
                : () => pushPage<void>(
                    context, (_) => DemandDetailPage(demandId: demandId)),
            child: Container(
                width: 230,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: t.bg,
                    borderRadius: BorderRadius.circular(YRadius.control),
                    border: Border.all(color: t.line)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          m.kind == MessageKind.demandCard
                              ? tr3('需求', 'Тапсырыс', 'Заявка')
                              : tr3('报价', 'Ұсыныс', 'Предложение'),
                          style: TextStyle(
                              color: t.accent,
                              fontSize: YFont.caption,
                              fontWeight: FontWeight.w700)),
                      Text(
                          info.first.isEmpty
                              ? tr3('已不可见', 'Қолжетімсіз', 'Недоступно')
                              : info.first,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (info.length > 2) Text(info[2]),
                    ])));
      case MessageKind.phoneShared:
        content =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              mine
                  ? tr3('你向对方展示了电话', 'Телефоныңызды көрсеттіңіз',
                      'Вы показали свой номер')
                  : tr3('对方向你展示了电话', 'Телефонын көрсетті',
                      'Собеседник показал номер'),
              style: TextStyle(
                  color: mine ? t.bg.withValues(alpha: 0.75) : t.muted, fontSize: YFont.caption)),
          SelectableText(m.text,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: mine ? t.bg : t.ink)),
        ]);
    }
    final bubble = Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        padding:
            m.kind == MessageKind.demandCard || m.kind == MessageKind.quoteCard
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: mine ? t.ink : t.surface,
            borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(YRadius.bubble),
                topRight: const Radius.circular(YRadius.bubble),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18))),
        child: content);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              bubble,
              Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: m.state == SendState.failed
                      ? InkWell(
                          onTap: () => attempt(
                              context, () => context.repos.resend(m.id)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.error_outline, size: 14, color: t.crit),
                            const SizedBox(width: 4),
                            Text(
                                tr3('发送失败，点击重试', 'Жіберілмеді, қайталау',
                                    'Не отправлено, повторить'),
                                style: TextStyle(color: t.crit, fontSize: YFont.caption)),
                          ]))
                      : Text(fmtTime(m.sentAt),
                          style: TextStyle(color: t.muted, fontSize: YFont.caption))),
            ]));
  }
}
