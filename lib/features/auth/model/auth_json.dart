import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Auth models to and from yusal-api JSON.

// ── accounts ──
/// An account from the server: the signed-in user's own view (with email)
/// or the public view of someone else (with `deleted`).
Account accountFrom(Map<String, dynamic> u) => Account(
    id: u['id'] as String,
    phone: u['phone'] as String? ?? '',
    displayName: u['display_name'] as String? ?? '',
    email: u['email'] as String? ?? '',
    deleted: u['deleted'] == true,
    restricted: u['restricted'] == true,
    role: (u['admin_role'] as String?)?.nullIfEmpty,
    createdAt: jsonTime(u['created_at']));
