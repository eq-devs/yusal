import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/chat/model/chat_json.dart';
import 'package:yusal/features/shared/model/models.dart';

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

final chatRepositoryProvider = Provider<ChatRepository>(
    (ref) => HttpChatRepository(ref.watch(apiClientProvider)));
final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => HttpNotificationRepository(ref.watch(apiClientProvider)));

/// [ChatRepository] over yusal-api.
final class HttpChatRepository implements ChatRepository {
  HttpChatRepository(this.api);
  final ApiClient api;

  @override
  Future<List<Conversation>> conversations() async {
    // Polled by the shell; signed out there is nothing to ask the server.
    if (api.currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    final list = [
      for (final j in await api.getList('/client/conversations'))
        conversationFrom(j)
    ];
    return list;
  }

  @override
  Future<Conversation> openConversation(String otherAccountId,
      {String? demandId}) async {
    final c = conversationFrom(
        await api.write('POST', '/client/conversations', body: {
      'account_id': otherAccountId,
      if (demandId != null) 'demand_id': demandId,
    }) as Map<String, dynamic>);
    return c;
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
        for (final j in await api
            .getList('/client/conversations/$conversationId/messages'))
          messageFrom(j)
      ];

  @override
  Future<ChatMessage> send(String conversationId, MessageKind kind,
          {String text = '', String? refId}) async =>
      messageFrom(await api.write(
          'POST', '/client/conversations/$conversationId/messages',
          body: {
            'kind': kind.name,
            'text': text,
            if (refId != null) 'ref_id': refId,
          }) as Map<String, dynamic>);

  @override
  Future<ChatMessage> resend(String messageId) async =>
      messageFrom(await api.write('POST', '/client/messages/$messageId/resend')
          as Map<String, dynamic>);

  @override
  Future<void> markConversationRead(String conversationId) async {
    await api.write('POST', '/client/conversations/$conversationId/read');
  }

  @override
  Future<void> block(String accountId) async {
    await api.write('POST', '/client/blocks', body: {'account_id': accountId});
  }

  @override
  Future<void> unblock(String accountId) async {
    await api.write('DELETE', '/client/blocks/$accountId');
  }

  @override
  Future<Set<String>> blocked() async {
    if (api.currentId == null) return {};
    return {
      for (final id in await api.request('GET', '/client/blocks') as List)
        id as String
    };
  }

  @override
  Future<ChatMessage> sharePhone(String conversationId) async =>
      messageFrom(await api.write(
              'POST', '/client/conversations/$conversationId/share-phone')
          as Map<String, dynamic>);

  @override
  Future<int> unreadMessages() async {
    if (api.currentId == null) return 0;
    final j = await api.request('GET', '/client/messages/unread-count')
        as Map<String, dynamic>;
    return (j['count'] as num).toInt();
  }
}

/// [NotificationRepository] over yusal-api.
final class HttpNotificationRepository implements NotificationRepository {
  HttpNotificationRepository(this.api);
  final ApiClient api;

  @override
  Future<List<AppNotification>> notifications() async {
    if (api.currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return [
      for (final j in await api.getList('/client/notifications')) noticeFrom(j)
    ];
  }

  @override
  Future<int> unreadNotifications() async {
    if (api.currentId == null) return 0;
    final j = await api.request('GET', '/client/notifications/unread-count')
        as Map<String, dynamic>;
    return (j['count'] as num).toInt();
  }

  @override
  Future<void> markRead(String id) async {
    await api.write('POST', '/client/notifications/$id/read');
  }

  @override
  Future<void> markAllRead() async {
    await api.write('POST', '/client/notifications/read-all');
  }
}
