import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../../features/house_editor.dart';
import '../../domain/models.dart';
import '../backup/backup_page.dart';
import '../cards.dart';
import '../demand/demand_detail_page.dart';
import '../home/publish_post_page.dart';
import '../demand/publish_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Second tab: my designs, the demands I published and my cooperations.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.drafting, required this.reload});

  /// The design tool keeps its own drafting look.
  final ThemeData drafting;
  final Listenable reload;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return DefaultTabController(
        length: 3,
        child: Scaffold(
            appBar: AppBar(
                title: Text(tr3('我的设计', 'Жобаларым', 'Мои проекты'),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                bottom: TabBar(tabs: [
                  Tab(text: tr3('设计', 'Жобалар', 'Проекты')),
                  Tab(text: tr3('我发布的需求', 'Тапсырыстарым', 'Мои заявки')),
                  Tab(text: tr3('合作', 'Келісімдер', 'Сотрудничество')),
                ])),
            body: TabBarView(children: [
              Theme(
                  data: drafting,
                  child: HouseHome(
                      store: context.projectStore,
                      reload: reload,
                      onFindBuilders: (entry) => pushPage<void>(
                          context, (_) => PublishPostPage(entry: entry)),
                      onBackup: (entry) => pushPage<void>(
                          context, (_) => BackupPage(highlight: entry.id)))),
              const _MyDemands(),
              const MyCooperations(),
            ])));
  }
}

/// Shown in place of lists that need an account.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => EmptyState(
      icon: Icons.lock_outline,
      title: text,
      action: FilledButton(
          onPressed: () => requireLogin(context),
          child: Text(tr3('登录', 'Кіру', 'Войти'))));
}

class _MyDemands extends StatelessWidget {
  const _MyDemands();
  @override
  Widget build(BuildContext context) => OnChange(
      builder: (context) => context.repos.currentAccount == null
          ? SignInPrompt(
              text: tr3('登录后查看你发布的需求', 'Тапсырыстарыңызды көру үшін кіріңіз',
                  'Войдите, чтобы видеть свои заявки'))
          : Live<List<Demand>>(
              load: (r) => r.myDemands(),
              builder: (context, list) => ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        FilledButton.icon(
                            onPressed: () => pushPage<void>(
                                context, (_) => const PublishPage()),
                            icon: const Icon(Icons.add),
                            label: Text(
                                tr3('发布需求', 'Тапсырыс беру', 'Новая заявка'))),
                        const SizedBox(height: 16),
                        if (list.isEmpty)
                          EmptyState(
                              icon: Icons.post_add,
                              title: tr3('还没有发布需求', 'Әзірге тапсырыс жоқ',
                                  'Заявок пока нет'),
                              body: tr3(
                                  '可以直接发布，也可以在“设计”里从某个设计找施工方。',
                                  'Тікелей не жобадан жариялаңыз.',
                                  'Опубликуйте сразу или из проекта.')),
                        for (final d in list)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DemandCard(
                                  compact: true,
                                  demand: d,
                                  trailing: d.status == DemandStatus.open
                                      ? Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: StatusPill(
                                              demandStatusName(d.status),
                                              color: YTokens.of(context).ok))
                                      : null,
                                  onTap: () => pushPage<void>(
                                      context,
                                      (_) =>
                                          DemandDetailPage(demandId: d.id)))),
                      ])));
}

class MyCooperations extends StatelessWidget {
  const MyCooperations({super.key});
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return OnChange(
        builder: (context) => context.repos.currentAccount == null
            ? SignInPrompt(
                text: tr3('登录后查看合作记录', 'Кіріңіз',
                    'Войдите, чтобы видеть сотрудничество'))
            : Live<List<(Cooperation, String)>>(
                load: (r) async => [
                      for (final c in await r.myCooperations())
                        (c, (await r.demand(c.demandId))?.current.title ?? '')
                    ],
                builder: (context, list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.handshake_outlined,
                        title: tr3(
                            '还没有合作', 'Келісім жоқ', 'Пока нет сотрудничества'),
                        body: tr3(
                            '在报名／报价中选定对方并双方确认后，会出现在这里。',
                            'Екі жақ растағаннан кейін осында болады.',
                            'Появится после подтверждения обеими сторонами.'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                            for (final (c, title) in list)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: YCard(
                                      onTap: () =>
                                          openCooperation(context, c.id),
                                      child: Row(children: [
                                        const Icon(Icons.handshake_outlined),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(title,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              Text(
                                                  '${cooperationStatusName(c)} · ${c.agreement.amount == null ? '' : money(c.agreement.amount, unit: c.agreement.amountUnit)}',
                                                  style: TextStyle(
                                                      color: t.muted,
                                                      fontSize: 13)),
                                            ])),
                                        const Icon(Icons.chevron_right),
                                      ]))),
                          ])));
  }
}
