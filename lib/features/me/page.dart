import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/demand/widgets/demand_card.dart';
import 'package:yusal/features/profile/widgets/profile_card.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/home/widgets/house_card.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/routes.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/service/voice/read_aloud.dart';
import 'package:yusal/features/voice/widgets/voice_overlay.dart'
    show voiceBuiltIn;
import 'package:yusal/features/auth/pages/sign_in_methods.dart';
import 'package:yusal/features/me/pages/feedback.dart';
import 'package:yusal/features/me/pages/kazakh_voice.dart';
import 'package:yusal/features/trust/page.dart';
import 'package:yusal/features/me/state/me.dart';
import 'package:yusal/features/profile/state/profile.dart';
import 'package:yusal/features/auth/widgets/edit_phone.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Fourth tab: who I am, what I published, my professional profile,
/// settings and the account itself, each as its own group.
class MePage extends ConsumerWidget {
  const MePage({super.key});

  static const _langs = languageNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(settingsProvider);
    final choose = ref.read(settingsProvider.notifier);
    final t = YTokens.of(context);
    final themes = [
      (ThemeChoice.auto, tr3('跟随系统', 'Жүйе бойынша', 'Как в системе', 'System', ky: 'Система', uz: 'Tizim')),
      (ThemeChoice.day, tr3('日间', 'Күндіз', 'Светлая', 'Light', ky: 'Жарык', uz: 'Yorugʻ')),
      (ThemeChoice.night, tr3('夜间', 'Түн', 'Тёмная', 'Dark', ky: 'Караңгы', uz: 'Qorongʻi')),
    ];
    return OnChange(builder: (context) {
      final account = context.session.currentAccount;
      return Scaffold(
          body: SafeArea(
              // At the top, not centred: signed out the page is shorter than
              // the screen and sat halfway down it.
              child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      // Built in one go, not lazily: the sections load
                      // their own data, and a lazy list rebuilt (and
                      // reloaded) the ones at the edge of its cache over and
                      // over while their height changed.
                      child: SingleChildScrollView(
                          // The SafeArea already keeps the floating tab
                          // bar's room at the end.
                          padding: const EdgeInsets.fromLTRB(YSpace.gutter,
                              YSpace.md, YSpace.gutter, YSpace.huge),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                    header: true,
                                    child: Text(tr3('我的', 'Менің', 'Профиль', 'Profile', ky: 'Профиль', uz: 'Profil'),
                                        style: display(size: 28))),
                                const SizedBox(height: YSpace.lg),
                                if (account == null)
                                  const _GuestCard()
                                else
                                  _AccountHeader(account: account),
                                if (account != null) ...[
                                  SectionTitle(tr3('我发布的房子',
                                      'Жарияланған үйлерім', 'Мои публикации', 'My posts', ky: 'Менин жарыяларым', uz: 'Mening eʼlonlarim')),
                                  const _MyPosts(),
                                  const SizedBox(height: YSpace.xl),
                                  SettingsGroup(children: [
                                    SettingsRow(
                                        icon: YIcons.heart,
                                        title:
                                            tr3('收藏', 'Таңдаулы', 'Избранное', 'Favourites', ky: 'Тандалгандар', uz: 'Sevimlilar'),
                                        onTap: () => pushPage<void>(context,
                                            (_) => const FavouritesPage())),
                                    SettingsRow(
                                        icon: YIcons.cloud,
                                        title: tr3('设计备份与恢复', 'Сақтық көшірме',
                                            'Резервные копии',
                                            'Backups', ky: 'Резервдик көчүрмөлөр', uz: 'Zaxira nusxalar'),
                                        onTap: () => pushPage<void>(context,
                                            (_) => pageFor(const ToBackup()))),
                                    SettingsRow(
                                        key: const Key('me-phone'),
                                        icon: YIcons.phone,
                                        title: tr3('手机号', 'Телефон нөмірі',
                                            'Номер телефона',
                                            'Phone number', ky: 'Телефон номери', uz: 'Telefon raqami'),
                                        subtitle: tr3(
                                            '只在你在聊天里主动分享时对方才能看到',
                                            'Чатта өзіңіз бөліскенде ғана көрінеді',
                                            'Виден, только когда вы делитесь им в чате',
                                            'Visible only when you share it in chat', ky: 'Чатта бөлүшкөндө гана көрүнөт', uz: 'Faqat chatda ulashganingizda koʻrinadi'),
                                        onTap: () => editPhone(context)),
                                    SettingsRow(
                                        icon: YIcons.block,
                                        title: tr3('隐私与拉黑', 'Құпиялық',
                                            'Приватность и блокировки',
                                            'Privacy and blocking', ky: 'Купуялык жана бөгөттөө', uz: 'Maxfiylik va bloklash'),
                                        onTap: () => pushPage<void>(context,
                                            (_) => const PrivacyPage())),
                                    ...trustRows(context, account),
                                    if (account.can(AdminPerms.read))
                                      SettingsRow(
                                          key: const Key('me-admin'),
                                          icon: Icons
                                              .admin_panel_settings_outlined,
                                          title: tr3(
                                              '管理后台', 'Әкімшілік', 'Админка', 'Admin', ky: 'Админ', uz: 'Admin'),
                                          onTap: () => pushPage<void>(context,
                                              (_) => pageFor(const ToAdmin()))),
                                  ]),
                                  const _ProProfiles(),
                                ],
                                SettingsGroup(
                                    title: tr3('设置', 'Баптаулар', 'Настройки', 'Settings', ky: 'Жөндөөлөр', uz: 'Sozlamalar'),
                                    children: [
                                      SettingsRow(
                                          key: const Key('me-language'),
                                          icon: YIcons.globe,
                                          title: tr3('语言', 'Тіл', 'Язык', 'Language', ky: 'Тил', uz: 'Til'),
                                          value: _langs
                                              .firstWhere(
                                                  (l) => l.$1 == app.lang)
                                              .$2,
                                          onTap: () async {
                                            final v = await pickOne<AppLang>(
                                                context,
                                                tr3('语言', 'Тіл', 'Язык', 'Language', ky: 'Тил', uz: 'Til'),
                                                _langs,
                                                selected: app.lang);
                                            if (v != null) choose.setLang(v);
                                          }),
                                      SettingsRow(
                                          key: const Key('me-theme'),
                                          icon: Icons.brightness_6_outlined,
                                          title: tr3('外观', 'Көрініс', 'Тема', 'Theme', ky: 'Тема', uz: 'Mavzu'),
                                          value: themes
                                              .firstWhere(
                                                  (c) => c.$1 == app.theme)
                                              .$2,
                                          onTap: () async {
                                            final v = await pickOne<
                                                    ThemeChoice>(
                                                context,
                                                tr3('外观', 'Көрініс', 'Тема', 'Theme', ky: 'Тема', uz: 'Mavzu'),
                                                themes,
                                                selected: app.theme);
                                            if (v != null) choose.setTheme(v);
                                          }),
                                      if (voiceBuiltIn)
                                        if (ReadAloud.instance
                                            case final reader?)
                                          ValueListenableBuilder<VoiceModelStatus>(
                                              valueListenable: reader.status,
                                              builder: (context, s, _) => SettingsRow(
                                                  key: const Key(
                                                      'me-kazakh-voice'),
                                                  icon: Icons
                                                      .record_voice_over_outlined,
                                                  title: tr3(
                                                      '哈萨克语朗读',
                                                      'Қазақша дауыс',
                                                      'Казахский голос',
                                                      'Kazakh voice', ky: 'Казакча үн', uz: 'Qozoqcha ovoz'),
                                                  value: kazakhVoiceValue(s),
                                                  onTap: () => pushPage<void>(
                                                      context,
                                                      (_) => KazakhVoicePage(
                                                          reader: reader)))),
                                      SettingsRow(
                                          key: const Key('me-feedback'),
                                          icon: YIcons.chat,
                                          title: tr3('意见反馈', 'Пікір қалдыру',
                                              'Обратная связь',
                                              'Feedback', ky: 'Пикир-сунуш', uz: 'Fikr-mulohaza'),
                                          onTap: () => pushPage<void>(context,
                                              (_) => const FeedbackPage())),
                                    ]),
                                if (account != null)
                                  SettingsGroup(
                                      title: tr3('账号', 'Аккаунт', 'Аккаунт', 'Account', ky: 'Аккаунт', uz: 'Akkaunt'),
                                      children: [
                                        if (context.read(authRepositoryProvider)
                                            case final HttpAuthRepository api)
                                          SettingsRow(
                                              key: const Key(
                                                  'me-sign-in-methods'),
                                              icon: YIcons.lock,
                                              title: tr3(
                                                  '登录方式',
                                                  'Кіру тәсілдері',
                                                  'Способы входа',
                                                  'Sign-in methods', ky: 'Кирүү ыкмалары', uz: 'Kirish usullari'),
                                              onTap: () => pushPage<void>(
                                                  context,
                                                  (_) => SignInMethodsPage(
                                                      api: api))),
                                        SettingsRow(
                                            key: const Key('me-sign-out'),
                                            icon: YIcons.logout,
                                            title: tr3('退出登录', 'Шығу', 'Выйти', 'Sign out', ky: 'Чыгуу', uz: 'Chiqish'),
                                            trailing: const SizedBox.shrink(),
                                            onTap: () async {
                                              if (await confirmDialog(
                                                      context,
                                                      tr3(
                                                          '退出登录？',
                                                          'Шығасыз ба?',
                                                          'Выйти из аккаунта?',
                                                          'Sign out of the account?', ky: 'Аккаунттан чыгасызбы?', uz: 'Akkauntdan chiqasizmi?'),
                                                      body: tr3(
                                                          '本机的设计会保留，再次登录即可继续。',
                                                          'Құрылғыдағы жобалар сақталады, қайта кірсеңіз жалғастырасыз.',
                                                          'Проекты на этом устройстве сохранятся, войдите снова, чтобы продолжить.',
                                                          'Designs on this device are kept; sign in again to continue.', ky: 'Бул түзмөктөгү долбоорлор сакталат; улантуу үчүн кайра кириңиз.', uz: 'Bu qurilmadagi loyihalar saqlanadi; davom etish uchun qayta kiring.'),
                                                      ok: tr3('退出', 'Шығу',
                                                          'Выйти',
                                                          'Sign out', ky: 'Чыгуу', uz: 'Chiqish')) &&
                                                  context.mounted) {
                                                await attempt(
                                                    context,
                                                    () => context
                                                        .read(
                                                            authRepositoryProvider)
                                                        .signOut());
                                              }
                                            }),
                                        SettingsRow(
                                            key: const Key('me-delete-account'),
                                            icon: YIcons.delete,
                                            danger: true,
                                            title: tr3('注销账号', 'Аккаунтты жою',
                                                'Удалить аккаунт',
                                                'Delete the account', ky: 'Аккаунтту өчүрүү', uz: 'Akkauntni oʻchirish'),
                                            onTap: () =>
                                                _deleteAccount(context)),
                                      ]),
                                const SizedBox(height: YSpace.xl),
                                Text(
                                    tr3(
                                        'Yusal 不提供付款担保或资金托管，不承诺施工质量。',
                                        'Yusal төлем кепілдігін бермейді.',
                                        'Yusal не гарантирует оплату и качество работ.',
                                        "Yusal doesn't guarantee payment or the quality of work.", ky: 'Yusal төлөмгө же иштин сапатына кепилдик бербейт.', uz: 'Yusal toʻlov yoki ish sifatini kafolatlamaydi.'),
                                    textAlign: TextAlign.center,
                                    style:
                                        YText.caption.copyWith(color: t.muted)),
                              ]))))));
    });
  }

  static Future<void> _deleteAccount(BuildContext context) async {
    if (await confirmDialog(
            context, tr3('注销账号？', 'Аккаунтты жою?', 'Удалить аккаунт?', 'Delete the account?', ky: 'Аккаунтту өчүрөсүзбү?', uz: 'Akkaunt oʻchirilsinmi?'),
            body: tr3(
                '名片和招募中的需求会下架，云端设计备份会删除。已有合作记录保留，对方看到“已注销用户”。本机设计不受影响。',
                'Профильдер мен тапсырыстар алынады. Жергілікті жобалар қалады.',
                'Профили и заявки будут сняты, облачные копии удалены. Локальные проекты останутся.',
                'Profiles and requests will be taken down and cloud copies deleted. Local designs stay.', ky: 'Профилдер жана суроо-талаптар алынып салынат, булуттагы көчүрмөлөр өчүрүлөт. Түзмөктөгү долбоорлор калат.', uz: 'Profillar va soʻrovlar olib tashlanadi, bulutdagi nusxalar oʻchiriladi. Qurilmadagi loyihalar qoladi.'),
            ok: tr3('注销', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish'),
            danger: true) &&
        context.mounted) {
      await attempt(
          context, () => context.read(authRepositoryProvider).deleteAccount(),
          success: tr3('账号已注销', 'Аккаунт жойылды', 'Аккаунт удалён', 'Account deleted', ky: 'Аккаунт өчүрүлдү', uz: 'Akkaunt oʻchirildi'));
    }
  }
}

/// Signed out: what an account is for, and the way in.
class _GuestCard extends StatelessWidget {
  const _GuestCard();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return YCard(
        shadow: true,
        padding: const EdgeInsets.all(YSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              tr3('登录后可以发布、报名、报价和备份设计', 'Кіріп, жариялаңыз және сақтаңыз',
                  'Войдите, чтобы публиковать, откликаться и сохранять',
                  'Sign in to publish, respond and save', ky: 'Жарыялоо, жооп берүү жана сактоо үчүн кириңиз', uz: 'Eʼlon qilish, javob berish va saqlash uchun kiring'),
              style: YText.heading),
          const SizedBox(height: YSpace.xs),
          Text(
              tr3('浏览和画图不需要账号。', 'Қарау мен сызу үшін аккаунт қажет емес.',
                  'Смотреть и чертить можно без аккаунта.',
                  'You can browse and draw without an account.', ky: 'Аккаунтсуз эле карап чыгып, чийсеңиз болот.', uz: 'Akkauntsiz ham koʻrib, chizishingiz mumkin.'),
              style: YText.label.copyWith(color: t.muted)),
          const SizedBox(height: YSpace.lg),
          FilledButton(
              onPressed: () => requireLogin(context),
              child: Text(tr3('登录或注册', 'Кіру', 'Войти', 'Sign in', ky: 'Кирүү', uz: 'Kirish'))),
        ]));
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Row(children: [
      Avatar(account.displayName, size: 64),
      const SizedBox(width: YSpace.lg),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(account.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: YText.title),
        Text(
            account.phone.isEmpty
                ? tr3('未填写手机号', 'Телефон көрсетілмеген', 'Телефон не указан', 'No phone number', ky: 'Телефон номери жок', uz: 'Telefon raqami yoʻq')
                : maskPhone(account.phone),
            style: YText.label.copyWith(color: t.muted)),
      ])),
      IconButton(
          tooltip: tr3('改称呼', 'Атын өзгерту', 'Изменить имя', 'Change the name', ky: 'Атын өзгөртүү', uz: 'Ismni oʻzgartirish'),
          icon: const Icon(YIcons.edit),
          onPressed: () async {
            final name = await askText(context, tr3('称呼', 'Аты', 'Имя', 'Name', ky: 'Аты', uz: 'Ism'),
                initial: account.displayName, lines: 1);
            if (name != null && context.mounted) {
              await attempt(context,
                  () => context.read(authRepositoryProvider).updateName(name));
            }
          }),
    ]);
  }
}

/// Houses I published, side by side; sized to the card so no gap is left
/// under it.
class _MyPosts extends StatelessWidget {
  const _MyPosts();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<HousePost>>(
        provider: myPostsProvider,
        loading: const Skeleton(height: 150, radius: YRadius.card),
        builder: (context, list) => list.isEmpty
            ? Text(
                tr3(
                    '还没有发布过设计。在“我的房子”里打开设计的菜单，选“发布作品”。',
                    'Әлі жарияланбаған. «Үйлерім» бөлімінде жоба мәзірінен «Жобаны жариялау» таңдаңыз.',
                    'Пока ничего не опубликовано. В «Моих домах» откройте меню проекта и выберите «Опубликовать».',
                    "Nothing published yet. In “My houses”, open a design's menu and choose “Publish”.", ky: 'Азырынча эч нерсе жарыяланган жок. «Менин үйлөрүм» бөлүмүндө долбоордун менюсун ачып, «Жарыялоону» тандаңыз.', uz: 'Hozircha hech narsa eʼlon qilinmagan. “Mening uylarim” boʻlimida loyiha menyusini ochib, “Eʼlon qilish” ni tanlang.'),
                style: YText.label.copyWith(color: t.muted))
            // A row that is as tall as its cards: a person has a handful
            // of published houses, so nothing needs to be lazy, and no
            // height has to be guessed for every language and text size.
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, post) in list.indexed)
                        Padding(
                            padding:
                                EdgeInsets.only(left: i == 0 ? 0 : YSpace.md),
                            child: SizedBox(
                                // Wide enough for a city, area, floors and rooms on one line.
                                width: 260,
                                child: HouseCard(
                                    compact: true,
                                    post: post,
                                    onTap: () => pushPage<void>(
                                        context,
                                        (_) => pageFor(
                                            ToPost(post.id, preview: post)))))),
                    ])));
  }
}

/// My professional profiles, or the three ways to make the first one.
class _ProProfiles extends StatelessWidget {
  const _ProProfiles();
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Live<List<ServiceProfile>>(
        provider: myProfilesProvider,
        loading: const SizedBox.shrink(),
        builder: (context, list) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (list.isNotEmpty) ...[
                SectionTitle(tr3('入驻接活', 'Кәсіби профиль', 'Профиль мастера', 'Pro profile', ky: 'Адистин профили', uz: 'Mutaxassis profili')),
                for (final p in list)
                  Padding(
                      padding: const EdgeInsets.only(bottom: YSpace.md),
                      child: ProfileCard(
                          profile: p,
                          onTap: () => pushPage<void>(
                              context, (_) => pageFor(ToProfile(p.id))))),
                SettingsGroup(children: [
                  SettingsRow(
                      key: const Key('me-demand-alert'),
                      icon: Icons.notifications_active_outlined,
                      title: tr3('新需求提醒', 'Жаңа тапсырыстар', 'Новые заявки', 'New requests', ky: 'Жаңы суроо-талаптар', uz: 'Yangi soʻrovlar'),
                      subtitle: tr3(
                          '按地区、工种订阅，有新需求时提醒你',
                          'Аймақ пен мамандық бойынша',
                          'По региону и специальности',
                          'By region and trade', ky: 'Аймак жана кесип боюнча', uz: 'Hudud va kasb boʻyicha'),
                      onTap: () => pushPage<void>(
                          context, (_) => const DemandAlertPage())),
                  for (final p in list)
                    if (!p.verified)
                      SettingsRow(
                          key: Key('me-verify-${p.id}'),
                          icon: YIcons.verified,
                          title: tr3('实名核验：${p.name}', 'Тексеру: ${p.name}',
                              'Проверка: ${p.name}',
                              'Verification: ${p.name}', ky: 'Текшерүү: ${p.name}', uz: 'Tekshiruv: ${p.name}'),
                          subtitle: tr3(
                              '核验手机号和施工现场，名片显示“已核验”',
                              'Профильде «тексерілген» белгісі',
                              'Значок «проверен» в профиле',
                              '“Verified” badge on the profile', ky: 'Профилдеги «Текшерилген» белгиси', uz: 'Profildagi “Tekshirilgan” belgisi'),
                          onTap: () => pushPage<void>(
                              context, (_) => VerificationPage(profile: p))),
                ]),
                const SizedBox(height: YSpace.sm),
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                        onPressed: () => pushPage<void>(
                            context, (_) => pageFor(const ToProfileEdit())),
                        icon: const Icon(YIcons.add, size: 20),
                        label: Text(
                            tr3('再建一个名片', 'Тағы профиль', 'Ещё профиль', 'Another profile', ky: 'Башка профиль', uz: 'Boshqa profil')))),
              ] else ...[
                SettingsGroup(
                    title: tr3('入驻接活', 'Кәсіби профиль', 'Профиль мастера', 'Pro profile', ky: 'Адистин профили', uz: 'Mutaxassis profili'),
                    children: [
                      for (final r in ProRole.values)
                        SettingsRow(
                            key: Key('me-join-${r.name}'),
                            icon: switch (r) {
                              ProRole.worker => YIcons.tools,
                              ProRole.contractor => YIcons.people,
                              ProRole.engineer => YIcons.design,
                            },
                            title: proRoleName(r),
                            onTap: () => pushPage<void>(context,
                                (_) => pageFor(ToProfileEdit(role: r)))),
                    ]),
                Padding(
                    padding: const EdgeInsets.fromLTRB(
                        YSpace.xs, YSpace.sm, YSpace.xs, 0),
                    child: Text(
                        tr3(
                            '工人、包工头或工程师：建一张名片，房主就能找到你。',
                            'Жұмысшы, мердігер не инженер: профиль жасаңыз.',
                            'Рабочий, прораб или инженер: создайте профиль, и вас найдут.',
                            'Worker, foreman or engineer: create a profile and people will find you.', ky: 'Жумушчу, прораб же инженер: профиль түзүңүз, адамдар сизди табат.', uz: 'Ishchi, prorab yoki muhandis: profil yarating, odamlar sizni topadi.'),
                        style: YText.caption.copyWith(color: t.muted))),
              ],
            ]));
  }
}

String maskPhone(String phone) => phone.length < 8
    ? phone
    : '${phone.substring(0, phone.length - 7)}***${phone.substring(phone.length - 4)}';

class MyApplicationsPage extends StatelessWidget {
  const MyApplicationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    watchLang(context);
    final t = YTokens.of(context);
    return PageScaffold(
        title: tr3('我的报名与报价', 'Өтінімдерім', 'Мои отклики', 'My responses', ky: 'Менин жоопторум', uz: 'Mening javoblarim'),
        body: Live<List<(Application, Demand?)>>(
            provider: myApplicationsProvider,
            builder: (context, list) => Column(children: [
                  if (list.isEmpty)
                    EmptyState(
                        icon: YIcons.contract,
                        title:
                            tr3('还没有报名或报价', 'Өтінім жоқ', 'Откликов пока нет', 'No responses yet', ky: 'Азырынча жооп жок', uz: 'Hozircha javob yoʻq')),
                  for (final (a, d) in list)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: YCard(
                            onTap: d == null
                                ? null
                                : () => pushPage<void>(context,
                                    (_) => pageFor(ToApply(d, existing: a))),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        d?.current.title ??
                                            tr3('需求已不可见', 'Қолжетімсіз',
                                                'Недоступно',
                                                'Unavailable', ky: 'Жеткиликсиз', uz: 'Mavjud emas'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        '${applicationStatusName(a.status)}${a.needsReconfirm ? ' · ${tr3('需求已修改，待重新确认', 'Тапсырыс өзгерді', 'Заявка изменилась', 'The request changed', ky: 'Суроо-талап өзгөрдү', uz: 'Soʻrov oʻzgardi')}' : ''}',
                                        style: TextStyle(
                                            color: a.needsReconfirm
                                                ? t.warn
                                                : t.muted,
                                            fontSize: YFont.small)),
                                  ])),
                              if (a.status ==
                                      ApplicationStatus.pendingConfirm ||
                                  a.status == ApplicationStatus.cooperating)
                                TextButton(
                                    onPressed: () async {
                                      final coops = await context
                                          .read(cooperationRepositoryProvider)
                                          .cooperationsFor(a.demandId);
                                      final c = coops
                                          .where((c) => c.applicationId == a.id)
                                          .lastOrNull;
                                      if (c != null && context.mounted) {
                                        pushPage<void>(
                                            context,
                                            (_) =>
                                                pageFor(ToCooperation(c.id)));
                                      }
                                    },
                                    child: Text(a.status ==
                                            ApplicationStatus.pendingConfirm
                                        ? tr3('去确认', 'Растау', 'Подтвердить', 'Confirm', ky: 'Ырастоо', uz: 'Tasdiqlash')
                                        : tr3('合作', 'Келісім',
                                            'Сотрудничество',
                                            'Cooperation', ky: 'Кызматташуу', uz: 'Hamkorlik'))),
                            ]))),
                ])));
  }
}

/// Everything I saved, one section per kind: houses I hearted (home feed
/// or a house page), workers and teams, and demands. Favourites hold
/// profile and demand ids together, so each id is looked up as either.
class FavouritesPage extends StatelessWidget {
  const FavouritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return PageScaffold(
        title: tr3('收藏', 'Таңдаулы', 'Избранное', 'Favourites', ky: 'Тандалгандар', uz: 'Sevimlilar'),
        body: Live<(List<HousePost>, List<ServiceProfile>, List<Demand>)>(
            provider: favouritesProvider,
            builder: (context, data) {
              final (houses, profiles, demands) = data;
              if (houses.isEmpty && profiles.isEmpty && demands.isEmpty) {
                return EmptyState(
                    icon: YIcons.heart,
                    title: tr3('还没有收藏', 'Бос', 'Пусто', 'Empty', ky: 'Бош', uz: 'Boʻsh'),
                    body: tr3(
                        '在房子、师傅名片或需求上点 ♡，就会出现在这里',
                        'Үйдегі, шебердегі не тапсырыстағы ♡ белгісін басыңыз',
                        'Нажмите ♡ на доме, мастере или заявке, и они появятся здесь',
                        'Tap ♡ on a house, pro or request and it shows up here', ky: 'Үйдөгү, адистеги же суроо-талаптагы ♡ белгисин бассаңыз, ал ушул жерде көрүнөт', uz: 'Uy, mutaxassis yoki soʻrovdagi ♡ ni bossangiz, u shu yerda koʻrinadi'));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (houses.isNotEmpty) ...[
                      SectionTitle(tr3('房子', 'Үйлер', 'Дома', 'Houses', ky: 'Үйлөр', uz: 'Uylar')),
                      for (final p in houses)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: HouseCard(
                                key: Key('fav-house-${p.id}'),
                                compact: true,
                                post: p,
                                liked: true,
                                onTap: () => pushPage<void>(context,
                                    (_) => pageFor(ToPost(p.id, preview: p))))),
                    ],
                    if (profiles.isNotEmpty) ...[
                      SectionTitle(
                          tr3('师傅和施工队', 'Шеберлер', 'Мастера и бригады', 'Pros and crews', ky: 'Адистер жана бригадалар', uz: 'Mutaxassislar va brigadalar')),
                      for (final p in profiles)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ProfileCard(
                                key: Key('fav-profile-${p.id}'),
                                profile: p,
                                onTap: () => pushPage<void>(
                                    context, (_) => pageFor(ToProfile(p.id))))),
                    ],
                    if (demands.isNotEmpty) ...[
                      SectionTitle(tr3('需求', 'Тапсырыстар', 'Заявки', 'Requests', ky: 'Суроо-талаптар', uz: 'Soʻrovlar')),
                      for (final d in demands)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DemandCard(
                                key: Key('fav-demand-${d.id}'),
                                compact: true,
                                demand: d,
                                onTap: () => pushPage<void>(
                                    context, (_) => pageFor(ToDemand(d.id))))),
                    ],
                  ]);
            }));
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return PageScaffold(
        title: tr3('隐私与拉黑', 'Құпиялық', 'Приватность', 'Privacy', ky: 'Купуялык', uz: 'Maxfiylik'),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Hint(tr3('手机号默认对所有人隐藏。你可以在聊天中主动向某个人展示，或在名片上选择公开。',
              'Телефон әдепкіде жасырын.', 'Номер скрыт по умолчанию.', 'Your number is hidden by default.', ky: 'Номериңиз демейки боюнча жашырылган.', uz: 'Raqamingiz standart boʻyicha yashirilgan.')),
          SectionTitle(tr3('已拉黑', 'Бұғатталғандар', 'Заблокированные', 'Blocked', ky: 'Бөгөттөлгөндөр', uz: 'Bloklanganlar')),
          Live<List<Account?>>(
              provider: blockedAccountsProvider,
              loading: const SkeletonList(count: 2, avatar: true),
              builder: (context, list) => Column(children: [
                    if (list.isEmpty)
                      Text(tr3('没有拉黑任何人', 'Ешкім жоқ', 'Никого нет', 'No one', ky: 'Эч ким', uz: 'Hech kim')),
                    for (final a in list.whereType<Account>())
                      ListTile(
                          leading: Avatar(a.displayName, size: 36),
                          title: Text(deletedName(a)),
                          trailing: TextButton(
                              onPressed: () => attempt(
                                  context,
                                  () => context
                                      .read(chatRepositoryProvider)
                                      .unblock(a.id)),
                              child: Text(
                                  tr3('取消拉黑', 'Шығару', 'Разблокировать', 'Unblock', ky: 'Бөгөттөн чыгаруу', uz: 'Blokdan chiqarish')))),
                  ])),
        ]));
  }
}
