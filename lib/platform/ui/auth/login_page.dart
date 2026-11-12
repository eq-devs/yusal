import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/settings.dart';
import '../../data/http/http_backend.dart';
import '../../data/mock/mock_backend.dart';
import '../../data/repositories.dart';
import '../../data/mock/mock_seed.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'social_sign_in.dart';

/// Sign-in: Google / Apple against the real backend, phone code on the
/// demo backend. Pops `true` once signed in so the caller continues the
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

  /// Google / Apple through the native SDK, then the backend.
  Future<void> social(HttpBackend api, String provider) async {
    final account = await attempt(context, () async {
      ({String idToken, String? name})? r;
      try {
        r = provider == 'apple'
            ? await SocialSignIn.apple()
            : await SocialSignIn.google();
      } catch (e) {
        throw ApiFailure(ApiCodes.network, '$e');
      }
      if (r == null) return null; // cancelled
      return api.signInWithProvider(provider, r.idToken, name: r.name);
    });
    if (account != null && mounted) Navigator.pop(context, true);
  }

  /// Development sign-in by name and the one-tap test accounts. On by
  /// default while the app is in development; build with
  /// `--dart-define=YUSAL_DEV_LOGIN=false` to hide them. The backend must run
  /// with DEV_LOGIN=true.
  static const _devLogin =
      bool.fromEnvironment('YUSAL_DEV_LOGIN', defaultValue: true);

  /// One-tap test accounts, by role. Each is a real account on the backend
  /// with real history, filled by yusal-api `tool/seed/seed.py` (the keys
  /// must match its PEOPLE). "Test Admin" is the superadmin the backend makes
  /// with DEV_ADMIN=true; "Test Owner" stays an empty new account.
  static const testPersonaGroups = [
    (
      '业主',
      [
        ('seed:aigerim', 'Айгерім · 施工中', Icons.home_outlined),
        ('seed:dinara', 'Динара · 已完工', Icons.cottage_outlined),
        ('seed:asel', 'Асель · 比价中', Icons.request_quote_outlined),
        ('seed:zhanar', 'Жанар · 求点评', Icons.forum_outlined),
        ('Test Owner', '新用户 · 空账号', Icons.person_add_alt),
      ]
    ),
    (
      '师傅与团队',
      [
        ('seed:bolat', 'Болат · 瓦工 · 已认证', Icons.construction_outlined),
        ('seed:erlan', 'Ерлан · 电工', Icons.electrical_services_outlined),
        ('seed:ruslan', 'Руслан · 认证审核中', Icons.plumbing_outlined),
        ('seed:gulnar', 'Гүлнар · 工程师', Icons.architecture_outlined),
        ('seed:nurlan', 'Нұрлан · 施工队', Icons.groups_outlined),
        ('seed:samat', 'Самат · 屋面队', Icons.roofing_outlined),
      ]
    ),
    (
      '后台',
      [
        ('Test Admin', '超级管理员', Icons.admin_panel_settings_outlined),
        ('seed:moderator', '审核员', Icons.gavel_outlined),
        ('seed:operator', '运营', Icons.campaign_outlined),
        ('seed:viewer', '只读', Icons.visibility_outlined),
      ]
    ),
    (
      '受限',
      [
        ('seed:spam', 'Стройбаза · 受限 · 申诉中', Icons.block_outlined),
      ]
    ),
  ];

  Future<void> devSignIn(HttpBackend api, [String? persona]) async {
    final n = (persona ?? name.text).trim();
    if (n.isEmpty) return;
    final account =
        await attempt(context, () => api.signInWithProvider('dev', n, name: n));
    if (account != null && mounted) Navigator.pop(context, true);
  }

  Widget _socialBody(BuildContext context, HttpBackend api) {
    final t = YTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Text(
          tr3('欢迎来到 Yusal', 'Yusal-ға қош келдіңіз',
              'Добро пожаловать в Yusal'),
          style: const TextStyle(
              fontSize: YFont.display, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
          tr3(
              '浏览不需要登录。发布、点评、报名、联系和云备份时需要登录。',
              'Қарау үшін кіру керек емес. Жариялау, пікір, өтінім, байланыс және сақтық көшірме үшін кіріңіз.',
              'Смотреть можно без входа. Для публикации, отзывов, откликов, связи и резервных копий нужно войти.'),
          style: TextStyle(color: t.muted, height: 1.4)),
      const SizedBox(height: 20),
      if (SocialSignIn.appleAvailable) ...[
        BusyButton(
            label: tr3('通过 Apple 登录', 'Apple арқылы кіру', 'Войти через Apple'),
            icon: Icons.apple,
            onPressed: () => social(api, 'apple')),
        const SizedBox(height: 12),
      ],
      if (SocialSignIn.googleAvailable)
        BusyButton(
            label:
                tr3('通过 Google 登录', 'Google арқылы кіру', 'Войти через Google'),
            icon: Icons.account_circle_outlined,
            outlined: SocialSignIn.appleAvailable,
            onPressed: () => social(api, 'google')),
      if (!SocialSignIn.appleAvailable && !SocialSignIn.googleAvailable)
        Hint(tr3('请在手机 App 中登录。', 'Телефондағы қолданбада кіріңіз.',
            'Войдите в мобильном приложении.')),
      if (_devLogin) ...[
        const SectionTitle('开发登录 · Dev', top: 28),
        TextField(
            key: const Key('dev-login-name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        BusyButton(
            key: const Key('dev-login'),
            label: 'Dev sign in',
            outlined: true,
            onPressed: () => devSignIn(api)),
        const SizedBox(height: 16),
        Text('测试账号 · Test accounts', style: TextStyle(color: t.muted)),
        for (final (group, personas) in testPersonaGroups) ...[
          const SizedBox(height: 12),
          Text(group,
              style: TextStyle(color: t.muted, fontSize: YFont.caption)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (id, label, icon) in personas)
              ActionChip(
                  key: Key('test-login-$id'),
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  onPressed: () => devSignIn(api, id)),
          ]),
        ],
      ],
    ]);
  }

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.repos;
    if (repos is HttpBackend) {
      return PageScaffold(
          title: tr3('登录或注册', 'Кіру не тіркелу', 'Вход или регистрация'),
          body: _socialBody(context, repos));
    }
    final t = YTokens.of(context);
    final mock = context.mock;
    return PageScaffold(
        title: tr3('登录或注册', 'Кіру не тіркелу', 'Вход или регистрация'),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (context.isDemo)
            Hint(tr3(
                '演示登录：不会发送短信，也不会验证真实手机号。平台数据重启后重置。',
                'Демо кіру: SMS жіберілмейді, нақты телефон расталмайды. Деректер қайта іске қосқанда өшеді.',
                'Демо-вход: SMS не отправляется, номер не проверяется. Данные сбрасываются при перезапуске.')),
          const SizedBox(height: 8),
          Text(
              tr3('欢迎来到 Yusal', 'Yusal-ға қош келдіңіз',
                  'Добро пожаловать в Yusal'),
              style: display(size: 26, color: t.ink)),
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
              style: TextStyle(color: t.muted, fontSize: YFont.caption)),
          if (mock != null) ...[
            SectionTitle(tr3('测试账号', 'Сынақ аккаунттары', 'Тестовые аккаунты'),
                top: 28),
            for (final (id, label) in [
              (SeedIds.owner, '${tr3('业主', 'Үй иесі', 'Владелец')} Айгерім'),
              (SeedIds.owner2, '${tr3('业主', 'Үй иесі', 'Владелец')} Динара'),
              (SeedIds.mason, '${tr3('瓦工', 'Қалаушы', 'Каменщик')} Болат'),
              (
                SeedIds.electrician,
                '${tr3('电工', 'Электрик', 'Электрик')} Ерлан'
              ),
              (SeedIds.team, '${tr3('施工队', 'Бригада', 'Бригада')} Нұрлан'),
              (
                SeedIds.roofTeam,
                '${tr3('屋面队', 'Шатыр бригадасы', 'Кровельщики')} Самат'
              ),
              (SeedIds.admin, '${tr3('审核员', 'Модератор', 'Модератор')} Admin'),
            ])
              ListTile(
                  leading: Avatar(label.split(' ').last, size: 36),
                  title: Text(label),
                  trailing: Icon(Icons.chevron_right, color: t.faint),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    mock.signInAs(id);
                    Navigator.pop(context, true);
                  }),
            Text(fmtDay(context.now),
                style: TextStyle(color: t.muted, fontSize: YFont.caption)),
          ],
        ]));
  }
}
