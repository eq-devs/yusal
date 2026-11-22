import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yusal/app/settings.dart';
import 'package:yusal/data/http/http_backend.dart';
import 'package:yusal/data/repositories.dart';
import 'package:yusal/shared/ui/components.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/shared/ui/widgets.dart';
import 'package:yusal/features/auth/social_sign_in.dart';

/// The ways the signed-in account can sign in: link Google or Apple, set an
/// email password, or remove one. The last way cannot be removed.
class SignInMethodsPage extends StatefulWidget {
  const SignInMethodsPage({super.key, required this.api});
  final HttpBackend api;
  @override
  State<SignInMethodsPage> createState() => _SignInMethodsPageState();
}

class _SignInMethodsPageState extends State<SignInMethodsPage> {
  late Future<List<SignInMethod>?> _load = _fetch();
  List<SignInMethod>? _methods;

  Future<List<SignInMethod>?> _fetch() async {
    final m = await attempt(context, widget.api.signInMethods);
    if (m != null && mounted) setState(() => _methods = m);
    return m;
  }

  /// Applies a change, keeping the list the server sent back.
  Future<void> _apply(Future<List<SignInMethod>> Function() change,
      {String? success}) async {
    final m = await attempt(context, change, success: success);
    if (m != null && mounted) setState(() => _methods = m);
  }

  SignInMethod? _find(String provider) =>
      _methods?.where((m) => m.provider == provider).firstOrNull;

  Future<void> _link(String provider) async {
    // The native sheet first: cancelling it is not an error and says nothing.
    final r = await attempt(context, () async {
      try {
        return provider == 'apple'
            ? await SocialSignIn.apple()
            : await SocialSignIn.google();
      } catch (e) {
        throw ApiFailure(ApiCodes.network, '$e');
      }
    });
    if (r == null || !mounted) return;
    await _apply(() => widget.api.linkSignIn(provider, r.idToken),
        success: tr3('已绑定', 'Қосылды', 'Привязано'));
  }

  Future<void> _unlink(String provider, String name) async {
    if (!await confirmDialog(context,
            tr3('解绑$name？', '$name ажырату керек пе?', 'Отвязать $name?'),
            body: tr3('解绑后不能再用它登录这个账号。', 'Онымен бұл аккаунтқа кіре алмайсыз.',
                'Войти в этот аккаунт через него больше не получится.'),
            ok: tr3('解绑', 'Ажырату', 'Отвязать'),
            danger: true) ||
        !mounted) {
      return;
    }
    await _apply(() => widget.api.unlinkSignIn(provider),
        success: tr3('已解绑', 'Ажыратылды', 'Отвязано'));
  }

  Future<void> _password() async {
    final pw = await showDialog<String>(
        context: context, builder: (_) => const _PasswordDialog());
    if (pw == null || !mounted) return;
    await _apply(() => widget.api.setPassword(pw),
        success: tr3('密码已保存', 'Құпиясөз сақталды', 'Пароль сохранён'));
  }

  Widget _row(
      {required Key key,
      required IconData icon,
      required String provider,
      required String name}) {
    final m = _find(provider);
    final linked = m != null;
    return SettingsRow(
        key: key,
        icon: icon,
        title: name,
        subtitle: linked
            ? (m.email.isEmpty ? tr3('已绑定', 'Қосылған', 'Привязан') : m.email)
            : tr3('未绑定', 'Қосылмаған', 'Не привязан'),
        trailing: TextButton(
            key: Key('$key-action'),
            onPressed:
                linked ? () => _unlink(provider, name) : () => _link(provider),
            child: Text(linked
                ? tr3('解绑', 'Ажырату', 'Отвязать')
                : tr3('绑定', 'Қосу', 'Привязать'))));
  }

  @override
  Widget build(BuildContext context) {
    final me = context.repos.currentAccount;
    final email = _find('email');
    return PageScaffold(
        title: tr3('登录方式', 'Кіру тәсілдері', 'Способы входа'),
        body: FutureBuilder(
            future: _load,
            builder: (context, snap) {
              if (_methods == null) {
                return snap.connectionState == ConnectionState.done
                    ? Center(
                        child: TextButton(
                            onPressed: () => setState(() => _load = _fetch()),
                            child: Text(tr3('重试', 'Қайталау', 'Повторить'))))
                    : const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Hint(tr3(
                        '绑定多种方式后，用其中任何一种都能登录同一个账号。至少保留一种。',
                        'Бірнеше тәсіл қосылса, кез келгенімен бір аккаунтқа кіресіз. Кемінде біреуі қалуы керек.',
                        'С любым привязанным способом вы входите в один и тот же аккаунт. Хотя бы один должен остаться.')),
                    SettingsGroup(children: [
                      if (SocialSignIn.appleAvailable || _find('apple') != null)
                        _row(
                            key: const Key('method-apple'),
                            icon: Icons.apple,
                            provider: 'apple',
                            name: 'Apple'),
                      if (SocialSignIn.googleAvailable ||
                          _find('google') != null)
                        _row(
                            key: const Key('method-google'),
                            icon: Icons.account_circle_outlined,
                            provider: 'google',
                            name: 'Google'),
                      SettingsRow(
                          key: const Key('method-email'),
                          icon: Icons.mail_outline,
                          title: tr3(
                              '邮箱和密码', 'Пошта мен құпиясөз', 'Почта и пароль'),
                          subtitle: email != null
                              ? email.email
                              : (me?.email.isNotEmpty ?? false)
                                  ? tr3('未设置密码', 'Құпиясөз жоқ',
                                      'Пароль не задан')
                                  : tr3('账号没有邮箱', 'Аккаунтта пошта жоқ',
                                      'У аккаунта нет почты'),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            if (me?.email.isNotEmpty ?? false)
                              TextButton(
                                  key: const Key('method-email-password'),
                                  onPressed: _password,
                                  child: Text(email != null
                                      ? tr3('改密码', 'Өзгерту', 'Сменить')
                                      : tr3('设密码', 'Орнату', 'Задать'))),
                            if (email != null)
                              TextButton(
                                  key: const Key('method-email-remove'),
                                  onPressed: () => _unlink(
                                      'email', tr3('邮箱登录', 'Пошта', 'почту')),
                                  child: Text(tr3('移除', 'Алу', 'Убрать'))),
                          ])),
                    ]),
                  ]);
            }));
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _pw = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _pw.text.length >= 8;
    return AlertDialog(
        title: Text(tr3('设置登录密码', 'Құпиясөз орнату', 'Пароль для входа')),
        content: TextField(
            key: const Key('method-password-field'),
            controller: _pw,
            autofocus: true,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.newPassword],
            inputFormatters: [LengthLimitingTextInputFormatter(72)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText:
                    tr3('至少 8 位', 'Кемінде 8 таңба', 'Не короче 8 символов'),
                suffixIcon: IconButton(
                    icon: Icon(_show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _show = !_show)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
          FilledButton(
              key: const Key('method-password-save'),
              onPressed: ok ? () => Navigator.pop(context, _pw.text) : null,
              child: Text(tr3('保存', 'Сақтау', 'Сохранить'))),
        ]);
  }
}
