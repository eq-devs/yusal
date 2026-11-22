import 'package:flutter/widgets.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/shared/ui/widgets.dart';

/// Asks for the phone number that chats share on request; true once saved.
Future<bool> editPhone(BuildContext context) async {
  final me = context.session.currentAccount;
  if (me == null) return false;
  final phone = await askText(
      context, tr3('手机号', 'Телефон нөмірі', 'Номер телефона'),
      hint: '+7 700 000 00 00', initial: me.phone, required: false, lines: 1);
  if (phone == null || !context.mounted) return false;
  final saved = await attempt(
      context, () => context.read(authRepositoryProvider).updatePhone(phone),
      success: tr3('已保存', 'Сақталды', 'Сохранено'));
  return saved != null;
}
