import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../apply/apply_page.dart';
import '../backup/backup_page.dart';
import '../cards.dart';
import '../components.dart';
import '../demand/demand_detail_page.dart';
import '../home/house_card.dart';
import '../home/post_page.dart';
import '../l10n.dart';
import '../profile/profile_edit_page.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'admin_page.dart';
import 'dev_tools_page.dart';

/// Fourth tab: who I am, what I published, my professional profile,
/// settings and the account itself, each as its own group.
class MePage extends StatelessWidget {
  const MePage({super.key});

  static const _langs = [
    (AppLang.kk, 'Қазақша'),
    (AppLang.ru, 'Русский'),
    (AppLang.zh, '中文'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final t = YTokens.of(context);
    final themes = [
      (ThemeChoice.auto, tr3('跟随系统', 'Жүйе бойынша', 'Как в системе')),
      (ThemeChoice.day, tr3('日间', 'Күндіз', 'Светлая')),
      (ThemeChoice.night, tr3('夜间', 'Түн', 'Тёмная')),
    ];
    return OnChange(builder: (context) {
      final account = context.repos.currentAccount;
      return Scaffold(
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      // Built in one go, not lazily: the sections load
                      // their own data, and a lazy list rebuilt (and
                      // reloaded) the ones at the edge of its cache over and
                      // over while their height changed.
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(YSpace.gutter,
                              YSpace.md, YSpace.gutter, YSpace.huge),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Semantics(
                                header: true,
                                child: Text(tr3('我的', 'Менің', 'Профиль'),
                                    style: display(size: 28))),
                            const SizedBox(height: YSpace.lg),
                            if (account == null)
                              const _GuestCard()
                            else
                              _AccountHeader(account: account),
                            if (account != null) ...[
                              SectionTitle(
                                  tr3('我发布的房子', 'Жарияланған үйлерім',
                                      'Мои публикации')),
                              const _MyPosts(),
                              const SizedBox(height: YSpace.xl),
                              SettingsGroup(children: [
                                SettingsRow(
                                    icon: Icons.favorite_border,
                                    title: tr3('收藏', 'Таңдаулы', 'Избранное'),
                                    onTap: () => pushPage<void>(context,
                                        (_) => const FavouritesPage())),
                                SettingsRow(
                                    icon: Icons.cloud_outlined,
                                    title: tr3(
                                        '设计备份与恢复',
                                        'Сақтық көшірме',
                                        context.isDemo
                                            ? 'Демо-копии'
                                            : 'Резервные копии'),
                                    onTap: () => pushPage<void>(
                                        context, (_) => const BackupPage())),
                                if (!context.isDemo)
                                  SettingsRow(
                                      key: const Key('me-phone'),
                                      icon: Icons.phone_outlined,
                                      title: tr3('手机号', 'Телефон нөмірі',
                                          'Номер телефона'),
                                      subtitle: tr3(
                                          '只在你在聊天里主动分享时对方才能看到',
                                          'Чатта өзіңіз бөліскенде ғана көрінеді',
                                          'Виден, только когда вы делитесь им в чате'),
                                      onTap: () => editPhone(context)),
                                SettingsRow(
                                    icon: Icons.block,
                                    title: tr3('隐私与拉黑', 'Құпиялық',
                                        'Приватность и блокировки'),
                                    onTap: () => pushPage<void>(
                                        context, (_) => const PrivacyPage())),
                                if (account.isAdmin)
                                  SettingsRow(
                                      icon:
                                          Icons.admin_panel_settings_outlined,
                                      title:
                                          tr3('审核后台', 'Модерация', 'Модерация'),
                                      onTap: () => pushPage<void>(context,
                                          (_) => const AdminPage())),
                              ]),
                              const _ProProfiles(),
                            ],
                            SettingsGroup(
                                title: tr3('设置', 'Баптаулар', 'Настройки'),
                                children: [
                                  SettingsRow(
                                      key: const Key('me-language'),
                                      icon: Icons.language,
                                      title: tr3('语言', 'Тіл', 'Язык'),
                                      value: _langs
                                          .firstWhere((l) => l.$1 == app.lang)
                                          .$2,
                                      onTap: () async {
                                        final v = await pickOne<AppLang>(
                                            context,
                                            tr3('语言', 'Тіл', 'Язык'),
                                            _langs,
                                            selected: app.lang);
                                        if (v != null) app.setLang(v);
                                      }),
                                  SettingsRow(
                                      key: const Key('me-theme'),
                                      icon: Icons.brightness_6_outlined,
                                      title: tr3('外观', 'Көрініс', 'Тема'),
                                      value: themes
                                          .firstWhere(
                                              (c) => c.$1 == app.theme)
                                          .$2,
                                      onTap: () async {
                                        final v = await pickOne<ThemeChoice>(
                                            context,
                                            tr3('外观', 'Көрініс', 'Тема'),
                                            themes,
                                            selected: app.theme);
                                        if (v != null) app.setTheme(v);
                                      }),
                                  if (context.mock != null)
                                    SettingsRow(
                                        icon: Icons.science_outlined,
                                        title: tr3(
                                            '开发者工具（模拟数据）',
                                            'Әзірлеуші құралдары',
                                            'Инструменты разработчика'),
                                        subtitle: tr3(
                                            '切换测试账号、快进时间、模拟断网',
                                            'Сынақ аккаунты, уақыт',
                                            'Тестовые аккаунты, время, сеть'),
                                        onTap: () => pushPage<void>(context,
                                            (_) => const DevToolsPage())),
                                ]),
                            if (account != null)
                              SettingsGroup(
                                  title: tr3('账号', 'Аккаунт', 'Аккаунт'),
                                  children: [
                                    SettingsRow(
                                        key: const Key('me-sign-out'),
                                        icon: Icons.logout,
                                        title: tr3('退出登录', 'Шығу', 'Выйти'),
                                        trailing: const SizedBox.shrink(),
                                        onTap: () => attempt(context,
                                            () => context.repos.signOut())),
                                    SettingsRow(
                                        key: const Key('me-delete-account'),
                                        icon: Icons.delete_outline,
                                        danger: true,
                                        title: tr3('注销账号', 'Аккаунтты жою',
                                            'Удалить аккаунт'),
                                        onTap: () => _deleteAccount(context)),
                                  ]),
                            const SizedBox(height: YSpace.xl),
                            Text(
                                tr3(
                                    'Yusal 不提供付款担保或资金托管，不承诺施工质量。',
                                    'Yusal төлем кепілдігін бермейді.',
                                    'Yusal не гарантирует оплату и качество работ.'),
                                textAlign: TextAlign.center,
                                style:
                                    YText.caption.copyWith(color: t.muted)),
                          ]))))));
    });
  }

  static Future<void> _deleteAccount(BuildContext context) async {
    if (await confirmDialog(
            context, tr3('注销账号？', 'Аккаунтты жою?', 'Удалить аккаунт?'),
            body: tr3(
                '名片和招募中的需求会下架，云端设计备份会删除。已有合作记录保留，对方看到“已注销用户”。本机设计不受影响。',
                'Профильдер мен тапсырыстар алынады. Жергілікті жобалар қалады.',
                'Профили и заявки будут сняты, облачные копии удалены. Локальные проекты останутся.'),
            ok: tr3('注销', 'Жою', 'Удалить'),
            danger: true) &&
        context.mounted)
      await attempt(context, () => context.repos.deleteAccount(),
          success: tr3('账号已注销', 'Аккаунт жойылды', 'Аккаунт удалён'));
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
                  'Войдите, чтобы публиковать, откликаться и сохранять'),
              style: YText.heading),
          const SizedBox(height: YSpace.xs),
          Text(
              tr3('浏览和画图不需要账号。', 'Қарау мен сызу үшін аккаунт қажет емес.',
                  'Смотреть и чертить можно без аккаунта.'),
              style: YText.label.copyWith(color: t.muted)),
          const SizedBox(height: YSpace.lg),
          FilledButton(
              onPressed: () => requireLogin(context),
              child: Text(tr3('登录或注册', 'Кіру', 'Войти'))),
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
            context.isDemo
                ? '${maskPhone(account.phone)} · ${tr3('演示账号', 'Демо аккаунт', 'Демо-аккаунт')}'
                : account.phone.isEmpty
                    ? tr3('未填写手机号', 'Телефон көрсетілмеген',
                        'Телефон не указан')
                    : maskPhone(account.phone),
            style: YText.label.copyWith(color: t.muted)),
      ])),
      IconButton(
          tooltip: tr3('改称呼', 'Атын өзгерту', 'Изменить имя'),
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final name = await askText(context, tr3('称呼', 'Аты', 'Имя'),
                initial: account.displayName, lines: 1);
            if (name != null && context.mounted)
              await attempt(context, () => context.repos.updateName(name));
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
        load: (r) => r.myPosts(),
        loading: const Skeleton(height: 150, radius: YRadius.card),
        builder: (context, list) => list.isEmpty
            ? Text(
                tr3(
                    '还没有发布过设计。在“我的房子”里打开设计的菜单，选“发布作品”。',
                    'Әлі жарияланбаған. «Үйлерім» бөлімінде жоба мәзірінен «Жобаны жариялау» таңдаңыз.',
                    'Пока ничего не опубликовано. В «Моих домах» откройте меню проекта и выберите «Опубликовать».'),
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
                            padding: EdgeInsets.only(
                                left: i == 0 ? 0 : YSpace.md),
                            child: SizedBox(
                                width: 220,
                                child: HouseCard(
                                    compact: true,
                                    post: post,
                                    onTap: () => pushPage<void>(
                                        context,
                                        (_) => PostPage(
                                            postId: post.id,
                                            preview: post))))),
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
        load: (r) => r.myProfiles(),
        loading: const SizedBox.shrink(),
        builder: (context, list) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (list.isNotEmpty) ...[
                    SectionTitle(
                        tr3('入驻接活', 'Кәсіби профиль', 'Профиль мастера')),
                    for (final p in list)
                      Padding(
                          padding: const EdgeInsets.only(bottom: YSpace.md),
                          child: ProfileCard(
                              profile: p,
                              onTap: () => pushPage<void>(context,
                                  (_) => ProfilePage(profileId: p.id)))),
                    Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                            onPressed: () => pushPage<void>(
                                context, (_) => const ProfileEditPage()),
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(tr3(
                                '再建一个名片', 'Тағы профиль', 'Ещё профиль')))),
                  ] else ...[
                    SettingsGroup(
                        title: tr3('入驻接活', 'Кәсіби профиль', 'Профиль мастера'),
                        children: [
                          for (final r in ProRole.values)
                            SettingsRow(
                                key: Key('me-join-${r.name}'),
                                icon: switch (r) {
                                  ProRole.worker => Icons.handyman_outlined,
                                  ProRole.contractor => Icons.groups_outlined,
                                  ProRole.engineer =>
                                    Icons.architecture_outlined,
                                },
                                title: proRoleName(r),
                                onTap: () => pushPage<void>(context,
                                    (_) => ProfileEditPage(role: r))),
                        ]),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(
                            YSpace.xs, YSpace.sm, YSpace.xs, 0),
                        child: Text(
                            tr3(
                                '工人、包工头或工程师：建一张名片，房主就能找到你。',
                                'Жұмысшы, мердігер не инженер: профиль жасаңыз.',
                                'Рабочий, прораб или инженер: создайте профиль, и вас найдут.'),
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
    AppScope.watch(context);
    final t = YTokens.of(context);
    return PageScaffold(
        title: tr3('我的报名与报价', 'Өтінімдерім', 'Мои отклики'),
        body: Live<List<(Application, Demand?)>>(
            load: (r) async => [
                  for (final a in await r.myApplications())
                    (a, await r.demand(a.demandId))
                ],
            builder: (context, list) => Column(children: [
                  if (list.isEmpty)
                    EmptyState(
                        icon: Icons.assignment_outlined,
                        title:
                            tr3('还没有报名或报价', 'Өтінім жоқ', 'Откликов пока нет')),
                  for (final (a, d) in list)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: YCard(
                            onTap: d == null
                                ? null
                                : () => pushPage<void>(context,
                                    (_) => ApplyPage(demand: d, existing: a)),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        d?.current.title ??
                                            tr3('需求已不可见', 'Қолжетімсіз',
                                                'Недоступно'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        '${applicationStatusName(a.status)}${a.needsReconfirm ? ' · ${tr3('需求已修改，待重新确认', 'Тапсырыс өзгерді', 'Заявка изменилась')}' : ''}',
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
                                      final coops = await context.repos
                                          .cooperationsFor(a.demandId);
                                      final c = coops
                                          .where((c) => c.applicationId == a.id)
                                          .lastOrNull;
                                      if (c != null && context.mounted)
                                        openCooperation(context, c.id);
                                    },
                                    child: Text(a.status ==
                                            ApplicationStatus.pendingConfirm
                                        ? tr3('去确认', 'Растау', 'Подтвердить')
                                        : tr3('合作', 'Келісім',
                                            'Сотрудничество'))),
                            ]))),
                ])));
  }
}

/// What I saved: the houses I hearted on the home feed or a house page,
/// and the demands I starred on Discover, one section each.
class FavouritesPage extends StatelessWidget {
  const FavouritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return PageScaffold(
        title: tr3('收藏', 'Таңдаулы', 'Избранное'),
        body: Live<(List<HousePost>, List<Demand>)>(
            load: (r) async => (
                  [
                    for (final id in await r.likedPosts())
                      if (await r.post(id) case final p?) p
                  ],
                  [
                    for (final id in await r.favourites())
                      if (await r.demand(id) case final d?) d
                  ]
                ),
            builder: (context, data) {
              final (houses, demands) = data;
              if (houses.isEmpty && demands.isEmpty) {
                return EmptyState(
                    icon: Icons.favorite_border,
                    title: tr3('还没有收藏', 'Бос', 'Пусто'),
                    body: tr3(
                        '在首页的房子上点 ♡，或在发现里收藏需求，就会出现在这里',
                        'Үйдегі ♡ белгісін басыңыз, ол осында шығады',
                        'Нажмите ♡ на доме или заявке, и она появится здесь'));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (houses.isNotEmpty) ...[
                      SectionTitle(tr3('房子', 'Үйлер', 'Дома')),
                      for (final p in houses)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: HouseCard(
                                key: Key('fav-house-${p.id}'),
                                compact: true,
                                post: p,
                                liked: true,
                                onTap: () => pushPage<void>(context,
                                    (_) => PostPage(postId: p.id, preview: p)))),
                    ],
                    if (demands.isNotEmpty) ...[
                      SectionTitle(tr3('需求', 'Тапсырыстар', 'Заявки')),
                      for (final d in demands)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DemandCard(
                                compact: true,
                                demand: d,
                                onTap: () => pushPage<void>(context,
                                    (_) => DemandDetailPage(demandId: d.id)))),
                    ],
                  ]);
            }));
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return PageScaffold(
        title: tr3('隐私与拉黑', 'Құпиялық', 'Приватность'),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Hint(tr3('手机号默认对所有人隐藏。你可以在聊天中主动向某个人展示，或在名片上选择公开。',
              'Телефон әдепкіде жасырын.', 'Номер скрыт по умолчанию.')),
          SectionTitle(tr3('已拉黑', 'Бұғатталғандар', 'Заблокированные')),
          Live<List<Account?>>(
              load: (r) async => Future.wait(
                  [for (final id in await r.blocked()) r.account(id)]),
              loading: const SkeletonList(count: 2, avatar: true),
              builder: (context, list) => Column(children: [
                    if (list.isEmpty)
                      Text(tr3('没有拉黑任何人', 'Ешкім жоқ', 'Никого нет')),
                    for (final a in list.whereType<Account>())
                      ListTile(
                          leading: Avatar(a.displayName, size: 36),
                          title: Text(deletedName(a)),
                          trailing: TextButton(
                              onPressed: () => attempt(
                                  context, () => context.repos.unblock(a.id)),
                              child: Text(
                                  tr3('取消拉黑', 'Шығару', 'Разблокировать')))),
                  ])),
        ]));
  }
}
