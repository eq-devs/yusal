import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/settings.dart';
import '../../voice/voice_overlay.dart';
import '../../data/http/http_backend.dart';
import '../../data/repositories.dart';
import '../../shared/ui/scope.dart';
import '../../shared/ui/theme.dart';
import '../../shared/ui/widgets.dart';
import 'social_sign_in.dart';

/// Sign-in: Google / Apple, plus the one-tap test accounts while the app is
/// in development. Pops `true` once signed in so the caller continues the
/// action that needed an account (publish, apply, contact, back up).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController();

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
      // Test sign-in: by name, and one tap per role. The backend must run
      // with DEV_LOGIN=true.
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
    ]);
  }

  // The voice orb would cover the test accounts at the bottom.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => VoiceBar.hidden.value++);
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => VoiceBar.hidden.value--);
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.repos;
    return PageScaffold(
        title: tr3('登录或注册', 'Кіру не тіркелу', 'Вход или регистрация'),
        body: repos is HttpBackend
            ? _socialBody(context, repos)
            : Hint(tr3('暂时无法登录。', 'Қазір кіру мүмкін емес.',
                'Вход сейчас недоступен.')));
  }
}
