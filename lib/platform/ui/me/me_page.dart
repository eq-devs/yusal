import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../apply/apply_page.dart';
import '../backup/backup_page.dart';
import '../cards.dart';
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

/// Third tab: account, profiles, my sign-ups and quotes, favourites,
/// backups, settings, privacy and developer tools.
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final t = YTokens.of(context);
    return OnChange(builder: (context) {
      final account = context.repos.currentAccount;
      Widget tile(IconData icon, String title, VoidCallback onTap,
              {String? sub}) =>
          ListTile(
              leading: Icon(icon),
              title: Text(title, style: const TextStyle(fontSize: 16)),
              subtitle: sub == null ? null : Text(sub),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap);
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
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(tr3('我的', 'Менің', 'Профиль'),
                                      style: display(size: 28))),
                            ]),
                            const SizedBox(height: 16),
                            if (account == null)
                              YCard(
                                  shadow: true,
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            tr3(
                                                '登录后可以发布、报名、报价和备份设计',
                                                'Кіріп, жариялаңыз және сақтаңыз',
                                                'Войдите, чтобы публиковать, откликаться и сохранять'),
                                            style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 14),
                                        FilledButton(
                                            onPressed: () =>
                                                requireLogin(context),
                                            child: Text(
                                                tr3('登录或注册', 'Кіру', 'Войти'))),
                                      ]))
                            else
                              Row(children: [
                                Avatar(account.displayName, size: 64),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(account.displayName,
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700)),
                                      Text(
                                          context.isDemo
                                              ? '${maskPhone(account.phone)} · ${tr3('演示账号', 'Демо аккаунт', 'Демо-аккаунт')}'
                                              : account.phone.isEmpty
                                                  ? tr3('未填写手机号', 'Телефон көрсетілмеген', 'Телефон не указан')
                                                  : maskPhone(account.phone),
                                          style: TextStyle(color: t.muted)),
                                    ])),
                                IconButton(
                                    tooltip: tr3(
                                        '改称呼', 'Атын өзгерту', 'Изменить имя'),
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final name = await askText(
                                          context, tr3('称呼', 'Аты', 'Имя'),
                                          initial: account.displayName,
                                          lines: 1);
                                      if (name != null && context.mounted)
                                        await attempt(
                                            context,
                                            () =>
                                                context.repos.updateName(name));
                                    }),
                              ]),
                            if (account != null) ...[
                              SectionTitle(
                                  tr3('我发布的房子', 'Үйлерім', 'Мои дома')),
                              Live<List<HousePost>>(
                                  load: (r) => r.myPosts(),
                                  builder: (context, list) => list.isEmpty
                                      ? Text(
                                          tr3(
                                              '还没有发布过设计。在“设计”里点分享图标即可发布到首页。',
                                              'Әлі жарияланбаған.',
                                              'Пока ничего не опубликовано.'),
                                          style: TextStyle(color: t.muted))
                                      : SizedBox(
                                          height: 300,
                                          child: ListView.separated(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: list.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(width: 12),
                                              itemBuilder: (context, i) => SizedBox(
                                                  width: 220,
                                                  child: HouseCard(
                                                      compact: true,
                                                      post: list[i],
                                                      onTap: () => pushPage<void>(context, (_) => PostPage(postId: list[i].id, preview: list[i]))))))),
                              SectionTitle(tr3(
                                  '入驻接活', 'Кәсіби профиль', 'Профиль мастера')),
                              Text(
                                  tr3(
                                      '工人、包工头或工程师：建一张名片，房主就能找到你。',
                                      'Жұмысшы, мердігер не инженер: профиль жасаңыз.',
                                      'Рабочий, прораб или инженер: создайте профиль, и вас найдут.'),
                                  style:
                                      TextStyle(color: t.muted, fontSize: 13)),
                              const SizedBox(height: 8),
                              Live<List<ServiceProfile>>(
                                  load: (r) => r.myProfiles(),
                                  builder: (context, list) => Column(children: [
                                        for (final p in list)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: ProfileCard(
                                                  profile: p,
                                                  onTap: () => pushPage<void>(
                                                      context,
                                                      (_) => ProfilePage(
                                                          profileId: p.id)))),
                                        if (list.isEmpty)
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                for (final r in ProRole.values)
                                                  OutlinedButton.icon(
                                                      onPressed: () => pushPage<
                                                              void>(
                                                          context,
                                                          (_) =>
                                                              ProfileEditPage(
                                                                  role: r)),
                                                      icon: Icon(switch (r) {
                                                        ProRole.worker => Icons
                                                            .handyman_outlined,
                                                        ProRole.contractor =>
                                                          Icons.groups_outlined,
                                                        ProRole.engineer => Icons
                                                            .architecture_outlined,
                                                      }),
                                                      label:
                                                          Text(proRoleName(r))),
                                              ])
                                        else
                                          OutlinedButton.icon(
                                              onPressed: () => pushPage<void>(
                                                  context,
                                                  (_) =>
                                                      const ProfileEditPage()),
                                              icon: const Icon(Icons.add),
                                              label: Text(tr3(
                                                  '再建一个名片',
                                                  'Тағы профиль',
                                                  'Ещё профиль'))),
                                      ])),
                              const SizedBox(height: 12),
                              tile(
                                  Icons.favorite_border,
                                  tr3('收藏', 'Таңдаулы', 'Избранное'),
                                  () => pushPage<void>(
                                      context, (_) => const FavouritesPage())),
                              tile(
                                  Icons.cloud_outlined,
                                  tr3(
                                      '设计备份与恢复',
                                      'Сақтық көшірме',
                                      context.isDemo
                                          ? 'Демо-копии'
                                          : 'Резервные копии'),
                                  () => pushPage<void>(
                                      context, (_) => const BackupPage())),
                              if (!context.isDemo)
                                tile(
                                    Icons.phone_outlined,
                                    tr3('手机号', 'Телефон нөмірі',
                                        'Номер телефона'),
                                    () => editPhone(context),
                                    sub: tr3(
                                        '只在你在聊天里主动分享时对方才能看到',
                                        'Чатта өзіңіз бөліскенде ғана көрінеді',
                                        'Виден, только когда вы делитесь им в чате')),
                              tile(
                                  Icons.block,
                                  tr3('隐私与拉黑', 'Құпиялық',
                                      'Приватность и блокировки'),
                                  () => pushPage<void>(
                                      context, (_) => const PrivacyPage())),
                              if (account.isAdmin)
                                tile(
                                    Icons.admin_panel_settings_outlined,
                                    tr3('审核后台', 'Модерация', 'Модерация'),
                                    () => pushPage<void>(
                                        context, (_) => const AdminPage())),
                            ],
                            SectionTitle(tr3('设置', 'Баптаулар', 'Настройки')),
                            Text(tr3('语言', 'Тіл', 'Язык'),
                                style: TextStyle(color: t.muted)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              for (final (l, label) in const [
                                (AppLang.kk, 'Қазақша'),
                                (AppLang.ru, 'Русский'),
                                (AppLang.zh, '中文'),
                              ])
                                FilterPill(
                                    label: label,
                                    selected: app.lang == l,
                                    onTap: () => app.setLang(l)),
                            ]),
                            const SizedBox(height: 14),
                            Text(tr3('外观', 'Көрініс', 'Тема'),
                                style: TextStyle(color: t.muted)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              for (final (c, label) in [
                                (ThemeChoice.auto, tr3('自动', 'Авто', 'Авто')),
                                (
                                  ThemeChoice.day,
                                  tr3('日间', 'Күндіз', 'Светлая')
                                ),
                                (ThemeChoice.night, tr3('夜间', 'Түн', 'Тёмная')),
                              ])
                                FilterPill(
                                    label: label,
                                    selected: app.theme == c,
                                    onTap: () => app.setTheme(c)),
                            ]),
                            const SizedBox(height: 18),
                            if (context.mock != null)
                              tile(
                                  Icons.science_outlined,
                                  tr3('开发者工具（模拟数据）', 'Әзірлеуші құралдары',
                                      'Инструменты разработчика'),
                                  () => pushPage<void>(
                                      context, (_) => const DevToolsPage()),
                                  sub: tr3(
                                      '切换测试账号、快进时间、模拟断网',
                                      'Сынақ аккаунты, уақыт',
                                      'Тестовые аккаунты, время, сеть')),
                            if (account != null) ...[
                              const Divider(height: 32),
                              TextButton(
                                  onPressed: () => attempt(
                                      context, () => context.repos.signOut()),
                                  child: Text(tr3('退出登录', 'Шығу', 'Выйти'))),
                              TextButton(
                                  onPressed: () async {
                                    if (await confirmDialog(
                                            context,
                                            tr3('注销账号？', 'Аккаунтты жою?',
                                                'Удалить аккаунт?'),
                                            body: tr3(
                                                '名片和招募中的需求会下架，云端设计备份会删除。已有合作记录保留，对方看到“已注销用户”。本机设计不受影响。',
                                                'Профильдер мен тапсырыстар алынады. Жергілікті жобалар қалады.',
                                                'Профили и заявки будут сняты, облачные копии удалены. Локальные проекты останутся.'),
                                            ok: tr3('注销', 'Жою', 'Удалить')) &&
                                        context.mounted)
                                      await attempt(context,
                                          () => context.repos.deleteAccount(),
                                          success: tr3(
                                              '账号已注销',
                                              'Аккаунт жойылды',
                                              'Аккаунт удалён'));
                                  },
                                  child: Text(
                                      tr3('注销账号', 'Аккаунтты жою',
                                          'Удалить аккаунт'),
                                      style: TextStyle(color: t.crit))),
                            ],
                            const SizedBox(height: 12),
                            Text(
                                tr3(
                                    'Yusal 不提供付款担保或资金托管，不承诺施工质量。',
                                    'Yusal төлем кепілдігін бермейді.',
                                    'Yusal не гарантирует оплату и качество работ.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: t.faint, fontSize: 12)),
                          ]))))));
    });
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
                                            fontSize: 13)),
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

class FavouritesPage extends StatelessWidget {
  const FavouritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return PageScaffold(
        title: tr3('收藏', 'Таңдаулы', 'Избранное'),
        body: Live<List<Demand>>(
            load: (r) async => [
                  for (final id in await r.favourites())
                    if (await r.demand(id) case final d?) d
                ],
            builder: (context, list) => Column(children: [
                  if (list.isEmpty)
                    EmptyState(
                        icon: Icons.favorite_border,
                        title: tr3('还没有收藏', 'Бос', 'Пусто')),
                  for (final d in list)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DemandCard(
                            compact: true,
                            demand: d,
                            onTap: () => pushPage<void>(context,
                                (_) => DemandDetailPage(demandId: d.id)))),
                ])));
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
              load: (r) async =>
                  [for (final id in await r.blocked()) await r.account(id)],
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
