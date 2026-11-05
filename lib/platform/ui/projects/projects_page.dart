import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../../features/house_editor.dart';
import '../../domain/models.dart';
import '../backup/backup_page.dart';
import '../demand/demand_detail_page.dart';
import '../home/post_page.dart';
import '../home/publish_post_page.dart';
import '../demand/from_design_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import '../house_progress.dart';
import '../houses/my_houses_data.dart';
import '../houses/my_jobs.dart';
import '../houses/workspace_page.dart';

/// Second tab, "我的房子": where each of my houses stands. A to-do strip on
/// top, the houses with platform activity as cards that open their
/// workspace, then the design list. People with a pro card also get
/// "我接的活".
class ProjectsPage extends StatelessWidget {
  const ProjectsPage(
      {super.key,
      required this.drafting,
      required this.reload,
      this.createRequest});

  /// The design tool keeps its own drafting look.
  final ThemeData drafting;
  final Listenable reload;

  /// "＋ → draw from scratch" opens the template picker.
  final Listenable? createRequest;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final houses = _HousesView(
        drafting: drafting, reload: reload, createRequest: createRequest);
    final title =
        Text(tr3('我的房子', 'Үйлерім', 'Мои дома'), style: display(size: 24));
    return OnChange(
        builder: (context) => Live<bool>(
            reloadKey: ('is-pro', context.repos.currentAccount?.id),
            load: (r) async =>
                r.currentAccount != null && (await r.myProfiles()).isNotEmpty,
            loading: Scaffold(appBar: AppBar(title: title), body: houses),
            builder: (context, pro) => !pro
                ? Scaffold(appBar: AppBar(title: title), body: houses)
                : DefaultTabController(
                    length: 2,
                    child: Scaffold(
                        appBar: AppBar(
                            title: title,
                            bottom: TabBar(tabs: [
                              Tab(text: tr3('我的房子', 'Үйлерім', 'Мои дома')),
                              Tab(
                                  text:
                                      tr3('我接的活', 'Жұмыстарым', 'Моя работа')),
                            ])),
                        body: TabBarView(
                            children: [houses, const MyJobsView()])))));
  }
}

class _HousesView extends StatelessWidget {
  const _HousesView(
      {required this.drafting, required this.reload, this.createRequest});
  final ThemeData drafting;
  final Listenable reload;
  final Listenable? createRequest;
  @override
  Widget build(BuildContext context) {
    final store = context.projectStore;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (context.repos.currentAccount != null)
        ListenableBuilder(
            listenable: reload,
            builder: (context, _) => Live<List<MyHouse>>(
                load: (r) => loadMyHouses(r, store),
                loading: const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                builder: (context, list) => list.isEmpty
                    ? const SizedBox.shrink()
                    : _ActiveHouses(houses: list))),
      Expanded(
          child: Theme(
              data: drafting,
              child: HouseHome(
                  store: store,
                  reload: reload,
                  createRequest: createRequest,
                  onPublishPost: (entry) => pushPage<void>(
                      context, (_) => PublishPostPage(entry: entry)),
                  onFindBuilders: (entry) => pushPage<void>(
                      context, (_) => FromDesignPage(entry: entry)),
                  onBackup: (entry) => pushPage<void>(
                      context, (_) => BackupPage(highlight: entry.id))))),
    ]);
  }
}

/// To-do strip (things only I can unblock: confirmations, inspections,
/// work days; new quotes show on the house cards) and the houses that have demands, quotes or cooperations.
class _ActiveHouses extends StatelessWidget {
  const _ActiveHouses({required this.houses});
  final List<MyHouse> houses;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.repos.currentAccount?.id ?? '';
    final todos = <(String, MyHouse, int)>[];
    for (final h in houses) {
      if (h.pendingConfirm(me) > 0)
        todos.add((
          tr3('「${h.name}」有合作约定待你确认', '«${h.name}»: келісімді растаңыз',
              '«${h.name}»: подтвердите соглашение'),
          h,
          2
        ));
      if (h.endAsks(me) > 0)
        todos.add((
          tr3('「${h.name}」对方请求结束合作', '«${h.name}»: аяқтауды растаңыз',
              '«${h.name}»: подтвердите завершение'),
          h,
          2
        ));
      final inspections = h.cooperations
          .expand((c) => c.milestones)
          .where((m) => m.status == MilestoneStatus.requested)
          .length;
      if (inspections > 0)
        todos.add((
          tr3(
              '「${h.name}」$inspections 个节点待验收',
              '«${h.name}»: кезеңді қабылдаңыз',
              '«${h.name}»: этапов к приёмке $inspections'),
          h,
          3
        ));
      final days = h.cooperations
          .expand((c) => c.workLogs)
          .where((w) => !w.confirmed)
          .length;
      if (days > 0)
        todos.add((
          tr3('「${h.name}」$days 天记工待确认', '«${h.name}»: $days күн расталмады',
              '«${h.name}»: дней к подтверждению $days'),
          h,
          3
        ));
    }
    void open(MyHouse h, int tab) => pushPage<void>(
        context,
        (_) => h.shareOnly
            ? PostPage(postId: h.postId!)
            : HouseWorkspacePage(houseKey: h.key, initialTab: tab));
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (todos.isNotEmpty)
            Container(
                key: const Key('todo-strip'),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    border:
                        Border(left: BorderSide(color: t.accent, width: 3))),
                child: Material(
                    color: t.surface,
                    child: Column(children: [
                      for (final (text, h, tab) in todos.take(4))
                        ListTile(
                            dense: true,
                            leading:
                                Icon(Icons.circle, size: 10, color: t.accent),
                            title: Text(text),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => open(h, tab)),
                    ]))),
          SizedBox(
              height: 104,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: houses.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final h = houses[i];
                    return SizedBox(
                        width: 290,
                        child: Card(
                            margin: EdgeInsets.zero,
                            child: InkWell(
                                key: Key('house-card-${h.key}'),
                                borderRadius: BorderRadius.circular(yRadius),
                                onTap: () => open(h, 0),
                                child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(children: [
                                      HouseThumb(house: h, size: 80),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                            Text(h.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            const SizedBox(height: 4),
                                            StatusPill(
                                                h.shareOnly
                                                    ? tr3('已分享', 'Бөлісілді',
                                                        'Опубликован')
                                                    : houseStageName(h.stage),
                                                color: t.accent),
                                            const SizedBox(height: 4),
                                            Text(h.nextStep(me),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: h.needsMe(me)
                                                        ? t.accent
                                                        : t.muted,
                                                    fontWeight: h.newQuotes > 0
                                                        ? FontWeight.w600
                                                        : null,
                                                    fontSize: 12)),
                                          ])),
                                    ])))));
                  })),
        ]));
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

class MyCooperations extends StatefulWidget {
  const MyCooperations({super.key});
  @override
  State<MyCooperations> createState() => _MyCooperationsState();
}

class _MyCooperationsState extends State<MyCooperations> {
  int _retry = 0;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return OnChange(
        builder: (context) => context.repos.currentAccount == null
            ? SignInPrompt(
                text: tr3('登录后查看合作记录', 'Кіріңіз',
                    'Войдите, чтобы видеть сотрудничество'))
            : Live<List<(Cooperation, String)>>(
                reloadKey: ('my-cooperations', _retry),
                load: (r) async {
                  final cooperations = await r.myCooperations();
                  final titles = <String, String>{};
                  await Future.wait(cooperations
                      .map((c) => c.demandId)
                      .toSet()
                      .map((id) async {
                    try {
                      titles[id] = (await r.demand(id))?.current.title ??
                          tr3('需求已不可见', 'Тапсырыс қолжетімсіз',
                              'Заявка недоступна');
                    } catch (_) {
                      titles[id] = tr3('标题暂不可用', 'Атауы уақытша қолжетімсіз',
                          'Название временно недоступно');
                    }
                  }));
                  return [
                    for (final c in cooperations) (c, titles[c.demandId]!)
                  ];
                },
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
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                    onPressed: () => setState(() => _retry++),
                                    icon: const Icon(Icons.refresh),
                                    label: Text(
                                        tr3('刷新', 'Жаңарту', 'Обновить')))),
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
