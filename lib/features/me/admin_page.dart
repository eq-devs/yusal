import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/settings.dart';
import '../../data/http/http_backend.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../../shared/ui/components.dart';
import '../demand/demand_detail_page.dart';
import '../home/post_page.dart';
import '../../shared/ui/l10n.dart';
import '../profile/profile_page.dart';
import '../../shared/ui/scope.dart';
import '../../shared/ui/theme.dart';
import '../../shared/ui/widgets.dart';

part 'admin_console.dart';

// The back office, in the moderator's language: a to-do first screen,
// review, accounts and the rest. Text users read (reasons) can be preset
// codes, shown to them in their own language. The server checks the role
// on every call; the menu only hides what the role cannot do.

/// The back office. Opens for accounts with an admin role.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _tab = 0;

  /// Which review list the 审核 tab shows; the to-do list sets it.
  final _reviewKind = ValueNotifier(_Review.demands);

  @override
  void dispose() {
    _reviewKind.dispose();
    super.dispose();
  }

  void _open(_Review kind) {
    _reviewKind.value = kind;
    setState(() => _tab = 1);
  }

  @override
  Widget build(BuildContext context) => OnChange(builder: (context) {
        final me = context.repos.currentAccount;
        if (me == null || !me.can(AdminPerms.read)) {
          // The role went away (revoked, signed out): close the console.
          return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                  icon: Icons.lock_outline,
                  title: tr3('没有后台权限', 'Әкімшілікке рұқсат жоқ',
                      'Нет доступа к админке')));
        }
        final tabs = [
          tr3('工作台', 'Шолу', 'Сводка'),
          tr3('审核', 'Тексеру', 'Проверка'),
          tr3('用户', 'Қолданушылар', 'Пользователи'),
          tr3('更多', 'Тағы', 'Ещё'),
        ];
        final pages = [
          _Workbench(open: _open),
          _ReviewTab(kind: _reviewKind),
          const _UsersTab(),
          const _MoreTab(),
        ];
        return Scaffold(
            appBar: AppBar(
                title: Text(tabs[_tab]),
                actions: [
                  Padding(
                      padding: const EdgeInsets.only(right: YSpace.lg),
                      child: Center(child: StatusPill(roleName(me.role)))),
                ]),
            body: IndexedStack(index: _tab, children: pages),
            bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  NavigationDestination(
                      icon: const Icon(Icons.dashboard_outlined), label: tabs[0]),
                  NavigationDestination(
                      icon: const Icon(Icons.fact_check_outlined), label: tabs[1]),
                  NavigationDestination(
                      icon: const Icon(Icons.people_outline), label: tabs[2]),
                  NavigationDestination(
                      icon: const Icon(Icons.more_horiz), label: tabs[3]),
                ]));
      });
}

String roleName(String? role) => switch (role) {
      AdminRoles.superadmin => tr3('超级管理员', 'Бас әкімші', 'Суперадмин'),
      AdminRoles.moderator => tr3('审核员', 'Модератор', 'Модератор'),
      AdminRoles.operator => tr3('运营', 'Оператор', 'Оператор'),
      AdminRoles.viewer => tr3('只读', 'Тек оқу', 'Только чтение'),
      _ => tr3('无', 'Жоқ', 'Нет'),
    };

bool _may(BuildContext context, String perm) =>
    context.repos.currentAccount?.can(perm) ?? false;

String _date(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.month}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String _reportTargetName(ReportTarget t) => switch (t) {
      ReportTarget.demand => _targetName('demand'),
      ReportTarget.profile => _targetName('profile'),
      ReportTarget.account => _targetName('account'),
      ReportTarget.message => _targetName('message'),
      ReportTarget.post => _targetName('post'),
      ReportTarget.comment => _targetName('comment'),
    };

String _reportStatusName(ReportStatus s) => switch (s) {
      ReportStatus.open => tr3('待处理', 'Күтуде', 'Ожидает'),
      ReportStatus.upheld => tr3('成立', 'Расталды', 'Подтверждена'),
      ReportStatus.dismissed => tr3('驳回', 'Қабылданбады', 'Отклонена'),
    };

String get _all => tr3('全部', 'Барлығы', 'Все');
String get _userSees => tr3('用户会看到这段说明',
    'Бұл түсініктемені пайдаланушы көреді', 'Это пояснение увидит пользователь');
String get _restrictedPill => tr3('受限', 'Шектелген', 'Ограничен');
String get _unnamed => tr3('（未命名）', '(атаусыз)', '(без имени)');
String get _approveWord => tr3('通过', 'Мақұлдау', 'Одобрить');
String get _dismissWord => tr3('驳回', 'Қабылдамау', 'Отклонить');
String get _teamTitle => tr3('后台成员', 'Команда', 'Команда');
String get _pushTitle =>
    tr3('推送节制', 'Хабарландыру шектеулері', 'Ограничения уведомлений');
String _registered(DateTime t) => tr3('注册 ${_date(t)}',
    'Тіркелген: ${_date(t)}', 'Регистрация: ${_date(t)}');

String _targetName(String t) => switch (t) {
      'demand' => tr3('需求', 'Тапсырыс', 'Заявка'),
      'profile' => tr3('名片', 'Профиль', 'Профиль'),
      'account' => tr3('账号', 'Аккаунт', 'Аккаунт'),
      'message' => tr3('消息', 'Хабар', 'Сообщение'),
      'post' => tr3('房子', 'Үй', 'Дом'),
      'comment' => tr3('评论', 'Пікір', 'Комментарий'),
      'platform' => tr3('全平台', 'Бүкіл платформа', 'Вся платформа'),
      _ => t,
    };

/// A reason as moderators read it: preset codes as short labels.
String _reasonLabel(String r) => switch (r) {
      'code:contact' =>
        tr3('含联系方式', 'Байланыс деректері бар', 'Есть контакты'),
      'code:fake' =>
        tr3('虚假信息', 'Жалған ақпарат', 'Недостоверные сведения'),
      'code:illegal' =>
        tr3('违规内容', 'Ережеге қайшы мазмұн', 'Запрещённое содержание'),
      'code:incomplete' =>
        tr3('信息不全', 'Ақпарат толық емес', 'Неполные данные'),
      'code:duplicate' =>
        tr3('重复发布', 'Қайталанған жарияланым', 'Повторная публикация'),
      'code:abuse' =>
        tr3('辱骂骚扰', 'Балағат не қудалау', 'Оскорбления, преследование'),
      'code:spam' => tr3('广告引流', 'Жарнама не спам', 'Реклама или спам'),
      'code:ok' =>
        tr3('未发现问题', 'Бұзушылық табылмады', 'Нарушений не найдено'),
      _ when r.startsWith('banned:') => tr3(
          '命中禁用词：${r.substring(7)}',
          'Тыйым салынған сөз: ${r.substring(7)}',
          'Запрещённое слово: ${r.substring(7)}'),
      _ => r,
    };

String _actionName(String a) => switch (a) {
      'approve' => tr3('通过需求', 'Тапсырыс мақұлданды', 'Заявка одобрена'),
      'reject' => tr3('拒绝需求', 'Тапсырыс қабылданбады', 'Заявка отклонена'),
      'uphold' => tr3('举报成立', 'Шағым расталды', 'Жалоба подтверждена'),
      'dismiss' => tr3('驳回举报', 'Шағым қабылданбады', 'Жалоба отклонена'),
      'restrict' => tr3('限制账号', 'Аккаунт шектелді', 'Аккаунт ограничен'),
      'unrestrict' => tr3('解除限制', 'Шектеу алынды', 'Ограничение снято'),
      'post_hide' => tr3('隐藏房子', 'Үй жасырылды', 'Дом скрыт'),
      'post_show' => tr3('恢复房子', 'Үй қайтарылды', 'Дом восстановлен'),
      'appeal_accept' => tr3('申诉成立', 'Апелляция қанағаттандырылды', 'Апелляция удовлетворена'),
      'appeal_reject' =>
        tr3('申诉驳回', 'Апелляция қабылданбады', 'Апелляция отклонена'),
      'verify_approve' =>
        tr3('认证通过', 'Растау мақұлданды', 'Верификация одобрена'),
      'verify_reject' =>
        tr3('认证驳回', 'Растау қабылданбады', 'Верификация отклонена'),
      'role_revoke' => tr3('撤销角色', 'Рөл алынды', 'Роль снята'),
      'push_policy' => tr3('修改推送节制', 'Хабарландыру шектеулері өзгертілді',
          'Изменены ограничения уведомлений'),
      _ when a.startsWith('role_grant:') => tr3(
          '授予${roleName(a.substring(11))}',
          'Рөл берілді: ${roleName(a.substring(11))}',
          'Назначена роль: ${roleName(a.substring(11))}'),
      _ => a,
    };

/// Picks a preset reason or takes the moderator's own words.
Future<String?> _pickReason(BuildContext context, String title,
    {List<String> codes = const [
      'contact', 'fake', 'illegal', 'incomplete', 'duplicate', 'abuse', 'spam'
    ]}) async {
  final v = await pickOne<String>(context, title, [
    for (final c in codes) ('code:$c', _reasonLabel('code:$c')),
    ('', tr3('自己填写…', 'Өзім жазамын…', 'Свой текст…')),
  ]);
  if (v == null || !context.mounted) return null;
  if (v.isNotEmpty) return v;
  return askText(context, title, hint: _userSees);
}

// ─────────────────────────── paged lists ───────────────────────────

/// A back-office list that loads more pages as it reaches the end.
class _PagedList<T> extends StatefulWidget {
  const _PagedList(
      {super.key,
      required this.load,
      required this.item,
      required this.empty,
      this.header});
  final Future<Paged<T>> Function(int page) load;
  final Widget Function(BuildContext, T) item;
  final String empty;
  final Widget? header;
  @override
  State<_PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<_PagedList<T>> {
  int _pages = 1;
  final _refresh = LiveRefresh();

  /// Pages 1…[_pages] in order, as one list; reloaded together on change.
  Future<(List<T>, bool)> _loadAll() async {
    final out = <T>[];
    var more = false;
    for (var p = 1; p <= _pages; p++) {
      final page = await widget.load(p);
      out.addAll(page.items);
      more = page.hasMore;
      if (!more) break;
    }
    return (out, more);
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: _refresh.call,
      child: Live<(List<T>, bool)>(
          refresh: _refresh,
          reloadKey: (widget.key, _pages),
          load: (_) => _loadAll(),
          builder: (context, data) {
            final (items, more) = data;
            return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (more &&
                      n.metrics.extentAfter < 400 &&
                      n is ScrollEndNotification) {
                    setState(() => _pages++);
                  }
                  return false;
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                        YSpace.gutter, YSpace.sm, YSpace.gutter, YSpace.huge),
                    children: [
                      if (widget.header != null) widget.header!,
                      if (items.isEmpty)
                        EmptyState(icon: Icons.inbox_outlined, title: widget.empty),
                      for (final x in items) widget.item(context, x),
                      if (more)
                        Center(
                            child: TextButton(
                                onPressed: () => setState(() => _pages++),
                                child: Text(tr3('加载更多', 'Тағы жүктеу', 'Показать ещё')))),
                    ]));
          }));
}

class _Chips<T> extends StatelessWidget {
  const _Chips(
      {required this.options, required this.selected, required this.onSelect});
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: YSpace.gutter, vertical: YSpace.sm),
      child: Row(children: [
        for (final (v, label) in options)
          Padding(
              padding: const EdgeInsets.only(right: YSpace.sm),
              child: FilterPill(
                  label: label, selected: v == selected, onTap: () => onSelect(v))),
      ]));
}

// ─────────────────────────── 工作台 ───────────────────────────

class _Workbench extends StatelessWidget {
  const _Workbench({required this.open});
  final void Function(_Review) open;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final refresh = LiveRefresh();
    return RefreshIndicator(
        onRefresh: refresh.call,
        child: Live<(AdminTodo, AdminDashboard)>(
            refresh: refresh,
            load: (r) => (r.todo(), r.dashboard()).wait,
            builder: (context, data) {
              final (todo, d) = data;
              int total(String k) => d.totals[k] ?? 0;
              return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      YSpace.gutter, YSpace.sm, YSpace.gutter, YSpace.huge),
                  children: [
                    for (final h in todo.health)
                      Padding(
                          padding: const EdgeInsets.only(bottom: YSpace.sm),
                          child: Hint(
                              switch (h) {
                                'sweep_stalled' => tr3(
                                    '定时任务超过 5 分钟没有运行：到期、提醒和单方结束会停住，请检查服务器。',
                                    'Жоспарлы тапсырма 5 минуттан бері іске қосылмады: мерзімнің бітуі, еске салулар және біржақты аяқтау тоқтап тұр. Серверді тексеріңіз.',
                                    'Фоновая задача не запускалась больше 5 минут: истечение сроков, напоминания и одностороннее завершение остановлены. Проверьте сервер.'),
                                'manual_review_on' => tr3(
                                    '已开启人工审核：新需求要等审核员通过才会公开。',
                                    'Қолмен тексеру қосулы: жаңа тапсырыстар модератор мақұлдағаннан кейін ғана жарияланады.',
                                    'Включена ручная проверка: новые заявки публикуются только после одобрения модератором.'),
                                _ => h,
                              },
                              warn: h != 'manual_review_on')),
                    Text(
                        todo.total == 0
                            ? tr3('没有待办，一切正常', 'Күтіп тұрған іс жоқ, бәрі дұрыс',
                                'Задач нет, всё в порядке')
                            : tr3('待办 ${todo.total} 项', 'Күтіп тұрған іс: ${todo.total}',
                                'Задач: ${todo.total}'),
                        style: display(size: 22)),
                    const SizedBox(height: YSpace.md),
                    _TodoTile(
                        icon: Icons.fact_check_outlined,
                        title: tr3('需求审核', 'Тапсырыстарды тексеру', 'Проверка заявок'),
                        count: todo.review.count,
                        lines: [for (final x in todo.review.items) x.current.title],
                        onTap: () => open(_Review.demands)),
                    _TodoTile(
                        icon: Icons.flag_outlined,
                        title: tr3('举报', 'Шағымдар', 'Жалобы'),
                        count: todo.reports.count,
                        lines: [
                          for (final x in todo.reports.items)
                            '${_reportTargetName(x.target)} · ${_reasonLabel(x.reason)}'
                        ],
                        onTap: () => open(_Review.reports)),
                    _TodoTile(
                        icon: Icons.gavel_outlined,
                        title: tr3('申诉', 'Апелляциялар', 'Апелляции'),
                        count: todo.appeals.count,
                        lines: [for (final x in todo.appeals.items) x.text],
                        onTap: () => open(_Review.appeals)),
                    _TodoTile(
                        icon: Icons.verified_outlined,
                        title: tr3('工人认证', 'Шеберлерді растау', 'Верификация мастеров'),
                        count: todo.verifications.count,
                        lines: [for (final x in todo.verifications.items) x.name],
                        onTap: () => open(_Review.verifications)),
                    _TodoTile(
                        icon: Icons.report_problem_outlined,
                        title: tr3('超过 3 天未解决的争议', '3 күннен астам шешілмеген даулар',
                            'Споры без решения дольше 3 дней'),
                        count: todo.disputes.count,
                        lines: [
                          for (final c in todo.disputes.items)
                            c.endRequest?.dispute ??
                                tr3('节点验收有异议', 'Кезеңді қабылдауға қарсылық бар',
                                    'Спор о приёмке этапа')
                        ]),
                    const SizedBox(height: YSpace.xl),
                    Text(tr3('今天', 'Бүгін', 'Сегодня'), style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    Wrap(spacing: YSpace.sm, runSpacing: YSpace.sm, children: [
                      for (final (k, label) in [
                        ('active', tr3('活跃设备', 'Белсенді құрылғы', 'Активные устройства')),
                        ('new_users', tr3('新用户', 'Жаңа аккаунт', 'Новые аккаунты')),
                        ('new_posts', tr3('新房子', 'Жаңа үй', 'Новые дома')),
                        ('new_demands', tr3('新需求', 'Жаңа тапсырыс', 'Новые заявки')),
                        ('new_quotes', tr3('新报价', 'Жаңа ұсыныс', 'Новые отклики')),
                        ('new_cooperations', tr3('新合作', 'Жаңа келісім', 'Новые сделки')),
                        ('inspections', tr3('节点验收', 'Кезең қабылдау', 'Приёмка этапов')),
                      ])
                        _Stat(label, d.today[k] ?? 0),
                    ]),
                    const SizedBox(height: YSpace.xl),
                    Text(tr3('近 7 天', 'Соңғы 7 күн', 'За 7 дней'), style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    _Bars(days: d.daily),
                    const SizedBox(height: YSpace.xl),
                    Text(tr3('从房子到验收', 'Үйден қабылдауға дейін', 'От дома до приёмки'),
                        style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    _Funnel(steps: d.funnel),
                    if (d.firstQuoteHours != null) ...[
                      const SizedBox(height: YSpace.sm),
                      Text(
                          tr3(
                              '需求发布后收到第一个报价：中位 ${d.firstQuoteHours!.toStringAsFixed(1)} 小时',
                              'Тапсырыс жарияланғаннан алғашқы ұсынысқа дейін: медиана ${d.firstQuoteHours!.toStringAsFixed(1)} сағ',
                              'От публикации заявки до первого предложения: медиана ${d.firstQuoteHours!.toStringAsFixed(1)} ч'),
                          style: YText.caption.copyWith(color: t.muted)),
                    ],
                    const SizedBox(height: YSpace.xl),
                    Text(
                        tr3(
                            '各地区供需（招募中的需求 / 可接活的名片）',
                            'Аймақтар бойынша сұраныс пен ұсыныс (ашық тапсырыстар / бос профильдер)',
                            'Спрос и предложение по районам (открытые заявки / свободные профили)'),
                        style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    YCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          if (d.regions.isEmpty)
                            Padding(
                                padding: const EdgeInsets.all(YSpace.lg),
                                child: Text(tr3('暂无数据', 'Дерек жоқ', 'Нет данных'))),
                          for (final r in d.regions)
                            ListTile(
                                dense: true,
                                title: Text(regionName(r.region)),
                                trailing: Text('${r.demands} / ${r.workers}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: r.workers == 0 && r.demands > 0
                                            ? t.crit
                                            : t.ink))),
                        ])),
                    const SizedBox(height: YSpace.xl),
                    Text(
                        tr3(
                            '累计：用户 ${total('users')} · 房子 ${total('posts')} · 名片 ${total('profiles')} · 需求 ${total('demands')}',
                            'Барлығы: аккаунт ${total('users')} · үй ${total('posts')} · профиль ${total('profiles')} · тапсырыс ${total('demands')}',
                            'Всего: аккаунты ${total('users')} · дома ${total('posts')} · профили ${total('profiles')} · заявки ${total('demands')}'),
                        style: YText.caption.copyWith(color: t.muted)),
                  ]);
            }));
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile(
      {required this.icon,
      required this.title,
      required this.count,
      required this.lines,
      this.onTap});
  final IconData icon;
  final String title;
  final int count;
  final List<String> lines;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: YSpace.sm),
        child: YCard(
            onTap: onTap,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: t.accent),
              const SizedBox(width: YSpace.md),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: YText.bodyStrong),
                    for (final l in lines.take(3))
                      Text(l,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YText.caption.copyWith(color: t.muted)),
                  ])),
              StatusPill('$count', color: t.accent, filled: true),
            ])));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Container(
        width: 104,
        padding: const EdgeInsets.all(YSpace.md),
        decoration: BoxDecoration(
            color: t.card,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(YRadius.control)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: display(size: 22)),
          Text(label, style: YText.caption.copyWith(color: t.muted)),
        ]));
  }
}

/// Seven days of new demands (bars) and quotes (numbers above them).
class _Bars extends StatelessWidget {
  const _Bars({required this.days});
  final List<DashboardDay> days;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    var top = 1;
    for (final d in days) {
      if (d.demands > top) top = d.demands;
      if (d.active > top) top = d.active;
    }
    return SizedBox(
        height: 170,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in days)
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${d.demands}', style: YText.caption),
                      const SizedBox(height: 2),
                      Container(
                          height: 80 * d.demands / top + 2,
                          decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(YRadius.row))),
                      const SizedBox(height: 4),
                      Text(d.day.length >= 10 ? d.day.substring(5) : d.day,
                          style: YText.caption.copyWith(color: t.muted)),
                      Text(
                          tr3('活跃 ${d.active}', 'Белс. ${d.active}',
                              'Акт. ${d.active}'),
                          style: YText.caption.copyWith(color: t.muted)),
                    ]))),
        ]));
  }
}

class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});
  final List<(String, int)> steps;
  static String _name(String k) => switch (k) {
        'posts' => tr3('公开的房子', 'Жария үйлер', 'Опубликованные дома'),
        'reuses' => tr3('被复用', 'Негізге алынды', 'Взято за основу'),
        'demands' =>
          tr3('发布的需求', 'Жарияланған тапсырыстар', 'Опубликованные заявки'),
        'quoted' =>
          tr3('收到报价的需求', 'Ұсыныс түскен тапсырыстар', 'Заявки с предложениями'),
        'cooperations' => tr3('达成合作', 'Келісімдер', 'Сделки'),
        'inspected' => tr3('有节点验收', 'Кезең қабылданған', 'С приёмкой этапов'),
        'reviews' => tr3('评价', 'Пікірлер', 'Отзывы'),
        _ => k,
      };
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    var top = 1;
    for (final (_, n) in steps) {
      if (n > top) top = n;
    }
    return Column(children: [
      for (final (k, n) in steps)
        Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 110, child: Text(_name(k), style: YText.caption)),
              Expanded(
                  child: LayoutBuilder(
                      builder: (context, c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                              height: 16,
                              width: c.maxWidth * n / top + 2,
                              decoration: BoxDecoration(
                                  color: t.accentSoft,
                                  borderRadius: BorderRadius.circular(YRadius.row)))))),
              SizedBox(
                  width: 44,
                  child: Text('$n', textAlign: TextAlign.end, style: YText.caption)),
            ])),
    ]);
  }
}

// ─────────────────────────── 审核 ───────────────────────────

enum _Review { demands, reports, appeals, verifications }

class _ReviewTab extends StatelessWidget {
  const _ReviewTab({required this.kind});
  final ValueNotifier<_Review> kind;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
      valueListenable: kind,
      builder: (context, k, _) => Column(children: [
            _Chips<_Review>(
                options: [
                  (_Review.demands, tr3('需求', 'Тапсырыстар', 'Заявки')),
                  (_Review.reports, tr3('举报', 'Шағымдар', 'Жалобы')),
                  (_Review.appeals, tr3('申诉', 'Апелляциялар', 'Апелляции')),
                  (_Review.verifications, tr3('认证', 'Растау', 'Верификация')),
                ],
                selected: k,
                onSelect: (v) => kind.value = v),
            Expanded(
                child: switch (k) {
              _Review.demands => const _DemandQueue(),
              _Review.reports => const _Reports(),
              _Review.appeals => const _Appeals(),
              _Review.verifications => const _Verifications(),
            }),
          ]));
}

/// Pending demands: swipe right to approve, left to reject; long-press
/// to select several and decide them together.
class _DemandQueue extends StatefulWidget {
  const _DemandQueue();
  @override
  State<_DemandQueue> createState() => _DemandQueueState();
}

class _DemandQueueState extends State<_DemandQueue> {
  final _selected = <String>{};

  Future<void> _batch(bool approve) async {
    String reason = '';
    if (!approve) {
      final r = await _pickReason(
          context,
          tr3('拒绝 ${_selected.length} 个需求的原因',
              'Қабылдамау себебі (тапсырыс: ${_selected.length})',
              'Причина отклонения (заявок: ${_selected.length})'));
      if (r == null || !mounted) return;
      reason = r;
    }
    final res = await attempt(context,
        () => context.repos.decideMany(_selected.toList(), approve, reason: reason));
    if (res == null || !mounted) return;
    toast(context,
        res.failed.isEmpty
            ? tr3('已处理 ${res.done} 个', 'Өңделді: ${res.done}', 'Обработано: ${res.done}')
            : tr3(
                '已处理 ${res.done} 个，${res.failed.length} 个状态已变化未处理',
                'Өңделді: ${res.done}; күйі өзгергендіктен өткізілді: ${res.failed.length}',
                'Обработано: ${res.done}; пропущено из-за смены статуса: ${res.failed.length}'));
    setState(_selected.clear);
  }

  Future<bool> _reject(Demand d) async {
    final r = await _pickReason(
        context, tr3('拒绝原因', 'Қабылдамау себебі', 'Причина отклонения'));
    if (r == null || !mounted) return false;
    return await attempt(context, () async {
          await context.repos.reject(d.id, r);
          return true;
        }, success: tr3('已拒绝', 'Қабылданбады', 'Отклонено')) ==
        true;
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      if (_selected.isNotEmpty)
        Material(
            color: t.surface,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: YSpace.gutter, vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          tr3('已选 ${_selected.length}', 'Таңдалды: ${_selected.length}',
                              'Выбрано: ${_selected.length}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: () => setState(_selected.clear), child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                  TextButton(onPressed: () => _batch(false), child: Text(tr3('批量拒绝', 'Қабылдамау', 'Отклонить'))),
                  FilledButton(onPressed: () => _batch(true), child: Text(tr3('批量通过', 'Мақұлдау', 'Одобрить'))),
                ]))),
      Expanded(
          child: _PagedList<Demand>(
              key: const ValueKey('queue'),
              load: (p) => context.repos.reviewQueue(page: p),
              empty: tr3('没有待审核的需求', 'Тексеруді күткен тапсырыс жоқ',
                  'Нет заявок на проверке'),
              header: canModerate
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: YSpace.sm),
                      child: Text(
                          tr3(
                              '右滑通过，左滑拒绝，长按多选',
                              'Оңға сырғыту — мақұлдау, солға — қабылдамау, ұзақ басу — бірнешеуін таңдау',
                              'Свайп вправо — одобрить, влево — отклонить, долгое нажатие — выбрать несколько'),
                          style: YText.caption.copyWith(color: t.muted)))
                  : null,
              item: (context, d) {
                final card = _DemandCard(
                    demand: d,
                    selected: _selected.contains(d.id),
                    onTap: _selected.isEmpty
                        ? () => pushPage<void>(
                            context, (_) => DemandDetailPage(demandId: d.id))
                        : () => setState(() {
                              if (!_selected.remove(d.id)) _selected.add(d.id);
                            }),
                    onLongPress: canModerate
                        ? () => setState(() => _selected.add(d.id))
                        : null);
                if (!canModerate) return card;
                return Dismissible(
                    key: ValueKey('q-${d.id}'),
                    background: _SwipeBg(
                        color: t.ok, icon: Icons.check, label: _approveWord, left: true),
                    secondaryBackground:
                        _SwipeBg(
                        color: t.crit,
                        icon: Icons.close,
                        label: tr3('拒绝', 'Қабылдамау', 'Отклонить'),
                        left: false),
                    confirmDismiss: (dir) async {
                      if (dir == DismissDirection.startToEnd) {
                        return await attempt(context, () async {
                              await context.repos.approve(d.id);
                              return true;
                            }, success: tr3('已通过', 'Мақұлданды', 'Одобрено')) ==
                            true;
                      }
                      return _reject(d);
                    },
                    child: card);
              })),
    ]);
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg(
      {required this.color, required this.icon, required this.label, required this.left});
  final Color color;
  final IconData icon;
  final String label;
  final bool left;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: YSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: YSpace.xl),
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(YRadius.card)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: onFill(color)),
        const SizedBox(width: 6),
        Text(label, style: YText.bodyStrong.copyWith(color: onFill(color))),
      ]));
}

class _DemandCard extends StatelessWidget {
  const _DemandCard(
      {required this.demand, this.selected = false, this.onTap, this.onLongPress});
  final Demand demand;
  final bool selected;
  final VoidCallback? onTap, onLongPress;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final v = demand.current;
    return Padding(
        padding: const EdgeInsets.only(bottom: YSpace.sm),
        child: GestureDetector(
            onLongPress: onLongPress,
            child: YCard(
                onTap: onTap,
                color: selected ? t.accentSoft : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (selected) ...[
                      Icon(Icons.check_circle, color: t.accent, size: 20),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: Text(v.title, style: YText.bodyStrong)),
                    StatusPill(demandStatusName(demand.status)),
                  ]),
                  const SizedBox(height: 4),
                  Text(v.description, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                      '${regionName(v.region)} · ${demandTypeName(demand.type)} · ${tr3('第 ${v.no} 版', '${v.no}-нұсқа', 'версия ${v.no}')} · ${_date(demand.createdAt)}',
                      style: YText.caption.copyWith(color: t.muted)),
                  if (demand.rejectReason != null && demand.status == DemandStatus.rejected)
                    Text(
                        tr3(
                            '拒绝原因：${_reasonLabel(demand.rejectReason!)}',
                            'Қабылдамау себебі: ${_reasonLabel(demand.rejectReason!)}',
                            'Причина отклонения: ${_reasonLabel(demand.rejectReason!)}'),
                        style: YText.caption.copyWith(color: t.crit)),
                ]))));
  }
}

class _Reports extends StatefulWidget {
  const _Reports();
  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  ReportStatus? _status = ReportStatus.open;

  Future<void> _resolve(ReportView v, bool upheld) async {
    final note = upheld
        ? await _pickReason(
            context,
            tr3('举报成立：给对方的说明', 'Шағым расталды: бұзушыға түсініктеме',
                'Жалоба подтверждена: пояснение нарушителю'))
        : await _pickReason(
            context,
            tr3('驳回举报：给举报人的说明', 'Шағым қабылданбады: шағымданушыға түсініктеме',
                'Жалоба отклонена: пояснение заявителю'),
            codes: const ['ok']);
    if (note == null || !mounted) return;
    await attempt(context, () => context.repos.resolveReport(v.report.id, upheld, note),
        success: upheld
            ? tr3(
                '已处理，内容已下架/账号已限制，双方已通知',
                'Өңделді: мазмұн алынды не аккаунт шектелді, екі жаққа хабарланды',
                'Готово: контент снят или аккаунт ограничен, обе стороны уведомлены')
            : tr3('已驳回，举报人已通知', 'Қабылданбады, шағымданушыға хабарланды',
                'Отклонено, заявитель уведомлён'));
  }

  void _openTarget(ReportView v) {
    final r = v.report;
    switch (r.target) {
      case ReportTarget.demand:
        pushPage<void>(context, (_) => DemandDetailPage(demandId: r.targetId));
      case ReportTarget.profile:
        pushPage<void>(context, (_) => ProfilePage(profileId: r.targetId));
      case ReportTarget.post:
        pushPage<void>(context, (_) => PostPage(postId: r.targetId));
      case ReportTarget.comment:
        if (v.postId != null) pushPage<void>(context, (_) => PostPage(postId: v.postId!));
      case ReportTarget.account:
        pushPage<void>(context, (_) => AccountDetailPage(accountId: r.targetId));
      case ReportTarget.message:
        if (v.targetOwnerId.isNotEmpty)
          pushPage<void>(context, (_) => AccountDetailPage(accountId: v.targetOwnerId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<ReportStatus?>(
          options: [
            (ReportStatus.open, tr3('待处理', 'Күтуде', 'Ожидают')),
            (ReportStatus.upheld, tr3('已成立', 'Расталған', 'Подтверждённые')),
            (ReportStatus.dismissed, tr3('已驳回', 'Қабылданбаған', 'Отклонённые')),
            (null, _all),
          ],
          selected: _status,
          onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<ReportView>(
              key: ValueKey('reports-$_status'),
              load: (p) => context.repos.reports(status: _status, page: p),
              empty: tr3('没有举报', 'Шағым жоқ', 'Жалоб нет'),
              item: (context, v) {
                final r = v.report;
                final reporter = v.reporterName.isEmpty ? '—' : v.reporterName;
                final accused = v.targetOwnerName.isEmpty ? '—' : v.targetOwnerName;
                return Padding(
                    padding: const EdgeInsets.only(bottom: YSpace.sm),
                    child: YCard(
                        onTap: () => _openTarget(v),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            StatusPill(_reportTargetName(r.target)),
                            const SizedBox(width: YSpace.sm),
                            Expanded(
                                child: Text(v.targetTitle.isEmpty ? r.targetId : v.targetTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: YText.bodyStrong)),
                          ]),
                          const SizedBox(height: 4),
                          Text(tr3('原因：${_reasonLabel(r.reason)}', 'Себебі: ${_reasonLabel(r.reason)}',
                              'Причина: ${_reasonLabel(r.reason)}')),
                          Text(
                              tr3(
                                  '举报人 $reporter · 被举报 $accused · ${_date(r.createdAt)}',
                                  'Шағымданушы: $reporter · Кімге: $accused · ${_date(r.createdAt)}',
                                  'Заявитель: $reporter · На кого: $accused · ${_date(r.createdAt)}'),
                              style: YText.caption.copyWith(color: t.muted)),
                          if (r.status != ReportStatus.open)
                            Text(
                                '${_reportStatusName(r.status)}${tr3('：', ': ', ': ')}${_reasonLabel(r.resolution)}',
                                style: YText.caption.copyWith(color: t.muted)),
                          if (r.status == ReportStatus.open && canModerate) ...[
                            const SizedBox(height: YSpace.sm),
                            Row(children: [
                              if (v.targetOwnerId.isNotEmpty)
                                TextButton(
                                    onPressed: () => pushPage<void>(context,
                                        (_) => AccountDetailPage(accountId: v.targetOwnerId)),
                                    child: Text(tr3('看此人', 'Аккаунт', 'Аккаунт'))),
                              const Spacer(),
                              OutlinedButton(
                                  onPressed: () => _resolve(v, false), child: Text(_dismissWord)),
                              const SizedBox(width: YSpace.sm),
                              FilledButton(
                                  onPressed: () => _resolve(v, true),
                                  child: Text(switch (r.target) {
                                    ReportTarget.account ||
                                    ReportTarget.message =>
                                      tr3('成立并限制', 'Шектеу', 'Ограничить'),
                                    ReportTarget.comment =>
                                      tr3('成立并删除', 'Жою', 'Удалить'),
                                    _ => tr3('成立并下架', 'Алып тастау', 'Снять'),
                                  })),
                            ]),
                          ],
                        ])));
              })),
    ]);
  }
}

class _Appeals extends StatefulWidget {
  const _Appeals();
  @override
  State<_Appeals> createState() => _AppealsState();
}

class _AppealsState extends State<_Appeals> {
  AppealStatus? _status = AppealStatus.open;

  Future<void> _resolve(Appeal a, bool accept) async {
    final note = await askText(
        context,
        accept
            ? tr3('申诉成立：说明', 'Апелляция қанағаттандырылды: түсініктеме',
                'Апелляция удовлетворена: пояснение')
            : tr3('维持原处理：说明', 'Шешім күшінде қалады: түсініктеме',
                'Решение оставлено в силе: пояснение'),
        hint: _userSees);
    if (note == null || !mounted) return;
    await attempt(context, () => context.repos.resolveAppeal(a.id, accept, note),
        success: accept
            ? tr3('已恢复并通知用户', 'Қалпына келтірілді, пайдаланушыға хабарланды',
                'Восстановлено, пользователь уведомлён')
            : tr3('已回复用户', 'Пайдаланушыға жауап жіберілді',
                'Ответ отправлен пользователю'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<AppealStatus?>(
          options: [
            (AppealStatus.open, tr3('待处理', 'Күтуде', 'Ожидают')),
            (AppealStatus.accepted, tr3('已成立', 'Қанағаттандырылған', 'Удовлетворённые')),
            (AppealStatus.rejected, tr3('已驳回', 'Қабылданбаған', 'Отклонённые')),
            (null, _all),
          ],
          selected: _status,
          onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<Appeal>(
              key: ValueKey('appeals-$_status'),
              load: (p) => context.repos.appeals(status: _status, page: p),
              empty: tr3('没有申诉', 'Апелляция жоқ', 'Апелляций нет'),
              item: (context, a) => Padding(
                  padding: const EdgeInsets.only(bottom: YSpace.sm),
                  child: YCard(
                      onTap: () => pushPage<void>(
                          context, (_) => AccountDetailPage(accountId: a.accountId)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          StatusPill(_targetName(a.target)),
                          const SizedBox(width: YSpace.sm),
                          Expanded(
                              child: Text(a.targetTitle.isEmpty ? a.accountName : a.targetTitle,
                                  style: YText.bodyStrong)),
                        ]),
                        const SizedBox(height: 4),
                        Text(a.text),
                        Text('${a.accountName} · ${_date(a.createdAt)}',
                            style: YText.caption.copyWith(color: t.muted)),
                        if (a.resolution.isNotEmpty)
                          Text(
                              tr3(
                                  '回复：${_reasonLabel(a.resolution)}',
                                  'Жауап: ${_reasonLabel(a.resolution)}',
                                  'Ответ: ${_reasonLabel(a.resolution)}'),
                              style: YText.caption.copyWith(color: t.muted)),
                        if (a.status == AppealStatus.open && canModerate)
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            OutlinedButton(
                                onPressed: () => _resolve(a, false),
                                child: Text(tr3('维持', 'Қабылдамау', 'Отклонить'))),
                            const SizedBox(width: YSpace.sm),
                            FilledButton(
                                onPressed: () => _resolve(a, true),
                                child: Text(tr3('成立并恢复', 'Қалпына келтіру', 'Восстановить'))),
                          ]),
                      ])))))
    ]);
  }
}

/// A verification photo: a `/media/` path on the server, or inline data
/// from the in-memory backend.
class _Photo extends StatelessWidget {
  const _Photo(this.src);
  final String src;
  @override
  Widget build(BuildContext context) {
    final Widget img;
    if (src.startsWith('data:')) {
      img = Image.memory(base64Decode(src.substring(src.indexOf(',') + 1)), fit: BoxFit.cover);
    } else {
      final r = context.repos;
      final base = r is HttpBackend ? r.baseUrl : '';
      img = Image.network('$base$src', fit: BoxFit.cover);
    }
    return GestureDetector(
        onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(child: InteractiveViewer(child: img))),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(YRadius.row),
            child: SizedBox(width: 88, height: 88, child: img)));
  }
}

class _Verifications extends StatefulWidget {
  const _Verifications();
  @override
  State<_Verifications> createState() => _VerificationsState();
}

class _VerificationsState extends State<_Verifications> {
  VerificationStatus? _status = VerificationStatus.pending;

  Future<void> _resolve(Verification v, bool approve) async {
    final note = approve
        ? ''
        : await askText(
            context, tr3('驳回原因', 'Қабылдамау себебі', 'Причина отклонения'),
            hint: tr3(
                '例如：照片看不出是本人施工的现场',
                'Мысалы: фотодан жұмысты өзі істегені көрінбейді',
                'Например: по фото не видно, что работу выполнял сам мастер'));
    if (note == null || !mounted) return;
    await attempt(context, () => context.repos.resolveVerification(v.id, approve, note),
        success: approve
            ? tr3('已通过，名片显示“已核验”', 'Мақұлданды, профильде «Расталған» белгісі шығады',
                'Одобрено, в профиле появится отметка «Проверен»')
            : tr3('已驳回并通知', 'Қабылданбады, пайдаланушыға хабарланды',
                'Отклонено, пользователь уведомлён'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<VerificationStatus?>(
          options: [
            (VerificationStatus.pending, tr3('待审核', 'Күтуде', 'Ожидают')),
            (VerificationStatus.approved, tr3('已通过', 'Мақұлданған', 'Одобренные')),
            (VerificationStatus.rejected, tr3('已驳回', 'Қабылданбаған', 'Отклонённые')),
            (null, _all),
          ],
          selected: _status,
          onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<Verification>(
              key: ValueKey('verif-$_status'),
              load: (p) => context.repos.verifications(status: _status, page: p),
              empty: tr3('没有认证申请', 'Растау өтінімі жоқ',
                  'Заявок на верификацию нет'),
              item: (context, v) => Padding(
                  padding: const EdgeInsets.only(bottom: YSpace.sm),
                  child: YCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InkWell(
                        onTap: () =>
                            pushPage<void>(context, (_) => ProfilePage(profileId: v.profileId)),
                        child: Text(v.name, style: YText.bodyStrong)),
                    Text(
                        '${v.ownerName} · ${tr3('电话 ${v.phone}', 'тел. ${v.phone}', 'тел. ${v.phone}')} · ${_date(v.createdAt)}',
                        style: YText.caption.copyWith(color: t.muted)),
                    if (v.note.isNotEmpty) Text(v.note),
                    const SizedBox(height: YSpace.sm),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in v.photos) _Photo(p),
                    ]),
                    if (v.resolution.isNotEmpty)
                      Text(
                          tr3('说明：${v.resolution}', 'Түсініктеме: ${v.resolution}',
                              'Пояснение: ${v.resolution}'),
                          style: YText.caption.copyWith(color: t.muted)),
                    if (v.status == VerificationStatus.pending && canModerate)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        OutlinedButton(
                            onPressed: () => _resolve(v, false), child: Text(_dismissWord)),
                        const SizedBox(width: YSpace.sm),
                        FilledButton(
                            onPressed: () => _resolve(v, true), child: Text(_approveWord)),
                      ]),
                  ])))))
    ]);
  }
}

// ─────────────────────────── 用户 ───────────────────────────

/// A search box whose query applies once typing pauses.
mixin _Search<T extends StatefulWidget> on State<T> {
  final search = TextEditingController();
  String _q = '';
  Timer? _typing;

  void typed(String v) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  void dispose() {
    _typing?.cancel();
    search.dispose();
    super.dispose();
  }
}

enum _UserFilter { all, restricted, team }

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> with _Search {
  _UserFilter _filter = _UserFilter.all;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(YSpace.gutter, YSpace.sm, YSpace.gutter, 0),
          child: SearchField(
              controller: search,
              hint: tr3('名字、邮箱或账号 ID', 'Аты, email не аккаунт ID',
                  'Имя, email или ID аккаунта'),
              onChanged: typed)),
      _Chips<_UserFilter>(
          options: [
            (_UserFilter.all, _all),
            (_UserFilter.restricted, tr3('受限', 'Шектелген', 'Ограниченные')),
            (_UserFilter.team, _teamTitle),
          ],
          selected: _filter,
          onSelect: (v) => setState(() => _filter = v)),
      Expanded(
          child: _PagedList<AdminUserRow>(
              key: ValueKey('users-$_q-$_filter'),
              load: (p) => context.repos.users(
                  query: _q,
                  restricted: _filter == _UserFilter.restricted,
                  admins: _filter == _UserFilter.team,
                  page: p),
              empty: tr3('没有找到用户', 'Пайдаланушы табылмады', 'Пользователи не найдены'),
              item: (context, u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(u.name.isEmpty ? '?' : u.name, size: 40),
                  title: Text(u.name.isEmpty ? _unnamed : u.name),
                  subtitle: Text([
                    if (u.email.isNotEmpty) u.email,
                    _registered(u.createdAt),
                  ].join(' · ')),
                  trailing: Wrap(spacing: 4, children: [
                    if (u.role != null) StatusPill(roleName(u.role)),
                    if (u.restricted) StatusPill(_restrictedPill, color: t.crit),
                  ]),
                  onTap: () =>
                      pushPage<void>(context, (_) => AccountDetailPage(accountId: u.id))))),
    ]);
  }
}

/// Everything about one account, with the moderator's actions.
class AccountDetailPage extends StatelessWidget {
  const AccountDetailPage({super.key, required this.accountId});
  final String accountId;

  Future<void> _restrict(BuildContext context, Account a) async {
    final note = a.restricted
        ? await askText(
            context,
            tr3('解除限制：说明', 'Шектеуді алу: түсініктеме',
                'Снятие ограничения: пояснение'),
            hint: _userSees)
        : await _pickReason(
            context, tr3('限制原因', 'Шектеу себебі', 'Причина ограничения'),
            codes: const ['fake', 'abuse', 'spam', 'illegal']);
    if (note == null || !context.mounted) return;
    await attempt(context, () => context.repos.setRestriction(a.id, !a.restricted, note),
        success: a.restricted
            ? tr3('已解除限制', 'Шектеу алынды', 'Ограничение снято')
            : tr3(
                '已限制：只能浏览，不能发布、报名和发消息',
                'Шектелді: тек қарай алады; жариялау, өтінім беру және хабар жазу жабық',
                'Ограничен: только просмотр, без публикаций, откликов и сообщений'));
  }

  Future<void> _ban(BuildContext context, Account a, bool banned) async {
    final api = _http(context);
    if (api == null) return;
    final note = banned
        ? await askText(context, tr3('解封：说明', 'Бұғаттан шығару: түсініктеме',
            'Разблокировка: пояснение'))
        : await _pickReason(
            context, tr3('封禁原因', 'Бұғаттау себебі', 'Причина блокировки'),
            codes: const ['fake', 'abuse', 'spam', 'illegal']);
    if (note == null || !context.mounted) return;
    await attempt(context, () => api.setBanned(a.id, !banned, note),
        success: banned
            ? tr3('已解封', 'Бұғаттан шығарылды', 'Разблокирован')
            : tr3('已封禁：不能登录和使用', 'Бұғатталды: кіре алмайды',
                'Заблокирован: войти нельзя'));
  }

  Future<void> _delete(BuildContext context, Account a) async {
    final api = _http(context);
    if (api == null) return;
    final note = await askText(
        context, tr3('注销原因', 'Жою себебі', 'Причина удаления'),
        hint: tr3('名片和需求会下架，云端备份删除，不能恢复。',
            'Профильдер мен тапсырыстар алынады, қалпына келмейді.',
            'Профили и заявки снимаются, восстановить нельзя.'));
    if (note == null || !context.mounted) return;
    if (!await confirmDialog(context,
            tr3('注销这个账号？', 'Аккаунтты жою керек пе?', 'Удалить аккаунт?'),
            ok: tr3('注销', 'Жою', 'Удалить'), danger: true) ||
        !context.mounted) return;
    await attempt(context, () => api.deleteAccountFor(a.id, note),
        success: tr3('已注销', 'Жойылды', 'Удалён'));
  }

  Future<void> _takeDown(BuildContext context, String target, String id) async {
    final api = _http(context);
    if (api == null) return;
    final note = await _pickReason(
        context, tr3('下架原因', 'Алып тастау себебі', 'Причина снятия'));
    if (note == null || !context.mounted) return;
    await attempt(context, () => api.takeDown(target, id, note),
        success: tr3('已下架', 'Алынды', 'Снято'));
  }

  static String _methodName(String m) => switch (m) {
        'email' => tr3('邮箱', 'Пошта', 'Почта'),
        'google' => 'Google',
        'apple' => 'Apple',
        _ => tr3('测试登录', 'Тест', 'Тест'),
      };

  Future<void> _role(BuildContext context, Account a) async {
    final v = await pickOne<String>(
        context, tr3('后台角色', 'Әкімшіліктегі рөл', 'Роль в админке'), [
      for (final r in AdminRoles.all) (r, roleName(r)),
      ('', tr3('无（撤销）', 'Жоқ (рөлді алу)', 'Нет (снять роль)')),
    ], selected: a.role ?? '');
    if (v == null || !context.mounted) return;
    await attempt(context, () => context.repos.setRole(a.id, v.isEmpty ? null : v),
        success: tr3('已更新角色', 'Рөл жаңартылды', 'Роль обновлена'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.repos.currentAccount;
    return Scaffold(
        appBar: AppBar(
            title: Text(tr3('账号详情', 'Аккаунт мәліметі', 'Сведения об аккаунте'))),
        body: Live<AccountDetail>(
            load: (r) => r.accountDetail(accountId),
            builder: (context, d) {
              final a = d.account;
              final self = me?.id == a.id;
              return ListView(padding: const EdgeInsets.all(YSpace.gutter), children: [
                Row(children: [
                  Avatar(a.displayName.isEmpty ? '?' : a.displayName, size: 56),
                  const SizedBox(width: YSpace.md),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.displayName.isEmpty ? _unnamed : a.displayName,
                        style: display(size: 22)),
                    Text(
                        [
                          if (d.email.isNotEmpty) d.email,
                          if (a.phone.isNotEmpty) a.phone,
                          _registered(a.createdAt),
                          if (d.methods.isNotEmpty)
                            d.methods.map(_methodName).join('/'),
                          if (d.lastLogin != null)
                            tr3(
                                '最近登录 ${_date(d.lastLogin!)}',
                                'Соңғы кіру: ${_date(d.lastLogin!)}',
                                'Последний вход: ${_date(d.lastLogin!)}'),
                        ].join(' · '),
                        style: YText.caption.copyWith(color: t.muted)),
                  ])),
                ]),
                const SizedBox(height: YSpace.sm),
                Wrap(spacing: 6, children: [
                  if (a.role != null) StatusPill(roleName(a.role)),
                  if (a.restricted) StatusPill(_restrictedPill, color: t.crit),
                  if (d.banned)
                    StatusPill(tr3('已封禁', 'Бұғатталған', 'Заблокирован'), color: t.crit),
                  if (a.deleted) StatusPill(tr3('已注销', 'Жойылған', 'Удалён')),
                ]),
                if (!self && !a.deleted) ...[
                  const SizedBox(height: YSpace.md),
                  Wrap(spacing: YSpace.sm, children: [
                    if (_may(context, AdminPerms.moderate) && a.role == null)
                      OutlinedButton(
                          onPressed: () => _restrict(context, a),
                          child: Text(a.restricted
                              ? tr3('解除限制', 'Шектеуді алу', 'Снять ограничение')
                              : tr3('限制账号', 'Аккаунтты шектеу', 'Ограничить аккаунт'))),
                    if (_may(context, AdminPerms.team) && !a.restricted)
                      OutlinedButton(
                          onPressed: () => _role(context, a),
                          child: Text(tr3('设置后台角色', 'Рөл тағайындау', 'Назначить роль'))),
                    if (_may(context, AdminPerms.moderate) && a.role == null)
                      OutlinedButton(
                          onPressed: () => _ban(context, a, d.banned),
                          child: Text(d.banned
                              ? tr3('解封', 'Бұғаттан шығару', 'Разблокировать')
                              : tr3('封禁', 'Бұғаттау', 'Заблокировать'))),
                    if (_may(context, AdminPerms.team) && a.role == null)
                      OutlinedButton(
                          onPressed: () => _delete(context, a),
                          child: Text(tr3('注销账号', 'Аккаунтты жою', 'Удалить аккаунт'),
                              style: TextStyle(color: t.crit))),
                  ]),
                ],
                const SizedBox(height: YSpace.lg),
                Text(
                    tr3(
                        '报价/报名 ${d.applications} 次 · 举报他人 ${d.reportsFiled} 次',
                        'Өтінім: ${d.applications} · Берген шағымы: ${d.reportsFiled}',
                        'Откликов: ${d.applications} · Подано жалоб: ${d.reportsFiled}'),
                    style: YText.caption.copyWith(color: t.muted)),
                if (d.profiles.isNotEmpty) ...[
                  SectionTitle(tr3('名片', 'Профильдер', 'Профили')),
                  for (final p in d.profiles)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name),
                        subtitle: Text([
                          p.status == ProfileStatus.hidden
                              ? tr3('隐藏', 'Жасырын', 'Скрыт')
                              : tr3('公开', 'Жария', 'Опубликован'),
                          if (p.verified) tr3('已核验', 'расталған', 'проверен'),
                        ].join(' · ')),
                        onTap: () =>
                            pushPage<void>(context, (_) => ProfilePage(profileId: p.id)),
                        trailing: _may(context, AdminPerms.moderate) &&
                                p.status != ProfileStatus.hidden
                            ? TextButton(
                                onPressed: () => _takeDown(context, 'profile', p.id),
                                child: Text(tr3('下架', 'Алу', 'Снять')))
                            : null),
                ],
                if (d.posts.isNotEmpty) ...[
                  SectionTitle(tr3('房子', 'Үйлер', 'Дома')),
                  for (final p in d.posts)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.title),
                        subtitle: Text([
                          p.hidden
                              ? tr3('已隐藏', 'Жасырылған', 'Скрыт')
                              : tr3('公开', 'Жария', 'Опубликован'),
                          if (p.featured) tr3('精选', 'Таңдаулы', 'В подборке'),
                          if (_may(context, AdminPerms.operate) && !p.hidden)
                            tr3('长按设精选', 'Ұзақ басып таңдау', 'Удерживайте для подборки'),
                        ].join(' · ')),
                        onLongPress: _may(context, AdminPerms.operate) &&
                                !p.hidden &&
                                _http(context) != null
                            ? () => attempt(
                                context, () => _http(context)!.setFeatured(p.id, !p.featured),
                                success: p.featured
                                    ? tr3('已取消精选', 'Таңдаулыдан алынды', 'Убрано из подборки')
                                    : tr3('已设为精选，排在首页最前', 'Басты бетте бірінші тұрады',
                                        'В подборке: первым на главной'))
                            : null,
                        onTap: () => pushPage<void>(context, (_) => PostPage(postId: p.id)),
                        trailing: _may(context, AdminPerms.moderate)
                            ? TextButton(
                                onPressed: () async {
                                  final note = p.hidden
                                      ? await askText(
                                          context,
                                          tr3('恢复说明', 'Қайтару түсініктемесі',
                                              'Пояснение к восстановлению'))
                                      : await _pickReason(context,
                                          tr3('隐藏原因', 'Жасыру себебі', 'Причина скрытия'));
                                  if (note == null || !context.mounted) return;
                                  await attempt(context,
                                      () => context.repos.setPostHidden(p.id, !p.hidden, note));
                                },
                                child: Text(p.hidden
                                    ? tr3('恢复', 'Қайтару', 'Вернуть')
                                    : tr3('隐藏', 'Жасыру', 'Скрыть')))
                            : null),
                ],
                if (d.demands.isNotEmpty) ...[
                  SectionTitle(tr3('需求', 'Тапсырыстар', 'Заявки')),
                  for (final x in d.demands) ...[
                    _DemandCard(
                        demand: x,
                        onTap: () =>
                            pushPage<void>(context, (_) => DemandDetailPage(demandId: x.id))),
                    if (_may(context, AdminPerms.moderate) &&
                        const [DemandStatus.pendingReview, DemandStatus.open, DemandStatus.paused]
                            .contains(x.status))
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: () => _takeDown(context, 'demand', x.id),
                              child: Text(tr3('下架这个需求', 'Тапсырысты алу', 'Снять заявку')))),
                  ],
                ],
                if (d.cooperations.isNotEmpty) ...[
                  SectionTitle(tr3('合作 ${d.cooperations.length}',
                      'Келісімдер: ${d.cooperations.length}', 'Сделки: ${d.cooperations.length}')),
                  for (final c in d.cooperations)
                    Text(
                        [
                          _date(c.createdAt),
                          c.status.name,
                          if (c.endRequest?.dispute != null)
                            tr3(
                                '争议：${c.endRequest!.dispute}',
                                'Дау: ${c.endRequest!.dispute}',
                                'Спор: ${c.endRequest!.dispute}'),
                        ].join(' · '),
                        style: YText.caption),
                ],
                if (d.reportsAbout.isNotEmpty) ...[
                  SectionTitle(tr3('被举报', 'Үстінен түскен шағымдар', 'Жалобы на аккаунт')),
                  for (final r in d.reportsAbout)
                    Text(
                        '${_date(r.createdAt)} · ${_reportTargetName(r.target)} · ${_reasonLabel(r.reason)} · ${_reportStatusName(r.status)}',
                        style: YText.caption),
                ],
                if (d.appeals.isNotEmpty) ...[
                  SectionTitle(tr3('申诉', 'Апелляциялар', 'Апелляции')),
                  for (final x in d.appeals)
                    Text('${_date(x.createdAt)} · ${_targetName(x.target)} · ${x.text}',
                        style: YText.caption),
                ],
                if (d.audit.isNotEmpty) ...[
                  SectionTitle(tr3('处理记录', 'Шешімдер тарихы', 'История решений')),
                  for (final e in d.audit) _AuditRow(e),
                ],
              ]);
            }));
  }
}

// ─────────────────────────── 更多 ───────────────────────────

class _MoreTab extends StatelessWidget {
  const _MoreTab();
  @override
  Widget build(BuildContext context) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: YSpace.gutter),
          children: [
            SettingsGroup(title: tr3('内容', 'Мазмұн', 'Контент'), children: [
              SettingsRow(
                  icon: Icons.list_alt,
                  title: tr3('全部需求', 'Барлық тапсырыстар', 'Все заявки'),
                  subtitle: tr3(
                      '按状态筛选、搜索标题，可下架已公开的需求',
                      'Күйі бойынша сүзу, атауынан іздеу, жарияланған тапсырысты алып тастау',
                      'Фильтр по статусу, поиск по названию, снятие опубликованных заявок'),
                  onTap: () => pushPage<void>(context, (_) => const _AllDemandsPage())),
            ]),
            SettingsGroup(
                title: tr3('团队与记录', 'Команда және журнал', 'Команда и журнал'),
                children: [
              SettingsRow(
                  icon: Icons.badge_outlined,
                  title: _teamTitle,
                  onTap: () => pushPage<void>(context, (_) => const _TeamPage())),
              SettingsRow(
                  icon: Icons.history,
                  title: tr3('操作记录', 'Әрекеттер журналы', 'Журнал действий'),
                  subtitle: tr3('每一个决定：谁、何时、为什么', 'Әр шешім: кім, қашан, не үшін',
                      'Каждое решение: кто, когда и почему'),
                  onTap: () => pushPage<void>(context, (_) => const AuditPage())),
            ]),
            SettingsGroup(title: tr3('用户与数据', 'Қолданушылар мен деректер', 'Пользователи и данные'), children: [
              SettingsRow(
                  key: const Key('admin-feedback'),
                  icon: Icons.mark_email_unread_outlined,
                  title: tr3('用户反馈', 'Пікірлер', 'Обратная связь'),
                  onTap: () => pushPage<void>(context, (_) => const FeedbackInboxPage())),
              SettingsRow(
                  key: const Key('admin-trends'),
                  icon: Icons.insights_outlined,
                  title: tr3('近 30 天趋势', 'Соңғы 30 күн', 'Динамика за 30 дней'),
                  onTap: () => pushPage<void>(context, (_) => const TrendsPage())),
              if (_may(context, AdminPerms.team)) ...[
                SettingsRow(
                    icon: Icons.file_download_outlined,
                    title: tr3('导出用户表', 'Қолданушыларды экспорттау', 'Экспорт пользователей'),
                    onTap: () => _export(context, 'users')),
                SettingsRow(
                    icon: Icons.file_download_outlined,
                    title: tr3('导出需求表', 'Тапсырыстарды экспорттау', 'Экспорт заявок'),
                    onTap: () => _export(context, 'demands')),
              ],
            ]),
            SettingsGroup(title: tr3('运营', 'Операциялар', 'Операции'), children: [
              if (_may(context, AdminPerms.operate))
                SettingsRow(
                    key: const Key('admin-broadcast'),
                    icon: Icons.campaign_outlined,
                    title: tr3('群发通知', 'Жаппай хабарландыру', 'Рассылка'),
                    subtitle: tr3('推送到所有用户的手机', 'Барлық телефонға', 'На все телефоны'),
                    onTap: () => pushPage<void>(context, (_) => const BroadcastPage())),
              SettingsRow(
                  key: const Key('admin-banned-words'),
                  icon: Icons.block_outlined,
                  title: tr3('违禁词', 'Тыйым сөздер', 'Запрещённые слова'),
                  onTap: () => pushPage<void>(context, (_) => const BannedWordsPage())),
            ]),
            SettingsGroup(title: tr3('推送', 'Хабарландырулар', 'Уведомления'), children: [
              SettingsRow(
                  icon: Icons.notifications_paused_outlined,
                  title: _pushTitle,
                  subtitle: tr3('平台免打扰时段与每人每日上限',
                      '«Мазаламау» уақыты және бір адамға күндік шек',
                      'Тихие часы и дневной лимит на человека'),
                  onTap: () => pushPage<void>(context, (_) => const _PushPolicyPage())),
            ]),
          ]);
}

class _AllDemandsPage extends StatefulWidget {
  const _AllDemandsPage();
  @override
  State<_AllDemandsPage> createState() => _AllDemandsPageState();
}

class _AllDemandsPageState extends State<_AllDemandsPage> with _Search {
  DemandStatus? _status = DemandStatus.open;

  @override
  Widget build(BuildContext context) {
    final canModerate = _may(context, AdminPerms.moderate);
    return Scaffold(
        appBar: AppBar(
            title: Text(tr3('全部需求', 'Барлық тапсырыстар', 'Все заявки'))),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(YSpace.gutter, YSpace.sm, YSpace.gutter, 0),
              child: SearchField(
                  controller: search,
                  hint: tr3('搜索标题', 'Атауы бойынша іздеу', 'Поиск по названию'),
                  onChanged: typed)),
          _Chips<DemandStatus?>(
              options: [
                for (final s in const [
                  DemandStatus.open,
                  DemandStatus.pendingReview,
                  DemandStatus.paused,
                  DemandStatus.rejected,
                  DemandStatus.found,
                  DemandStatus.expired,
                  DemandStatus.closed,
                ])
                  (s, demandStatusName(s)),
                (null, _all),
              ],
              selected: _status,
              onSelect: (v) => setState(() => _status = v)),
          Expanded(
              child: _PagedList<Demand>(
                  key: ValueKey('all-$_status-$_q'),
                  load: (p) => context.repos.adminDemands(status: _status, query: _q, page: p),
                  empty: tr3('没有需求', 'Тапсырыс жоқ', 'Заявок нет'),
                  item: (context, d) => _DemandCard(
                      demand: d,
                      onTap: () =>
                          pushPage<void>(context, (_) => DemandDetailPage(demandId: d.id)),
                      onLongPress: canModerate &&
                              (d.status == DemandStatus.open || d.status == DemandStatus.paused)
                          ? () async {
                              final r = await _pickReason(context,
                                  tr3('下架原因', 'Алып тастау себебі', 'Причина снятия'));
                              if (r == null || !context.mounted) return;
                              await attempt(context, () => context.repos.reject(d.id, r),
                                  success: tr3('已下架', 'Алып тасталды', 'Снято'));
                            }
                          : null))),
        ]));
  }
}

class _TeamPage extends StatelessWidget {
  const _TeamPage();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_teamTitle)),
      body: Live<List<AdminUserRow>>(
          load: (r) => r.team(),
          builder: (context, list) => ListView(padding: const EdgeInsets.all(YSpace.gutter), children: [
                Text(
                    tr3(
                        '超级管理员：全部权限，管理团队；审核员：审核需求、处理举报申诉与认证、限制账号；运营：推送节制；只读：只能查看。角色在“用户”里点开账号设置，不能改自己的角色。',
                        'Бас әкімші: барлық құқық, команданы басқарады. Модератор: тапсырыстарды тексереді, шағымдарды, апелляцияларды және растауды қарайды, аккаунттарды шектейді. Оператор: хабарландыру шектеулері. Тек оқу: тек қарай алады. Рөл «Қолданушылар» қойындысында аккаунтты ашып тағайындалады; өз рөліңізді өзгерте алмайсыз.',
                        'Суперадмин: все права, управляет командой. Модератор: проверяет заявки, разбирает жалобы, апелляции и верификацию, ограничивает аккаунты. Оператор: ограничения уведомлений. Только чтение: только просмотр. Роль назначается на вкладке «Пользователи» в карточке аккаунта; свою роль изменить нельзя.'),
                    style: YText.caption.copyWith(color: YTokens.of(context).muted)),
                const SizedBox(height: YSpace.md),
                for (final u in list)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(u.name.isEmpty ? '?' : u.name, size: 40),
                      title: Text(u.name),
                      subtitle: Text(u.email),
                      trailing: StatusPill(roleName(u.role)),
                      onTap: () => pushPage<void>(
                          context, (_) => AccountDetailPage(accountId: u.id))),
              ])));
}

class _AuditRow extends StatelessWidget {
  const _AuditRow(this.e);
  final AuditEntry e;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${_actionName(e.action)}${e.target.isEmpty ? '' : ' · ${_targetName(e.target)}'}${e.title.isEmpty ? '' : tr3('「${e.title}」', ' «${e.title}»', ' «${e.title}»')}',
              style: YText.body),
          Text(
              '${e.by.isEmpty || e.by == 'system' ? tr3('自动审核', 'Автоматты тексеру', 'Автопроверка') : (e.byName.isEmpty ? e.by : e.byName)} · ${_date(e.at)}${e.reason.isEmpty ? '' : ' · ${_reasonLabel(e.reason)}'}',
              style: YText.caption.copyWith(color: t.muted)),
        ]));
  }
}

/// The audit log: every decision with who, when and why.
class AuditPage extends StatelessWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(tr3('操作记录', 'Әрекеттер журналы', 'Журнал действий'))),
      body: _PagedList<AuditEntry>(
          key: const ValueKey('audit'),
          load: (p) => context.repos.audit(page: p),
          empty: tr3('还没有记录', 'Әзірге жазба жоқ', 'Записей пока нет'),
          item: (context, e) => _AuditRow(e)));
}

class _PushPolicyPage extends StatefulWidget {
  const _PushPolicyPage();
  @override
  State<_PushPolicyPage> createState() => _PushPolicyPageState();
}

class _PushPolicyPageState extends State<_PushPolicyPage> {
  static const _hours = ['', '20:00', '21:00', '22:00', '23:00', '00:00'];
  static const _ends = ['', '06:00', '07:00', '08:00', '09:00'];

  static String get _noQuiet => tr3('不限制', 'Шектеусіз', 'Не ограничено');
  static String _cap(int n) => n == 0
      ? tr3('不限', 'Шексіз', 'Без лимита')
      : tr3('$n 条', 'Күніне $n', '$n в день');

  Future<void> _save(PushPolicy p) =>
      attempt(context, () => context.repos.savePushPolicy(p),
          success: tr3('已保存', 'Сақталды', 'Сохранено'));

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canOperate = _may(context, AdminPerms.operate);
    final quietStart =
        tr3('免打扰开始', '«Мазаламау» басталуы', 'Начало тихих часов');
    final quietEnd = tr3('免打扰结束', '«Мазаламау» аяқталуы', 'Конец тихих часов');
    final dailyCap =
        tr3('每人每日上限', 'Бір адамға күндік шек', 'Дневной лимит на человека');
    return Scaffold(
        appBar: AppBar(title: Text(_pushTitle)),
        body: Live<PushPolicy>(
            load: (r) => r.pushPolicy(),
            builder: (context, p) => ListView(
                    padding: const EdgeInsets.symmetric(horizontal: YSpace.gutter),
                    children: [
                      SettingsGroup(children: [
                        SettingsRow(
                            icon: Icons.bedtime_outlined,
                            title: quietStart,
                            value: p.quietStart.isEmpty ? _noQuiet : p.quietStart,
                            onTap: canOperate
                                ? () async {
                                    final v = await pickOne<String>(context, quietStart,
                                        [for (final h in _hours) (h, h.isEmpty ? _noQuiet : h)],
                                        selected: p.quietStart);
                                    if (v != null)
                                      await _save(PushPolicy(
                                          quietStart: v,
                                          quietEnd: v.isEmpty ? '' : (p.quietEnd.isEmpty ? '08:00' : p.quietEnd),
                                          dailyCap: p.dailyCap));
                                  }
                                : null),
                        SettingsRow(
                            icon: Icons.wb_sunny_outlined,
                            title: quietEnd,
                            value: p.quietEnd.isEmpty ? _noQuiet : p.quietEnd,
                            onTap: canOperate && p.quietStart.isNotEmpty
                                ? () async {
                                    final v = await pickOne<String>(context, quietEnd,
                                        [for (final h in _ends.skip(1)) (h, h)],
                                        selected: p.quietEnd);
                                    if (v != null)
                                      await _save(PushPolicy(
                                          quietStart: p.quietStart, quietEnd: v, dailyCap: p.dailyCap));
                                  }
                                : null),
                        SettingsRow(
                            icon: Icons.speed,
                            title: dailyCap,
                            value: _cap(p.dailyCap),
                            onTap: canOperate
                                ? () async {
                                    final v = await pickOne<int>(context, dailyCap, [
                                      for (final n in const [3, 5, 10, 20, 0])
                                        (n, _cap(n)),
                                    ], selected: p.dailyCap);
                                    if (v != null)
                                      await _save(PushPolicy(
                                          quietStart: p.quietStart, quietEnd: p.quietEnd, dailyCap: v));
                                  }
                                : null),
                      ]),
                      Padding(
                          padding: const EdgeInsets.all(YSpace.sm),
                          child: Text(
                              tr3('只限制点赞、点评和新需求提醒；报名、合作、验收等交易通知总会推送。时间按 UTC+5。消息列表不受影响。',
                                      'Тек ұнату, пікір және жаңа тапсырыс туралы хабарландырулар шектеледі; өтінім, келісім, қабылдау сияқты мәміле хабарландырулары әрдайым жіберіледі. Уақыт UTC+5 бойынша. Хабарлар тізіміне әсер етпейді.',
                                      'Ограничиваются только уведомления о лайках, отзывах и новых заявках; уведомления по сделкам (отклики, соглашения, приёмка) приходят всегда. Время по UTC+5. На список сообщений не влияет.') +
                                  (canOperate
                                      ? ''
                                      : tr3(
                                          '\n只有运营或超级管理员可以修改。',
                                          '\nТек оператор не бас әкімші өзгерте алады.',
                                          '\nМенять может только оператор или суперадмин.')),
                              style: YText.caption.copyWith(color: t.muted))),
                    ])));
  }
}
