import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/voice/widgets/voice_overlay.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/auth/repository/social_sign_in.dart';
import 'package:yusal/features/shared/brand/brand.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Sign-in: Google / Apple or email and password, plus the one-tap test
/// accounts while the app is in development. Pops `true` once signed in so the caller continues the
/// action that needed an account (publish, apply, contact, back up).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final emailName = TextEditingController();

  /// Email form: false signs in, true creates the account.
  bool registering = false;
  bool showPassword = false;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Email and password, checked here first so the common slips get a
  /// plain message instead of a round trip.
  Future<void> emailSignIn(HttpAuthRepository api) async {
    final e = email.text.trim();
    if (!_emailShape.hasMatch(e)) {
      toast(context,
          tr3('请输入正确的邮箱', 'Поштаны дұрыс енгізіңіз', 'Введите верную почту', 'Enter a valid email', ky: 'Туура email киргизиңиз', uz: 'Toʻgʻri email kiriting'));
      return;
    }
    if (password.text.isEmpty || (registering && password.text.length < 8)) {
      toast(
          context,
          tr3('密码至少 8 位', 'Құпиясөз кемінде 8 таңба',
              'Пароль не короче 8 символов',
              'Password must be at least 8 characters', ky: 'Сырсөз кеминде 8 белгиден турушу керек', uz: 'Parol kamida 8 ta belgidan iborat boʻlishi kerak'));
      return;
    }
    final account = await attempt(
        context,
        () => api.signInWithEmail(e, password.text,
            register: registering, name: emailName.text));
    if (account != null && mounted) Navigator.pop(context, true);
  }

  /// Google / Apple through the native SDK, then the backend.
  Future<void> social(HttpAuthRepository api, String provider) async {
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
        ('seed:aigerim', 'Айгерім · 施工中', YIcons.home),
        ('seed:dinara', 'Динара · 已完工', YIcons.home),
        ('seed:asel', 'Асель · 比价中', YIcons.budget),
        ('seed:zhanar', 'Жанар · 求点评', YIcons.chat),
        ('Test Owner', '新用户 · 空账号', YIcons.personAdd),
      ]
    ),
    (
      '师傅与团队',
      [
        ('seed:bolat', 'Болат · 瓦工 · 已认证', YIcons.tools),
        ('seed:erlan', 'Ерлан · 电工', YIcons.bolt),
        ('seed:ruslan', 'Руслан · 认证审核中', YIcons.water),
        ('seed:gulnar', 'Гүлнар · 工程师', YIcons.design),
        ('seed:nurlan', 'Нұрлан · 施工队', YIcons.people),
        ('seed:samat', 'Самат · 屋面队', YIcons.roof),
      ]
    ),
    (
      '后台',
      [
        ('Test Admin', '超级管理员', YIcons.verified),
        ('seed:moderator', '审核员', YIcons.gavel),
        ('seed:operator', '运营', YIcons.megaphone),
        ('seed:viewer', '只读', YIcons.eye),
      ]
    ),
    (
      '受限',
      [
        ('seed:spam', 'Стройбаза · 受限 · 申诉中', YIcons.block),
      ]
    ),
  ];

  Future<void> devSignIn(HttpAuthRepository api, [String? persona]) async {
    final n = (persona ?? name.text).trim();
    if (n.isEmpty) return;
    final account =
        await attempt(context, () => api.signInWithProvider('dev', n, name: n));
    if (account != null && mounted) Navigator.pop(context, true);
  }

  Widget _socialBody(BuildContext context, HttpAuthRepository api) {
    final t = YTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft, child: YusalMark(height: 56)),
      const SizedBox(height: 16),
      Text(
          tr3('欢迎来到 Yusal', 'Yusal-ға қош келдіңіз',
              'Добро пожаловать в Yusal',
              'Welcome to Yusal', ky: "Yusal'га кош келиңиз", uz: 'Yusal ga xush kelibsiz'),
          style: const TextStyle(
              fontSize: YFont.display, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
          tr3(
              '浏览不需要登录。发布、点评、报名、联系和云备份时需要登录。',
              'Қарау үшін кіру керек емес. Жариялау, пікір, өтінім, байланыс және сақтық көшірме үшін кіріңіз.',
              'Смотреть можно без входа. Для публикации, отзывов, откликов, связи и резервных копий нужно войти.',
              'You can browse without signing in. Sign in to publish, review, respond, get in touch and back up.', ky: 'Кирбей эле карап чыксаңыз болот. Жарыялоо, пикир калтыруу, жооп берүү, байланышуу жана резервдик көчүрмө үчүн кириңиз.', uz: 'Kirmasdan ham koʻrishingiz mumkin. Eʼlon qilish, sharh qoldirish, javob berish, bogʻlanish va zaxira nusxa uchun kiring.'),
          style: TextStyle(color: t.muted, height: 1.4)),
      const SizedBox(height: 20),
      if (SocialSignIn.appleAvailable) ...[
        BusyButton(
            label: tr3('通过 Apple 登录', 'Apple арқылы кіру', 'Войти через Apple', 'Sign in with Apple', ky: 'Apple менен кирүү', uz: 'Apple orqali kirish'),
            icon: Icons.apple,
            onPressed: () => social(api, 'apple')),
        const SizedBox(height: 12),
      ],
      if (SocialSignIn.googleAvailable)
        BusyButton(
            label:
                tr3('通过 Google 登录', 'Google арқылы кіру', 'Войти через Google', 'Sign in with Google', ky: 'Google менен кирүү', uz: 'Google orqali kirish'),
            icon: YIcons.profile,
            outlined: SocialSignIn.appleAvailable,
            onPressed: () => social(api, 'google')),
      if (!SocialSignIn.appleAvailable && !SocialSignIn.googleAvailable)
        Hint(tr3('请在手机 App 中登录。', 'Телефондағы қолданбада кіріңіз.',
            'Войдите в мобильном приложении.',
            'Sign in in the mobile app.', ky: 'Мобилдик тиркемеде кириңиз.', uz: 'Mobil ilovada kiring.')),
      ..._emailForm(context, api),
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
        Text(group, style: TextStyle(color: t.muted, fontSize: YFont.caption)),
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

  List<Widget> _emailForm(BuildContext context, HttpAuthRepository api) {
    final t = YTokens.of(context);
    return [
      const SizedBox(height: 24),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(tr3('或用邮箱', 'немесе поштамен', 'или по почте', 'or with email', ky: 'же email менен', uz: 'yoki email orqali'),
                style: TextStyle(color: t.muted, fontSize: YFont.caption))),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: 16),
      AutofillGroup(
          child: Column(children: [
        if (registering) ...[
          TextField(
              key: const Key('email-name'),
              controller: emailName,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: InputDecoration(
                  labelText: tr3('称呼（选填）', 'Атыңыз (міндетті емес)',
                      'Имя (необязательно)',
                      'Name (optional)', ky: 'Аты (милдеттүү эмес)', uz: 'Ism (ixtiyoriy)'))),
          const SizedBox(height: 12),
        ],
        TextField(
            key: const Key('email-address'),
            controller: email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.email],
            decoration:
                InputDecoration(labelText: tr3('邮箱', 'Пошта', 'Почта', 'Email', ky: 'Email', uz: 'Email'))),
        const SizedBox(height: 12),
        TextField(
            key: const Key('email-password'),
            controller: password,
            obscureText: !showPassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autofillHints: [
              registering ? AutofillHints.newPassword : AutofillHints.password
            ],
            inputFormatters: [LengthLimitingTextInputFormatter(72)],
            onSubmitted: (_) => emailSignIn(api),
            decoration: InputDecoration(
                labelText: registering
                    ? tr3('密码（至少 8 位）', 'Құпиясөз (кемінде 8 таңба)',
                        'Пароль (от 8 символов)',
                        'Password (8+ characters)', ky: 'Сырсөз (8+ белги)', uz: 'Parol (8+ belgi)')
                    : tr3('密码', 'Құпиясөз', 'Пароль', 'Password', ky: 'Сырсөз', uz: 'Parol'),
                suffixIcon: IconButton(
                    tooltip: showPassword
                        ? tr3('隐藏密码', 'Жасыру', 'Скрыть пароль', 'Hide password', ky: 'Сырсөздү жашыруу', uz: 'Parolni yashirish')
                        : tr3('显示密码', 'Көрсету', 'Показать пароль', 'Show password', ky: 'Сырсөздү көрсөтүү', uz: 'Parolni koʻrsatish'),
                    icon: Icon(showPassword
                        ? YIcons.eyeOff
                        : YIcons.eye),
                    onPressed: () =>
                        setState(() => showPassword = !showPassword)))),
      ])),
      const SizedBox(height: 16),
      BusyButton(
          key: const Key('email-submit'),
          label: registering
              ? tr3('注册', 'Тіркелу', 'Зарегистрироваться', 'Sign up', ky: 'Катталуу', uz: 'Roʻyxatdan oʻtish')
              : tr3('登录', 'Кіру', 'Войти', 'Sign in', ky: 'Кирүү', uz: 'Kirish'),
          outlined: true,
          onPressed: () => emailSignIn(api)),
      TextButton(
          key: const Key('email-toggle'),
          onPressed: () => setState(() => registering = !registering),
          child: Text(registering
              ? tr3(
                  '已有账号？去登录', 'Аккаунт бар ма? Кіру', 'Уже есть аккаунт? Войти', 'Already have an account? Sign in', ky: 'Аккаунтуңуз барбы? Кириңиз', uz: 'Akkauntingiz bormi? Kiring')
              : tr3('没有账号？用邮箱注册', 'Аккаунт жоқ па? Тіркелу',
                  'Нет аккаунта? Зарегистрироваться',
                  'No account? Sign up', ky: 'Аккаунт жокпу? Катталыңыз', uz: 'Akkaunt yoʻqmi? Roʻyxatdan oʻting'))),
    ];
  }

  // The voice orb would cover the test accounts at the bottom.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => VoiceSlot.hidden.value++);
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => VoiceSlot.hidden.value--);
    name.dispose();
    email.dispose();
    password.dispose();
    emailName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
        title: tr3('登录或注册', 'Кіру не тіркелу', 'Вход или регистрация', 'Sign in or sign up', ky: 'Кирүү же катталуу', uz: 'Kirish yoki roʻyxatdan oʻtish'),
        body: switch (context.read(authRepositoryProvider)) {
          final HttpAuthRepository api => _socialBody(context, api),
          _ => Hint(tr3(
              '暂时无法登录。', 'Қазір кіру мүмкін емес.', 'Вход сейчас недоступен.', "Sign-in isn't available right now.", ky: 'Азыр кирүү мүмкүн эмес.', uz: 'Hozir kirib boʻlmaydi.')),
        });
  }
}
