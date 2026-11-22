import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/api_failure.dart';
import 'package:yusal/services/api/codec.dart';
import 'package:yusal/shared/model/models.dart';

/// Conversations, messages and in-app notices.

abstract interface class ChatRepository {
  Future<List<Conversation>> conversations();
  Future<Conversation> openConversation(String otherAccountId,
      {String? demandId});
  Future<List<ChatMessage>> messages(String conversationId);
  Future<ChatMessage> send(String conversationId, MessageKind kind,
      {String text = '', String? refId});

  /// Retries a failed message.
  Future<ChatMessage> resend(String messageId);
  Future<void> markConversationRead(String conversationId);
  Future<void> block(String accountId);
  Future<void> unblock(String accountId);
  Future<Set<String>> blocked();

  /// Shows the caller's phone number to one partner, on purpose.
  Future<ChatMessage> sharePhone(String conversationId);
  Future<int> unreadMessages();
}

abstract interface class NotificationRepository {
  Future<List<AppNotification>> notifications();
  Future<int> unreadNotifications();
  Future<void> markRead(String id);
  Future<void> markAllRead();
}

/// Overridden in `lib/app` with the one backend (the fake in tests).
final chatRepositoryProvider = Provider<ChatRepository>((ref) =>
    throw UnimplementedError('chatRepositoryProvider is not overridden'));
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) =>
    throw UnimplementedError(
        'notificationRepositoryProvider is not overridden'));

/// [ChatRepository] over yusal-api.
mixin HttpChatRepository on ApiClient implements ChatRepository {
  @override
  Future<List<Conversation>> conversations() async {
    // Polled by the shell; signed out there is nothing to ask the server.
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    final list = [
      for (final j in await getList('/client/conversations'))
        conversationFrom(j)
    ];
    await loadNames(list.expand((c) => c.participants));
    return list;
  }

  @override
  Future<Conversation> openConversation(String otherAccountId,
      {String? demandId}) async {
    final c =
        conversationFrom(await write('POST', '/client/conversations', body: {
      'account_id': otherAccountId,
      if (demandId != null) 'demand_id': demandId,
    }) as Map<String, dynamic>);
    await loadNames(c.participants);
    return c;
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
        for (final j
            in await getList('/client/conversations/$conversationId/messages'))
          messageFrom(j)
      ];

  @override
  Future<ChatMessage> send(String conversationId, MessageKind kind,
          {String text = '', String? refId}) async =>
      messageFrom(await write(
          'POST', '/client/conversations/$conversationId/messages',
          body: {
            'kind': kind.name,
            'text': text,
            if (refId != null) 'ref_id': refId,
          }) as Map<String, dynamic>);

  @override
  Future<ChatMessage> resend(String messageId) async =>
      messageFrom(await write('POST', '/client/messages/$messageId/resend')
          as Map<String, dynamic>);

  @override
  Future<void> markConversationRead(String conversationId) async {
    await write('POST', '/client/conversations/$conversationId/read');
  }

  @override
  Future<void> block(String accountId) async {
    await write('POST', '/client/blocks', body: {'account_id': accountId});
  }

  @override
  Future<void> unblock(String accountId) async {
    await write('DELETE', '/client/blocks/$accountId');
  }

  @override
  Future<Set<String>> blocked() async {
    if (currentId == null) return {};
    return {
      for (final id in await request('GET', '/client/blocks') as List)
        id as String
    };
  }

  @override
  Future<ChatMessage> sharePhone(String conversationId) async => messageFrom(
      await write('POST', '/client/conversations/$conversationId/share-phone')
          as Map<String, dynamic>);

  @override
  Future<int> unreadMessages() async {
    if (currentId == null) return 0;
    final j = await request('GET', '/client/messages/unread-count')
        as Map<String, dynamic>;
    return (j['count'] as num).toInt();
  }
}

/// [NotificationRepository] over yusal-api.
mixin HttpNotificationRepository on ApiClient
    implements NotificationRepository {
  @override
  Future<List<AppNotification>> notifications() async {
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return [
      for (final j in await getList('/client/notifications')) noticeFrom(j)
    ];
  }

  @override
  Future<int> unreadNotifications() async {
    if (currentId == null) return 0;
    final j = await request('GET', '/client/notifications/unread-count')
        as Map<String, dynamic>;
    return (j['count'] as num).toInt();
  }

  @override
  Future<void> markRead(String id) async {
    await write('POST', '/client/notifications/$id/read');
  }

  @override
  Future<void> markAllRead() async {
    await write('POST', '/client/notifications/read-all');
  }
}
