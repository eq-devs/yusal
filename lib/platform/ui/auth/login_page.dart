import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../data/mock/mock_backend.dart';
import '../../data/mock/mock_seed.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Phone sign-in. Pops `true` once signed in so the caller continues the
/// action that needed an account (publish, apply, contact, back up).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController(text: '+7 ');
  final code = TextEditingController();
  final name = TextEditingController();
  bool codeSent = false;

  Future<void> sendCode() async {
    final ok = await attempt(context, () async {
      await context.repos.requestCode(phone.text);
      return true;
    });
    if (ok == true && mounted) setState(() => codeSent = true);
  }

  Future<void> verify() async {
    final account = await attempt(
        context,
        () => context.repos
            .verify(phone.text, code.text, displayName: name.text));
    if (account != null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final mock = context.mock;
    return PageScaffold(
        title: tr3('登录或注册', 'Кіру не тіркелу', 'Вход или регистрация'),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Text(
              tr3('欢迎来到 Yusal', 'Yusal-ға қош келдіңіз',
                  'Добро пожаловать в Yusal'),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              tr3(
                  '浏览不需要登录。发布、报名、报价、联系和云备份时需要手机号验证。',
                  'Қарау үшін кіру керек емес. Жариялау, өтінім, байланыс және сақтық көшірме үшін телефон расталады.',
                  'Смотреть можно без входа. Для публикации, откликов, связи и резервных копий нужен телефон.'),
              style: TextStyle(color: t.muted, height: 1.4)),
          const SizedBox(height: 20),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration:
                  InputDecoration(labelText: tr3('手机号', 'Телефон', 'Телефон'))),
          if (codeSent) ...[
            const SizedBox(height: 12),
            TextField(
                controller: code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: tr3('验证码', 'Код', 'Код из SMS'),
                    helperText: mock == null
                        ? null
                        : tr3(
                            '测试环境验证码：${MockBackend.verificationCode}',
                            'Сынақ коды: ${MockBackend.verificationCode}',
                            'Тестовый код: ${MockBackend.verificationCode}'))),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText:
                        tr3('称呼（新用户）', 'Атыңыз (жаңа)', 'Имя (для новых)'))),
          ],
          const SizedBox(height: 20),
          BusyButton(
              label: codeSent
                  ? tr3('登录', 'Кіру', 'Войти')
                  : tr3('获取验证码', 'Код алу', 'Получить код'),
              onPressed: codeSent ? verify : sendCode),
          const SizedBox(height: 14),
          Text(
              tr3(
                  '手机号默认不公开；手机号验证不等于实名认证。',
                  'Телефон әдепкіде жасырын; телефонды растау — жеке басты растау емес.',
                  'Номер скрыт по умолчанию; подтверждение телефона — не проверка личности.'),
              style: TextStyle(color: t.muted, fontSize: 12)),
          if (mock != null) ...[
            const SectionTitle('测试账号 · Test', top: 28),
            for (final (id, label) in [
              (SeedIds.owner, '业主 Айгерім'),
              (SeedIds.mason, '瓦工 Болат'),
              (SeedIds.team, '施工队 Нұрлан'),
              (SeedIds.admin, '审核员 Admin'),
            ])
              ListTile(
                  leading: Avatar(label.split(' ').last, size: 36),
                  title: Text(label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    mock.signInAs(id);
                    Navigator.pop(context, true);
                  }),
            Text(fmtDay(context.now),
                style: TextStyle(color: t.faint, fontSize: 11)),
          ],
        ]));
  }
}
