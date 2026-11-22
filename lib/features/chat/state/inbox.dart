import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/shared/state/session.dart';

/// Unread chats and notices together, asked for at the same time.
final unreadProvider = FutureProvider.autoDispose<int>((ref) async {
  final counts = await Future.wait([
    ref.watch(chatRepositoryProvider).unreadMessages(),
    ref.watch(notificationRepositoryProvider).unreadNotifications(),
  ]);
  return counts[0] + counts[1];
});

/// My conversations, each with the account on the other side.
final conversationsProvider =
    FutureProvider.autoDispose<List<(Conversation, Account?)>>((ref) async {
  final chat = ref.watch(chatRepositoryProvider);
  final auth = ref.watch(authRepositoryProvider);
  final me = ref.watch(sessionProvider).currentAccount?.id ?? '';
  final list = await chat.conversations();
  final others =
      await Future.wait([for (final c in list) auth.account(c.otherSide(me))]);
  return [for (var i = 0; i < list.length; i++) (list[i], others[i])];
});

/// My in-app notices.
final noticesProvider = FutureProvider.autoDispose<List<AppNotification>>(
    (ref) => ref.watch(notificationRepositoryProvider).notifications());
