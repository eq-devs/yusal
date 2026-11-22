import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/state/session.dart';

/// One conversation as its page shows it.
class ChatData {
  ChatData(
      this.conversation, this.other, this.messages, this.cards, this.blocked);
  final Conversation conversation;
  final Account? other;
  final List<ChatMessage> messages;

  /// Demand titles of card messages by referenced id.
  final Map<String, String> cards;
  final bool blocked;
}

/// What an open conversation remembers between its reloads.
class ChatMemo {
  /// Card titles already looked up; a message's card never changes, so a
  /// reload after each new message does not ask for them again.
  final cards = <String, String>{};

  /// What the last load showed, to tell whether a poll found anything new.
  String shown = '';

  /// The unread batch was already marked read.
  bool readSent = false;

  static String signature(List<ChatMessage> msgs) => msgs.isEmpty
      ? '0'
      : '${msgs.length}|${msgs.last.id}|${msgs.last.state.name}';
}

/// Kept while the conversation's data is watched.
final chatMemoProvider =
    Provider.autoDispose.family<ChatMemo, String>((ref, id) => ChatMemo());

/// A conversation by id: its messages, the other side, card titles and
/// whether they are blocked. Marks an unread batch read once.
final chatProvider =
    FutureProvider.autoDispose.family<ChatData, String>((ref, id) async {
  final memo = ref.watch(chatMemoProvider(id));
  final chat = ref.watch(chatRepositoryProvider);
  final auth = ref.watch(authRepositoryProvider);
  final demands = ref.watch(demandRepositoryProvider);
  final applications = ref.watch(applicationRepositoryProvider);
  final me = ref.watch(sessionProvider).currentAccount?.id;
  if (me == null) throw const ApiFailure(ApiCodes.notSignedIn);

  Future<String> card(ChatMessage m) async {
    if (m.kind == MessageKind.demandCard) {
      return (await demands.demand(m.refId!))?.current.title ?? '';
    }
    final a = await applications.application(m.refId!);
    if (a == null) return '';
    final d = await demands.demand(a.demandId);
    return '${d?.current.title ?? ''}|${a.demandId}|${a.current.total == null ? pricingName(a.current.pricing) : money(a.current.total)}';
  }

  // The conversation, its messages and the block list do not depend on
  // each other: ask for them together.
  final convsF = chat.conversations();
  final msgsF = chat.messages(id);
  final blockedF = chat.blocked();
  final convs = await convsF;
  final c = convs.firstWhere((c) => c.id == id,
      orElse: () => throw const ApiFailure(ApiCodes.notFound));
  final otherF = auth.account(c.otherSide(me));
  final msgs = await msgsF;
  final missing = [
    for (final m in msgs)
      if (m.refId != null &&
          (m.kind == MessageKind.demandCard ||
              m.kind == MessageKind.quoteCard) &&
          !memo.cards.containsKey(m.refId))
        m
  ];
  await Future.wait([
    for (final m in missing)
      card(m).then((v) => memo.cards[m.refId!] = v,
          onError: (Object _) {/* drawn as unavailable; retried later */})
  ]);
  final blocked = (await blockedF).contains(c.otherSide(me));
  final other = await otherF;
  memo.shown = ChatMemo.signature(msgs);
  if (c.unread > 0 && !memo.readSent) {
    // Once per batch of unread: the reload this causes sees it read.
    memo.readSent = true;
    unawaited(chat.markConversationRead(c.id).catchError((Object _) {
      memo.readSent = false;
    }));
  }
  return ChatData(c, other, msgs, Map.of(memo.cards), blocked);
});
