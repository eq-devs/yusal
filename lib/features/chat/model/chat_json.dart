import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Chat models to and from yusal-api JSON.

ChatMessage messageFrom(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    conversationId: j['conversation_id'] as String,
    senderId: j['sender_id'] as String,
    kind: jsonEnum(MessageKind.values, j['kind'], MessageKind.text),
    sentAt: jsonTime(j['sent_at']),
    text: j['text'] as String? ?? '',
    refId: j['ref_id'] as String?);

Conversation conversationFrom(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    participants: jsonStrings(j['participants']),
    createdAt: jsonTime(j['created_at']),
    demandId: j['demand_id'] as String?,
    lastMessage: j['last_message'] == null
        ? null
        : messageFrom(j['last_message'] as Map<String, dynamic>),
    unread: jsonInt(j['unread']) ?? 0);

AppNotification noticeFrom(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    accountId: j['account_id'] as String,
    kind: jsonEnum(NoticeKind.values, j['kind'], NoticeKind.newApplication),
    refType: jsonEnum(RefType.values, j['ref_type'], RefType.demand),
    refId: j['ref_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    read: j['read'] == true,
    createdAt: jsonTime(j['created_at']));
