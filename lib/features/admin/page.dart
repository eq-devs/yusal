import 'dart:async';
import 'package:yusal/features/admin/repository/admin_repository.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/admin/state/admin.dart';
import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart'
    show costUnits, defaultLabour, defaultPrices;
import 'package:yusal/features/editor/engine/core/document/house_document.dart'
    show Currency, MasonryUnit;
import 'package:yusal/features/editor/engine/render2d/planning_names.dart'
    show
        costLineName,
        masonryUnitName,
        priceRegionName,
        priceSourceName,
        unitName;
import 'package:yusal/features/editor/repository/price_repository.dart'
    show priceRegions;
import 'package:yusal/features/shared/model/admin_models.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/features/demand/page.dart';
import 'package:yusal/features/home/pages/post.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/profile/page.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';

part 'pages/console.dart';

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
        final me = context.session.currentAccount;
        if (me == null || !me.can(AdminPerms.read)) {
          // The role went away (revoked, signed out): close the console.
          return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                  icon: Icons.lock_outline,
                  title: tr3('没有后台权限', 'Әкімшілікке рұқсат жоқ',
                      'Нет доступа к админке',
                      'No access to admin', ky: 'Администраторлук бөлүмгө кирүү укугу жок', uz: 'Admin boʻlimiga kirish huquqi yoʻq')));
        }
        final tabs = [
          tr3('工作台', 'Шолу', 'Сводка', 'Overview', ky: 'Сереп', uz: 'Umumiy koʻrinish'),
          tr3('审核', 'Тексеру', 'Проверка', 'Review', ky: 'Карап чыгуу', uz: 'Koʻrib chiqish'),
          tr3('用户', 'Қолданушылар', 'Пользователи', 'Users', ky: 'Колдонуучулар', uz: 'Foydalanuvchilar'),
          tr3('更多', 'Тағы', 'Ещё', 'More', ky: 'Дагы', uz: 'Yana'),
        ];
        final pages = [
          _Workbench(open: _open),
          _ReviewTab(kind: _reviewKind),
          const _UsersTab(),
          const _MoreTab(),
        ];
        return Scaffold(
            appBar: AppBar(title: Text(tabs[_tab]), actions: [
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
                      icon: const Icon(Icons.dashboard_outlined),
                      label: tabs[0]),
                  NavigationDestination(
                      icon: const Icon(Icons.fact_check_outlined),
                      label: tabs[1]),
                  NavigationDestination(
                      icon: const Icon(Icons.people_outline), label: tabs[2]),
                  NavigationDestination(
                      icon: const Icon(Icons.more_horiz), label: tabs[3]),
                ]));
      });
}

String roleName(String? role) => switch (role) {
      AdminRoles.superadmin => tr3('超级管理员', 'Бас әкімші', 'Суперадмин', 'Super admin', ky: 'Супер админ', uz: 'Super admin'),
      AdminRoles.moderator => tr3('审核员', 'Модератор', 'Модератор', 'Moderator', ky: 'Модератор', uz: 'Moderator'),
      AdminRoles.operator => tr3('运营', 'Оператор', 'Оператор', 'Operator', ky: 'Оператор', uz: 'Operator'),
      AdminRoles.viewer => tr3('只读', 'Тек оқу', 'Только чтение', 'Read only', ky: 'Окуу гана', uz: 'Faqat oʻqish'),
      _ => tr3('无', 'Жоқ', 'Нет', 'None', ky: 'Жок', uz: 'Yoʻq'),
    };

bool _may(BuildContext context, String perm) =>
    context.session.currentAccount?.can(perm) ?? false;

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
      ReportStatus.open => tr3('待处理', 'Күтуде', 'Ожидает', 'Pending', ky: 'Күтүүдө', uz: 'Kutilmoqda'),
      ReportStatus.upheld => tr3('成立', 'Расталды', 'Подтверждена', 'Upheld', ky: 'Канааттандырылды', uz: 'Qanoatlantirildi'),
      ReportStatus.dismissed => tr3('驳回', 'Қабылданбады', 'Отклонена', 'Rejected', ky: 'Четке кагылды', uz: 'Rad etildi'),
    };

String get _all => tr3('全部', 'Барлығы', 'Все', 'All', ky: 'Баары', uz: 'Hammasi');
String get _userSees => tr3('用户会看到这段说明', 'Бұл түсініктемені пайдаланушы көреді',
    'Это пояснение увидит пользователь',
    'The user will see this explanation', ky: 'Колдонуучу бул түшүндүрмөнү көрөт', uz: 'Foydalanuvchi bu izohni koʻradi');
String get _restrictedPill => tr3('受限', 'Шектелген', 'Ограничен', 'Restricted', ky: 'Чектелген', uz: 'Cheklangan');
String get _unnamed => tr3('（未命名）', '(атаусыз)', '(без имени)', '(no name)', ky: '(аты жок)', uz: '(nomsiz)');
String get _approveWord => tr3('通过', 'Мақұлдау', 'Одобрить', 'Approve', ky: 'Бекитүү', uz: 'Tasdiqlash');
String get _dismissWord => tr3('驳回', 'Қабылдамау', 'Отклонить', 'Reject', ky: 'Четке кагуу', uz: 'Rad etish');
String get _teamTitle => tr3('后台成员', 'Команда', 'Команда', 'Team', ky: 'Команда', uz: 'Jamoa');
String get _pushTitle =>
    tr3('推送节制', 'Хабарландыру шектеулері', 'Ограничения уведомлений', 'Notification limits', ky: 'Билдирүү чектөөлөрү', uz: 'Bildirishnoma cheklovlari');
String _registered(DateTime t) =>
    tr3('注册 ${_date(t)}', 'Тіркелген: ${_date(t)}', 'Регистрация: ${_date(t)}', 'Joined: ${_date(t)}', ky: 'Кошулган: ${_date(t)}', uz: 'Qoʻshilgan: ${_date(t)}');

String _targetName(String t) => switch (t) {
      'demand' => tr3('需求', 'Тапсырыс', 'Заявка', 'Request', ky: 'Суроо-талап', uz: 'Soʻrov'),
      'profile' => tr3('名片', 'Профиль', 'Профиль', 'Profile', ky: 'Профиль', uz: 'Profil'),
      'account' => tr3('账号', 'Аккаунт', 'Аккаунт', 'Account', ky: 'Аккаунт', uz: 'Akkaunt'),
      'message' => tr3('消息', 'Хабар', 'Сообщение', 'Message', ky: 'Билдирүү', uz: 'Xabar'),
      'post' => tr3('房子', 'Үй', 'Дом', 'House', ky: 'Үй', uz: 'Uy'),
      'comment' => tr3('评论', 'Пікір', 'Комментарий', 'Comment', ky: 'Комментарий', uz: 'Izoh'),
      'platform' => tr3('全平台', 'Бүкіл платформа', 'Вся платформа', 'Whole platform', ky: 'Бүт платформа', uz: 'Butun platforma'),
      _ => t,
    };

/// A reason as moderators read it: preset codes as short labels.
String _reasonLabel(String r) => switch (r) {
      'code:contact' => tr3('含联系方式', 'Байланыс деректері бар', 'Есть контакты', 'Contains contacts', ky: 'Байланыштар камтылган', uz: 'Kontaktlar bor'),
      'code:fake' => tr3('虚假信息', 'Жалған ақпарат', 'Недостоверные сведения', 'False information', ky: 'Жалган маалымат', uz: 'Yolgʻon maʼlumot'),
      'code:illegal' =>
        tr3('违规内容', 'Ережеге қайшы мазмұн', 'Запрещённое содержание', 'Prohibited content', ky: 'Тыюу салынган мазмун', uz: 'Taqiqlangan kontent'),
      'code:incomplete' => tr3('信息不全', 'Ақпарат толық емес', 'Неполные данные', 'Incomplete details', ky: 'Толук эмес маалымат', uz: 'Toʻliq boʻlmagan maʼlumot'),
      'code:duplicate' =>
        tr3('重复发布', 'Қайталанған жарияланым', 'Повторная публикация', 'Duplicate post', ky: 'Кайталанган жарыя', uz: 'Takroriy eʼlon'),
      'code:abuse' =>
        tr3('辱骂骚扰', 'Балағат не қудалау', 'Оскорбления, преследование', 'Abuse or harassment', ky: 'Кордоо же куугунтук', uz: 'Haqorat yoki taʼqib'),
      'code:spam' => tr3('广告引流', 'Жарнама не спам', 'Реклама или спам', 'Advertising or spam', ky: 'Жарнама же спам', uz: 'Reklama yoki spam'),
      'code:ok' => tr3('未发现问题', 'Бұзушылық табылмады', 'Нарушений не найдено', 'No violation found', ky: 'Бузуу табылган жок', uz: 'Qoidabuzarlik topilmadi'),
      _ when r.startsWith('banned:') => tr3(
          '命中禁用词：${r.substring(7)}',
          'Тыйым салынған сөз: ${r.substring(7)}',
          'Запрещённое слово: ${r.substring(7)}',
          'Banned word: ${r.substring(7)}', ky: 'Тыюу салынган сөз: ${r.substring(7)}', uz: 'Taqiqlangan soʻz: ${r.substring(7)}'),
      _ => r,
    };

String _actionName(String a) => switch (a) {
      'approve' => tr3('通过需求', 'Тапсырыс мақұлданды', 'Заявка одобрена', 'Request approved', ky: 'Суроо-талап бекитилди', uz: 'Soʻrov tasdiqlandi'),
      'reject' => tr3('拒绝需求', 'Тапсырыс қабылданбады', 'Заявка отклонена', 'Request rejected', ky: 'Суроо-талап четке кагылды', uz: 'Soʻrov rad etildi'),
      'uphold' => tr3('举报成立', 'Шағым расталды', 'Жалоба подтверждена', 'Report upheld', ky: 'Арыз канааттандырылды', uz: 'Shikoyat qanoatlantirildi'),
      'dismiss' => tr3('驳回举报', 'Шағым қабылданбады', 'Жалоба отклонена', 'Report rejected', ky: 'Арыз четке кагылды', uz: 'Shikoyat rad etildi'),
      'restrict' => tr3('限制账号', 'Аккаунт шектелді', 'Аккаунт ограничен', 'Account restricted', ky: 'Аккаунт чектелди', uz: 'Akkaunt cheklandi'),
      'unrestrict' => tr3('解除限制', 'Шектеу алынды', 'Ограничение снято', 'Restriction lifted', ky: 'Чектөө алынды', uz: 'Cheklov olib tashlandi'),
      'post_hide' => tr3('隐藏房子', 'Үй жасырылды', 'Дом скрыт', 'House hidden', ky: 'Үй жашырылды', uz: 'Uy yashirildi'),
      'post_show' => tr3('恢复房子', 'Үй қайтарылды', 'Дом восстановлен', 'House restored', ky: 'Үй калыбына келтирилди', uz: 'Uy tiklandi'),
      'appeal_accept' =>
        tr3('申诉成立', 'Апелляция қанағаттандырылды', 'Апелляция удовлетворена', 'Appeal granted', ky: 'Даттануу канааттандырылды', uz: 'Apellyatsiya qanoatlantirildi'),
      'appeal_reject' =>
        tr3('申诉驳回', 'Апелляция қабылданбады', 'Апелляция отклонена', 'Appeal rejected', ky: 'Даттануу четке кагылды', uz: 'Apellyatsiya rad etildi'),
      'verify_approve' =>
        tr3('认证通过', 'Растау мақұлданды', 'Верификация одобрена', 'Verification approved', ky: 'Текшерүү бекитилди', uz: 'Tekshiruv tasdiqlandi'),
      'verify_reject' =>
        tr3('认证驳回', 'Растау қабылданбады', 'Верификация отклонена', 'Verification rejected', ky: 'Текшерүү четке кагылды', uz: 'Tekshiruv rad etildi'),
      'role_revoke' => tr3('撤销角色', 'Рөл алынды', 'Роль снята', 'Role removed', ky: 'Роль алынды', uz: 'Rol olib tashlandi'),
      'push_policy' => tr3('修改推送节制', 'Хабарландыру шектеулері өзгертілді',
          'Изменены ограничения уведомлений',
          'Notification limits changed', ky: 'Билдирүү чектөөлөрү өзгөртүлдү', uz: 'Bildirishnoma cheklovlari oʻzgartirildi'),
      _ when a.startsWith('role_grant:') => tr3(
          '授予${roleName(a.substring(11))}',
          'Рөл берілді: ${roleName(a.substring(11))}',
          'Назначена роль: ${roleName(a.substring(11))}',
          'Role assigned: ${roleName(a.substring(11))}', ky: 'Роль берилди: ${roleName(a.substring(11))}', uz: 'Rol berildi: ${roleName(a.substring(11))}'),
      _ => a,
    };

/// Picks a preset reason or takes the moderator's own words.
Future<String?> _pickReason(BuildContext context, String title,
    {List<String> codes = const [
      'contact',
      'fake',
      'illegal',
      'incomplete',
      'duplicate',
      'abuse',
      'spam'
    ]}) async {
  final v = await pickOne<String>(context, title, [
    for (final c in codes) ('code:$c', _reasonLabel('code:$c')),
    ('', tr3('自己填写…', 'Өзім жазамын…', 'Свой текст…', 'Custom text…', ky: 'Өз текстиңиз…', uz: 'Oʻz matningiz…')),
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
  late final _provider =
      pagedListProvider<T>((p) => widget.load(p), () => _pages);

  void _more() {
    _pages++;
    ProviderScope.containerOf(context, listen: false).invalidate(_provider);
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: _refresh.call,
      child: Live<(List<T>, bool)>(
          refresh: _refresh,
          provider: _provider,
          builder: (context, data) {
            final (items, more) = data;
            return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (more &&
                      n.metrics.extentAfter < 400 &&
                      n is ScrollEndNotification) {
                    _more();
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
                        EmptyState(
                            icon: Icons.inbox_outlined, title: widget.empty),
                      for (final x in items) widget.item(context, x),
                      if (more)
                        Center(
                            child: TextButton(
                                onPressed: _more,
                                child: Text(tr3(
                                    '加载更多', 'Тағы жүктеу', 'Показать ещё', 'Show more', ky: 'Дагы көрсөтүү', uz: 'Yana koʻrsatish')))),
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
      padding: const EdgeInsets.symmetric(
          horizontal: YSpace.gutter, vertical: YSpace.sm),
      child: Row(children: [
        for (final (v, label) in options)
          Padding(
              padding: const EdgeInsets.only(right: YSpace.sm),
              child: FilterPill(
                  label: label,
                  selected: v == selected,
                  onTap: () => onSelect(v))),
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
            provider: adminWorkbenchProvider,
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
                                    'Фоновая задача не запускалась больше 5 минут: истечение сроков, напоминания и одностороннее завершение остановлены. Проверьте сервер.',
                                    "The background job hasn't run for over 5 minutes: expiries, reminders and one-sided completion are stopped. Check the server.", ky: 'Фондук иш 5 мүнөттөн ашык иштеген жок: мөөнөттөрдүн бүтүшү, эскертүүлөр жана бир тараптуу бүтүрүү токтоп турат. Серверди текшериңиз.', uz: 'Fon vazifasi 5 daqiqadan ortiq ishlamadi: muddat tugashi, eslatmalar va bir tomonlama yakunlash toʻxtagan. Serverni tekshiring.'),
                                'manual_review_on' => tr3(
                                    '已开启人工审核：新需求要等审核员通过才会公开。',
                                    'Қолмен тексеру қосулы: жаңа тапсырыстар модератор мақұлдағаннан кейін ғана жарияланады.',
                                    'Включена ручная проверка: новые заявки публикуются только после одобрения модератором.',
                                    'Manual review is on: new requests are published only after a moderator approves them.', ky: 'Кол менен текшерүү күйгүзүлгөн: жаңы суроо-талаптар модератор бекиткенден кийин гана жарыяланат.', uz: 'Qoʻlda tekshirish yoqilgan: yangi soʻrovlar faqat moderator tasdiqlagandan keyin eʼlon qilinadi.'),
                                _ => h,
                              },
                              warn: h != 'manual_review_on')),
                    Text(
                        todo.total == 0
                            ? tr3(
                                '没有待办，一切正常',
                                'Күтіп тұрған іс жоқ, бәрі дұрыс',
                                'Задач нет, всё в порядке',
                                'No tasks, all good', ky: 'Тапшырма жок, баары жакшы', uz: 'Vazifa yoʻq, hammasi joyida')
                            : tr3(
                                '待办 ${todo.total} 项',
                                'Күтіп тұрған іс: ${todo.total}',
                                'Задач: ${todo.total}',
                                'Tasks: ${todo.total}', ky: 'Тапшырмалар: ${todo.total}', uz: 'Vazifalar: ${todo.total}'),
                        style: display(size: 22)),
                    const SizedBox(height: YSpace.md),
                    _TodoTile(
                        icon: Icons.fact_check_outlined,
                        title: tr3(
                            '需求审核', 'Тапсырыстарды тексеру', 'Проверка заявок', 'Request review', ky: 'Суроо-талаптарды текшерүү', uz: 'Soʻrovlarni tekshirish'),
                        count: todo.review.count,
                        lines: [
                          for (final x in todo.review.items) x.current.title
                        ],
                        onTap: () => open(_Review.demands)),
                    _TodoTile(
                        icon: Icons.flag_outlined,
                        title: tr3('举报', 'Шағымдар', 'Жалобы', 'Reports', ky: 'Арыздар', uz: 'Shikoyatlar'),
                        count: todo.reports.count,
                        lines: [
                          for (final x in todo.reports.items)
                            '${_reportTargetName(x.target)} · ${_reasonLabel(x.reason)}'
                        ],
                        onTap: () => open(_Review.reports)),
                    _TodoTile(
                        icon: Icons.gavel_outlined,
                        title: tr3('申诉', 'Апелляциялар', 'Апелляции', 'Appeals', ky: 'Даттануулар', uz: 'Apellyatsiyalar'),
                        count: todo.appeals.count,
                        lines: [for (final x in todo.appeals.items) x.text],
                        onTap: () => open(_Review.appeals)),
                    _TodoTile(
                        icon: Icons.verified_outlined,
                        title: tr3('工人认证', 'Шеберлерді растау',
                            'Верификация мастеров',
                            'Pro verification', ky: 'Адисти текшерүү', uz: 'Mutaxassisni tekshirish'),
                        count: todo.verifications.count,
                        lines: [
                          for (final x in todo.verifications.items) x.name
                        ],
                        onTap: () => open(_Review.verifications)),
                    _TodoTile(
                        icon: Icons.report_problem_outlined,
                        title: tr3(
                            '超过 3 天未解决的争议',
                            '3 күннен астам шешілмеген даулар',
                            'Споры без решения дольше 3 дней',
                            'Disputes unresolved for over 3 days', ky: '3 күндөн ашык чечилбеген талаш-тартыштар', uz: '3 kundan ortiq hal qilinmagan nizolar'),
                        count: todo.disputes.count,
                        lines: [
                          for (final c in todo.disputes.items)
                            c.endRequest?.dispute ??
                                tr3(
                                    '节点验收有异议',
                                    'Кезеңді қабылдауға қарсылық бар',
                                    'Спор о приёмке этапа',
                                    'Stage acceptance dispute', ky: 'Этапты кабыл алуу боюнча талаш', uz: 'Bosqichni qabul qilish boʻyicha nizo')
                        ]),
                    const SizedBox(height: YSpace.xl),
                    Text(tr3('今天', 'Бүгін', 'Сегодня', 'Today', ky: 'Бүгүн', uz: 'Bugun'),
                        style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    Wrap(spacing: YSpace.sm, runSpacing: YSpace.sm, children: [
                      for (final (k, label) in [
                        (
                          'active',
                          tr3('活跃设备', 'Белсенді құрылғы', 'Активные устройства', 'Active devices', ky: 'Активдүү түзмөктөр', uz: 'Faol qurilmalar')
                        ),
                        (
                          'new_users',
                          tr3('新用户', 'Жаңа аккаунт', 'Новые аккаунты', 'New accounts', ky: 'Жаңы аккаунттар', uz: 'Yangi akkauntlar')
                        ),
                        ('new_posts', tr3('新房子', 'Жаңа үй', 'Новые дома', 'New houses', ky: 'Жаңы үйлөр', uz: 'Yangi uylar')),
                        (
                          'new_demands',
                          tr3('新需求', 'Жаңа тапсырыс', 'Новые заявки', 'New requests', ky: 'Жаңы суроо-талаптар', uz: 'Yangi soʻrovlar')
                        ),
                        (
                          'new_quotes',
                          tr3('新报价', 'Жаңа ұсыныс', 'Новые отклики', 'New responses', ky: 'Жаңы жооптор', uz: 'Yangi javoblar')
                        ),
                        (
                          'new_cooperations',
                          tr3('新合作', 'Жаңа келісім', 'Новые сделки', 'New deals', ky: 'Жаңы келишимдер', uz: 'Yangi bitimlar')
                        ),
                        (
                          'inspections',
                          tr3('节点验收', 'Кезең қабылдау', 'Приёмка этапов', 'Stage acceptances', ky: 'Этаптарды кабыл алуу', uz: 'Bosqichlarni qabul qilish')
                        ),
                      ])
                        _Stat(label, d.today[k] ?? 0),
                    ]),
                    const SizedBox(height: YSpace.xl),
                    Text(tr3('近 7 天', 'Соңғы 7 күн', 'За 7 дней', 'Last 7 days', ky: 'Акыркы 7 күн', uz: 'Soʻnggi 7 kun'),
                        style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    _Bars(days: d.daily),
                    const SizedBox(height: YSpace.xl),
                    Text(
                        tr3('从房子到验收', 'Үйден қабылдауға дейін',
                            'От дома до приёмки',
                            'From house to acceptance', ky: 'Үйдөн кабыл алууга чейин', uz: 'Uydan qabul qilishgacha'),
                        style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    _Funnel(steps: d.funnel),
                    if (d.firstQuoteHours != null) ...[
                      const SizedBox(height: YSpace.sm),
                      Text(
                          tr3(
                              '需求发布后收到第一个报价：中位 ${d.firstQuoteHours!.toStringAsFixed(1)} 小时',
                              'Тапсырыс жарияланғаннан алғашқы ұсынысқа дейін: медиана ${d.firstQuoteHours!.toStringAsFixed(1)} сағ',
                              'От публикации заявки до первого предложения: медиана ${d.firstQuoteHours!.toStringAsFixed(1)} ч',
                              'From posting a request to the first quote: median ${d.firstQuoteHours!.toStringAsFixed(1)} h', ky: 'Суроо-талап жарыялангандан биринчи сунушка чейин: медиана ${d.firstQuoteHours!.toStringAsFixed(1)} саат', uz: 'Soʻrov eʼlon qilinganidan birinchi taklifgacha: mediana ${d.firstQuoteHours!.toStringAsFixed(1)} soat'),
                          style: YText.caption.copyWith(color: t.muted)),
                    ],
                    const SizedBox(height: YSpace.xl),
                    Text(
                        tr3(
                            '各地区供需（招募中的需求 / 可接活的名片）',
                            'Аймақтар бойынша сұраныс пен ұсыныс (ашық тапсырыстар / бос профильдер)',
                            'Спрос и предложение по районам (открытые заявки / свободные профили)',
                            'Supply and demand by district (open requests / available profiles)', ky: 'Райондор боюнча сунуш жана суроо (ачык суроо-талаптар / жеткиликтүү профилдер)', uz: 'Tumanlar boʻyicha taklif va talab (ochiq soʻrovlar / mavjud profillar)'),
                        style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    YCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          if (d.regions.isEmpty)
                            Padding(
                                padding: const EdgeInsets.all(YSpace.lg),
                                child: Text(
                                    tr3('暂无数据', 'Дерек жоқ', 'Нет данных', 'No data', ky: 'Маалымат жок', uz: 'Maʼlumot yoʻq'))),
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
                            'Всего: аккаунты ${total('users')} · дома ${total('posts')} · профили ${total('profiles')} · заявки ${total('demands')}',
                            'Total: accounts ${total('users')} · houses ${total('posts')} · profiles ${total('profiles')} · requests ${total('demands')}', ky: 'Бардыгы: аккаунттар ${total('users')} · үйлөр ${total('posts')} · профилдер ${total('profiles')} · суроо-талаптар ${total('demands')}', uz: 'Jami: akkauntlar ${total('users')} · uylar ${total('posts')} · profillar ${total('profiles')} · soʻrovlar ${total('demands')}'),
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
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${d.demands}', style: YText.caption),
                          const SizedBox(height: 2),
                          Container(
                              height: 80 * d.demands / top + 2,
                              decoration: BoxDecoration(
                                  color: t.accent,
                                  borderRadius:
                                      BorderRadius.circular(YRadius.row))),
                          const SizedBox(height: 4),
                          Text(d.day.length >= 10 ? d.day.substring(5) : d.day,
                              style: YText.caption.copyWith(color: t.muted)),
                          Text(
                              tr3('活跃 ${d.active}', 'Белс. ${d.active}',
                                  'Акт. ${d.active}',
                                  'Active ${d.active}', ky: 'Активдүү ${d.active}', uz: 'Faol ${d.active}'),
                              style: YText.caption.copyWith(color: t.muted)),
                        ]))),
        ]));
  }
}

class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});
  final List<(String, int)> steps;
  static String _name(String k) => switch (k) {
        'posts' => tr3('公开的房子', 'Жария үйлер', 'Опубликованные дома', 'Published houses', ky: 'Жарыяланган үйлөр', uz: 'Eʼlon qilingan uylar'),
        'reuses' => tr3('被复用', 'Негізге алынды', 'Взято за основу', 'Used as a base', ky: 'Негиз катары колдонулду', uz: 'Asos sifatida ishlatilgan'),
        'demands' =>
          tr3('发布的需求', 'Жарияланған тапсырыстар', 'Опубликованные заявки', 'Published requests', ky: 'Жарыяланган суроо-талаптар', uz: 'Eʼlon qilingan soʻrovlar'),
        'quoted' =>
          tr3('收到报价的需求', 'Ұсыныс түскен тапсырыстар', 'Заявки с предложениями', 'Requests with quotes', ky: 'Сунуштары бар суроо-талаптар', uz: 'Takliflari bor soʻrovlar'),
        'cooperations' => tr3('达成合作', 'Келісімдер', 'Сделки', 'Deals', ky: 'Келишимдер', uz: 'Bitimlar'),
        'inspected' => tr3('有节点验收', 'Кезең қабылданған', 'С приёмкой этапов', 'With stage acceptance', ky: 'Этапты кабыл алуу менен', uz: 'Bosqichni qabul qilish bilan'),
        'reviews' => tr3('评价', 'Пікірлер', 'Отзывы', 'Reviews', ky: 'Пикирлер', uz: 'Sharhlar'),
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
                                  borderRadius:
                                      BorderRadius.circular(YRadius.row)))))),
              SizedBox(
                  width: 44,
                  child: Text('$n',
                      textAlign: TextAlign.end, style: YText.caption)),
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
            _Chips<_Review>(options: [
              (_Review.demands, tr3('需求', 'Тапсырыстар', 'Заявки', 'Requests', ky: 'Суроо-талаптар', uz: 'Soʻrovlar')),
              (_Review.reports, tr3('举报', 'Шағымдар', 'Жалобы', 'Reports', ky: 'Арыздар', uz: 'Shikoyatlar')),
              (_Review.appeals, tr3('申诉', 'Апелляциялар', 'Апелляции', 'Appeals', ky: 'Даттануулар', uz: 'Apellyatsiyalar')),
              (_Review.verifications, tr3('认证', 'Растау', 'Верификация', 'Verification', ky: 'Текшерүү', uz: 'Tekshiruv')),
            ], selected: k, onSelect: (v) => kind.value = v),
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

  /// Swiped away (approved or rejected): out of the list at once, before
  /// the queue is read again.
  final _decided = <String>{};

  Future<void> _batch(bool approve) async {
    String reason = '';
    if (!approve) {
      final r = await _pickReason(
          context,
          tr3(
              '拒绝 ${_selected.length} 个需求的原因',
              'Қабылдамау себебі (тапсырыс: ${_selected.length})',
              'Причина отклонения (заявок: ${_selected.length})',
              'Rejection reason (requests: ${_selected.length})', ky: 'Четке кагуунун себеби (суроо-талаптар: ${_selected.length})', uz: 'Rad etish sababi (soʻrovlar: ${_selected.length})'));
      if (r == null || !mounted) return;
      reason = r;
    }
    final res = await attempt(
        context,
        () => context
            .read(adminRepositoryProvider)
            .decideMany(_selected.toList(), approve, reason: reason));
    if (res == null || !mounted) return;
    toast(
        context,
        res.failed.isEmpty
            ? tr3('已处理 ${res.done} 个', 'Өңделді: ${res.done}',
                'Обработано: ${res.done}',
                'Processed: ${res.done}', ky: 'Иштетилди: ${res.done}', uz: 'Qayta ishlandi: ${res.done}')
            : tr3(
                '已处理 ${res.done} 个，${res.failed.length} 个状态已变化未处理',
                'Өңделді: ${res.done}; күйі өзгергендіктен өткізілді: ${res.failed.length}',
                'Обработано: ${res.done}; пропущено из-за смены статуса: ${res.failed.length}',
                'Processed: ${res.done}; skipped because the status changed: ${res.failed.length}', ky: 'Иштетилди: ${res.done}; абалы өзгөргөндүктөн өткөрүлүп жиберилди: ${res.failed.length}', uz: 'Qayta ishlandi: ${res.done}; holati oʻzgargani uchun oʻtkazib yuborildi: ${res.failed.length}'));
    setState(_selected.clear);
  }

  Future<bool> _reject(Demand d) async {
    final r = await _pickReason(
        context, tr3('拒绝原因', 'Қабылдамау себебі', 'Причина отклонения', 'Rejection reason', ky: 'Четке кагуунун себеби', uz: 'Rad etish sababi'));
    if (r == null || !mounted) return false;
    return await attempt(context, () async {
          await context.read(adminRepositoryProvider).reject(d.id, r);
          return true;
        }, success: tr3('已拒绝', 'Қабылданбады', 'Отклонено', 'Rejected', ky: 'Четке кагылды', uz: 'Rad etildi')) ==
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
                padding: const EdgeInsets.symmetric(
                    horizontal: YSpace.gutter, vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          tr3(
                              '已选 ${_selected.length}',
                              'Таңдалды: ${_selected.length}',
                              'Выбрано: ${_selected.length}',
                              'Selected: ${_selected.length}', ky: 'Тандалды: ${_selected.length}', uz: 'Tanlandi: ${_selected.length}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  TextButton(
                      onPressed: () => setState(_selected.clear),
                      child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                  TextButton(
                      onPressed: () => _batch(false),
                      child: Text(tr3('批量拒绝', 'Қабылдамау', 'Отклонить', 'Reject', ky: 'Четке кагуу', uz: 'Rad etish'))),
                  FilledButton(
                      onPressed: () => _batch(true),
                      child: Text(tr3('批量通过', 'Мақұлдау', 'Одобрить', 'Approve', ky: 'Бекитүү', uz: 'Tasdiqlash'))),
                ]))),
      Expanded(
          child: _PagedList<Demand>(
              key: const ValueKey('queue'),
              load: (p) =>
                  context.read(adminRepositoryProvider).reviewQueue(page: p),
              empty: tr3('没有待审核的需求', 'Тексеруді күткен тапсырыс жоқ',
                  'Нет заявок на проверке',
                  'No requests to review', ky: 'Текшере турган суроо-талап жок', uz: 'Tekshiriladigan soʻrov yoʻq'),
              header: canModerate
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: YSpace.sm),
                      child: Text(
                          tr3(
                              '右滑通过，左滑拒绝，长按多选',
                              'Оңға сырғыту — мақұлдау, солға — қабылдамау, ұзақ басу — бірнешеуін таңдау',
                              'Свайп вправо — одобрить, влево — отклонить, долгое нажатие — выбрать несколько',
                              'Swipe right to approve, left to reject, long-press to select several', ky: 'Бекитүү үчүн оңго, четке кагуу үчүн солго сүрүңүз, бир нечесин тандоо үчүн узак басыңыз', uz: 'Tasdiqlash uchun oʻngga, rad etish uchun chapga suring, bir nechtasini tanlash uchun uzoq bosing'),
                          style: YText.caption.copyWith(color: t.muted)))
                  : null,
              item: (context, d) {
                if (_decided.contains(d.id)) return const SizedBox.shrink();
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
                        color: t.ok,
                        icon: Icons.check,
                        label: _approveWord,
                        left: true),
                    secondaryBackground: _SwipeBg(
                        color: t.crit,
                        icon: Icons.close,
                        label: tr3('拒绝', 'Қабылдамау', 'Отклонить', 'Reject', ky: 'Четке кагуу', uz: 'Rad etish'),
                        left: false),
                    confirmDismiss: (dir) async {
                      if (dir == DismissDirection.startToEnd) {
                        return await attempt(context, () async {
                              await context
                                  .read(adminRepositoryProvider)
                                  .approve(d.id);
                              return true;
                            }, success: tr3('已通过', 'Мақұлданды', 'Одобрено', 'Approved', ky: 'Бекитилди', uz: 'Tasdiqlandi')) ==
                            true;
                      }
                      return _reject(d);
                    },
                    onDismissed: (_) => setState(() => _decided.add(d.id)),
                    child: card);
              })),
    ]);
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg(
      {required this.color,
      required this.icon,
      required this.label,
      required this.left});
  final Color color;
  final IconData icon;
  final String label;
  final bool left;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: YSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: YSpace.xl),
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(YRadius.card)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: onFill(color)),
        const SizedBox(width: 6),
        Text(label, style: YText.bodyStrong.copyWith(color: onFill(color))),
      ]));
}

class _DemandCard extends StatelessWidget {
  const _DemandCard(
      {required this.demand,
      this.selected = false,
      this.onTap,
      this.onLongPress});
  final Demand demand;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (selected) ...[
                          Icon(Icons.check_circle, color: t.accent, size: 20),
                          const SizedBox(width: 6),
                        ],
                        Expanded(child: Text(v.title, style: YText.bodyStrong)),
                        StatusPill(demandStatusName(demand.status)),
                      ]),
                      const SizedBox(height: 4),
                      Text(v.description,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          '${regionName(v.region)} · ${demandTypeName(demand.type)} · ${tr3('第 ${v.no} 版', '${v.no}-нұсқа', 'версия ${v.no}', 'version ${v.no}', ky: '${v.no}-версия', uz: '${v.no}-versiya')} · ${_date(demand.createdAt)}',
                          style: YText.caption.copyWith(color: t.muted)),
                      if (demand.rejectReason != null &&
                          demand.status == DemandStatus.rejected)
                        Text(
                            tr3(
                                '拒绝原因：${_reasonLabel(demand.rejectReason!)}',
                                'Қабылдамау себебі: ${_reasonLabel(demand.rejectReason!)}',
                                'Причина отклонения: ${_reasonLabel(demand.rejectReason!)}',
                                'Rejection reason: ${_reasonLabel(demand.rejectReason!)}', ky: 'Четке кагуунун себеби: ${_reasonLabel(demand.rejectReason!)}', uz: 'Rad etish sababi: ${_reasonLabel(demand.rejectReason!)}'),
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
                'Жалоба подтверждена: пояснение нарушителю',
                'Report upheld: explanation for the offender', ky: 'Арыз канааттандырылды: бузуучуга түшүндүрмө', uz: 'Shikoyat qanoatlantirildi: qoidabuzarga izoh'))
        : await _pickReason(
            context,
            tr3('驳回举报：给举报人的说明', 'Шағым қабылданбады: шағымданушыға түсініктеме',
                'Жалоба отклонена: пояснение заявителю',
                'Report rejected: explanation for the reporter', ky: 'Арыз четке кагылды: арыз берүүчүгө түшүндүрмө', uz: 'Shikoyat rad etildi: shikoyatchiga izoh'),
            codes: const ['ok']);
    if (note == null || !mounted) return;
    await attempt(
        context,
        () => context
            .read(adminRepositoryProvider)
            .resolveReport(v.report.id, upheld, note),
        success: upheld
            ? tr3(
                '已处理，内容已下架/账号已限制，双方已通知',
                'Өңделді: мазмұн алынды не аккаунт шектелді, екі жаққа хабарланды',
                'Готово: контент снят или аккаунт ограничен, обе стороны уведомлены',
                'Done: content removed or account restricted; both sides notified', ky: 'Аткарылды: мазмун өчүрүлдү же аккаунт чектелди; эки тарапка тең билдирилди', uz: 'Bajarildi: kontent oʻchirildi yoki akkaunt cheklandi; ikkala tomonga xabar berildi')
            : tr3('已驳回，举报人已通知', 'Қабылданбады, шағымданушыға хабарланды',
                'Отклонено, заявитель уведомлён',
                'Rejected; the reporter was notified', ky: 'Четке кагылды; арыз берүүчүгө билдирилди', uz: 'Rad etildi; shikoyatchiga xabar berildi'));
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
        if (v.postId != null) {
          pushPage<void>(context, (_) => PostPage(postId: v.postId!));
        }
      case ReportTarget.account:
        pushPage<void>(
            context, (_) => AccountDetailPage(accountId: r.targetId));
      case ReportTarget.message:
        if (v.targetOwnerId.isNotEmpty) {
          pushPage<void>(
              context, (_) => AccountDetailPage(accountId: v.targetOwnerId));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<ReportStatus?>(options: [
        (ReportStatus.open, tr3('待处理', 'Күтуде', 'Ожидают', 'Pending', ky: 'Күтүүдө', uz: 'Kutilmoqda')),
        (ReportStatus.upheld, tr3('已成立', 'Расталған', 'Подтверждённые', 'Upheld', ky: 'Канааттандырылды', uz: 'Qanoatlantirildi')),
        (ReportStatus.dismissed, tr3('已驳回', 'Қабылданбаған', 'Отклонённые', 'Rejected', ky: 'Четке кагылды', uz: 'Rad etildi')),
        (null, _all),
      ], selected: _status, onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<ReportView>(
              key: ValueKey('reports-$_status'),
              load: (p) => context
                  .read(adminRepositoryProvider)
                  .reports(status: _status, page: p),
              empty: tr3('没有举报', 'Шағым жоқ', 'Жалоб нет', 'No reports', ky: 'Арыздар жок', uz: 'Shikoyatlar yoʻq'),
              item: (context, v) {
                final r = v.report;
                final reporter = v.reporterName.isEmpty ? '—' : v.reporterName;
                final accused =
                    v.targetOwnerName.isEmpty ? '—' : v.targetOwnerName;
                return Padding(
                    padding: const EdgeInsets.only(bottom: YSpace.sm),
                    child: YCard(
                        onTap: () => _openTarget(v),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                StatusPill(_reportTargetName(r.target)),
                                const SizedBox(width: YSpace.sm),
                                Expanded(
                                    child: Text(
                                        v.targetTitle.isEmpty
                                            ? r.targetId
                                            : v.targetTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: YText.bodyStrong)),
                              ]),
                              const SizedBox(height: 4),
                              Text(tr3(
                                  '原因：${_reasonLabel(r.reason)}',
                                  'Себебі: ${_reasonLabel(r.reason)}',
                                  'Причина: ${_reasonLabel(r.reason)}',
                                  'Reason: ${_reasonLabel(r.reason)}', ky: 'Себеби: ${_reasonLabel(r.reason)}', uz: 'Sababi: ${_reasonLabel(r.reason)}')),
                              Text(
                                  tr3(
                                      '举报人 $reporter · 被举报 $accused · ${_date(r.createdAt)}',
                                      'Шағымданушы: $reporter · Кімге: $accused · ${_date(r.createdAt)}',
                                      'Заявитель: $reporter · На кого: $accused · ${_date(r.createdAt)}',
                                      'Reporter: $reporter · Against: $accused · ${_date(r.createdAt)}', ky: 'Арыз берүүчү: $reporter · Кимге: $accused · ${_date(r.createdAt)}', uz: 'Shikoyatchi: $reporter · Kimga: $accused · ${_date(r.createdAt)}'),
                                  style:
                                      YText.caption.copyWith(color: t.muted)),
                              if (r.status != ReportStatus.open)
                                Text(
                                    '${_reportStatusName(r.status)}${tr3('：', ': ', ': ', ': ', ky: ': ', uz: ': ')}${_reasonLabel(r.resolution)}',
                                    style:
                                        YText.caption.copyWith(color: t.muted)),
                              if (r.status == ReportStatus.open &&
                                  canModerate) ...[
                                const SizedBox(height: YSpace.sm),
                                Row(children: [
                                  if (v.targetOwnerId.isNotEmpty)
                                    TextButton(
                                        onPressed: () => pushPage<void>(
                                            context,
                                            (_) => AccountDetailPage(
                                                accountId: v.targetOwnerId)),
                                        child: Text(
                                            tr3('看此人', 'Аккаунт', 'Аккаунт', 'Account', ky: 'Аккаунт', uz: 'Akkaunt'))),
                                  const Spacer(),
                                  OutlinedButton(
                                      onPressed: () => _resolve(v, false),
                                      child: Text(_dismissWord)),
                                  const SizedBox(width: YSpace.sm),
                                  FilledButton(
                                      onPressed: () => _resolve(v, true),
                                      child: Text(switch (r.target) {
                                        ReportTarget.account ||
                                        ReportTarget.message =>
                                          tr3('成立并限制', 'Шектеу', 'Ограничить', 'Restrict', ky: 'Чектөө', uz: 'Cheklash'),
                                        ReportTarget.comment =>
                                          tr3('成立并删除', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish'),
                                        _ =>
                                          tr3('成立并下架', 'Алып тастау', 'Снять', 'Take down', ky: 'Алып салуу', uz: 'Olib tashlash'),
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
                'Апелляция удовлетворена: пояснение',
                'Appeal granted: explanation', ky: 'Даттануу канааттандырылды: түшүндүрмө', uz: 'Apellyatsiya qanoatlantirildi: izoh')
            : tr3('维持原处理：说明', 'Шешім күшінде қалады: түсініктеме',
                'Решение оставлено в силе: пояснение',
                'Decision upheld: explanation', ky: 'Чечим күчүндө калды: түшүндүрмө', uz: 'Qaror kuchda qoldi: izoh'),
        hint: _userSees);
    if (note == null || !mounted) return;
    await attempt(
        context,
        () => context
            .read(adminRepositoryProvider)
            .resolveAppeal(a.id, accept, note),
        success: accept
            ? tr3('已恢复并通知用户', 'Қалпына келтірілді, пайдаланушыға хабарланды',
                'Восстановлено, пользователь уведомлён',
                'Restored; the user was notified', ky: 'Калыбына келтирилди; колдонуучуга билдирилди', uz: 'Tiklandi; foydalanuvchiga xabar berildi')
            : tr3('已回复用户', 'Пайдаланушыға жауап жіберілді',
                'Ответ отправлен пользователю',
                'Reply sent to the user', ky: 'Жооп колдонуучуга жөнөтүлдү', uz: 'Javob foydalanuvchiga yuborildi'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<AppealStatus?>(options: [
        (AppealStatus.open, tr3('待处理', 'Күтуде', 'Ожидают', 'Pending', ky: 'Күтүүдө', uz: 'Kutilmoqda')),
        (
          AppealStatus.accepted,
          tr3('已成立', 'Қанағаттандырылған', 'Удовлетворённые', 'Granted', ky: 'Канааттандырылды', uz: 'Qanoatlantirildi')
        ),
        (AppealStatus.rejected, tr3('已驳回', 'Қабылданбаған', 'Отклонённые', 'Rejected', ky: 'Четке кагылды', uz: 'Rad etildi')),
        (null, _all),
      ], selected: _status, onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<Appeal>(
              key: ValueKey('appeals-$_status'),
              load: (p) => context
                  .read(adminRepositoryProvider)
                  .appeals(status: _status, page: p),
              empty: tr3('没有申诉', 'Апелляция жоқ', 'Апелляций нет', 'No appeals', ky: 'Даттануулар жок', uz: 'Apellyatsiyalar yoʻq'),
              item: (context, a) => Padding(
                  padding: const EdgeInsets.only(bottom: YSpace.sm),
                  child: YCard(
                      onTap: () => pushPage<void>(context,
                          (_) => AccountDetailPage(accountId: a.accountId)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              StatusPill(_targetName(a.target)),
                              const SizedBox(width: YSpace.sm),
                              Expanded(
                                  child: Text(
                                      a.targetTitle.isEmpty
                                          ? a.accountName
                                          : a.targetTitle,
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
                                      'Ответ: ${_reasonLabel(a.resolution)}',
                                      'Reply: ${_reasonLabel(a.resolution)}', ky: 'Жооп: ${_reasonLabel(a.resolution)}', uz: 'Javob: ${_reasonLabel(a.resolution)}'),
                                  style:
                                      YText.caption.copyWith(color: t.muted)),
                            if (a.status == AppealStatus.open && canModerate)
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton(
                                        onPressed: () => _resolve(a, false),
                                        child: Text(tr3(
                                            '维持', 'Қабылдамау', 'Отклонить', 'Reject', ky: 'Четке кагуу', uz: 'Rad etish'))),
                                    const SizedBox(width: YSpace.sm),
                                    FilledButton(
                                        onPressed: () => _resolve(a, true),
                                        child: Text(tr3(
                                            '成立并恢复',
                                            'Қалпына келтіру',
                                            'Восстановить',
                                            'Restore', ky: 'Калыбына келтирүү', uz: 'Tiklash'))),
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
      img = Image.memory(base64Decode(src.substring(src.indexOf(',') + 1)),
          fit: BoxFit.cover);
    } else {
      final base = switch (context.read(adminRepositoryProvider)) {
        final HttpAdminRepository admin => admin.api.baseUrl,
        _ => '',
      };
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
            context, tr3('驳回原因', 'Қабылдамау себебі', 'Причина отклонения', 'Rejection reason', ky: 'Четке кагуунун себеби', uz: 'Rad etish sababi'),
            hint: tr3(
                '例如：照片看不出是本人施工的现场',
                'Мысалы: фотодан жұмысты өзі істегені көрінбейді',
                'Например: по фото не видно, что работу выполнял сам мастер',
                "For example: the photos don't show that the pro did the work themselves", ky: 'Мисалы: сүрөттөр адис ишти өзү аткарганын көрсөтпөйт', uz: 'Masalan: rasmlar mutaxassis ishni oʻzi bajarganini koʻrsatmaydi'));
    if (note == null || !mounted) return;
    await attempt(
        context,
        () => context
            .read(adminRepositoryProvider)
            .resolveVerification(v.id, approve, note),
        success: approve
            ? tr3(
                '已通过，名片显示“已核验”',
                'Мақұлданды, профильде «Расталған» белгісі шығады',
                'Одобрено, в профиле появится отметка «Проверен»',
                'Approved; the profile will show a “Verified” badge', ky: 'Бекитилди; профилде «Текшерилген» белгиси көрүнөт', uz: 'Tasdiqlandi; profilda “Tekshirilgan” belgisi koʻrinadi')
            : tr3('已驳回并通知', 'Қабылданбады, пайдаланушыға хабарланды',
                'Отклонено, пользователь уведомлён',
                'Rejected; the user was notified', ky: 'Четке кагылды; колдонуучуга билдирилди', uz: 'Rad etildi; foydalanuvchiga xabar berildi'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<VerificationStatus?>(options: [
        (VerificationStatus.pending, tr3('待审核', 'Күтуде', 'Ожидают', 'Pending', ky: 'Күтүүдө', uz: 'Kutilmoqda')),
        (VerificationStatus.approved, tr3('已通过', 'Мақұлданған', 'Одобренные', 'Approved', ky: 'Бекитилди', uz: 'Tasdiqlandi')),
        (
          VerificationStatus.rejected,
          tr3('已驳回', 'Қабылданбаған', 'Отклонённые', 'Rejected', ky: 'Четке кагылды', uz: 'Rad etildi')
        ),
        (null, _all),
      ], selected: _status, onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<Verification>(
              key: ValueKey('verif-$_status'),
              load: (p) => context
                  .read(adminRepositoryProvider)
                  .verifications(status: _status, page: p),
              empty: tr3(
                  '没有认证申请', 'Растау өтінімі жоқ', 'Заявок на верификацию нет', 'No verification requests', ky: 'Текшерүү өтүнүчтөрү жок', uz: 'Tekshiruv soʻrovlari yoʻq'),
              item: (context, v) => Padding(
                  padding: const EdgeInsets.only(bottom: YSpace.sm),
                  child: YCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        InkWell(
                            onTap: () => pushPage<void>(context,
                                (_) => ProfilePage(profileId: v.profileId)),
                            child: Text(v.name, style: YText.bodyStrong)),
                        Text(
                            '${v.ownerName} · ${tr3('电话 ${v.phone}', 'тел. ${v.phone}', 'тел. ${v.phone}', 'tel. ${v.phone}', ky: 'тел. ${v.phone}', uz: 'tel. ${v.phone}')} · ${_date(v.createdAt)}',
                            style: YText.caption.copyWith(color: t.muted)),
                        if (v.note.isNotEmpty) Text(v.note),
                        const SizedBox(height: YSpace.sm),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final p in v.photos) _Photo(p),
                        ]),
                        if (v.resolution.isNotEmpty)
                          Text(
                              tr3(
                                  '说明：${v.resolution}',
                                  'Түсініктеме: ${v.resolution}',
                                  'Пояснение: ${v.resolution}',
                                  'Explanation: ${v.resolution}', ky: 'Түшүндүрмө: ${v.resolution}', uz: 'Izoh: ${v.resolution}'),
                              style: YText.caption.copyWith(color: t.muted)),
                        if (v.status == VerificationStatus.pending &&
                            canModerate)
                          Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                    onPressed: () => _resolve(v, false),
                                    child: Text(_dismissWord)),
                                const SizedBox(width: YSpace.sm),
                                FilledButton(
                                    onPressed: () => _resolve(v, true),
                                    child: Text(_approveWord)),
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
          padding: const EdgeInsets.fromLTRB(
              YSpace.gutter, YSpace.sm, YSpace.gutter, 0),
          child: SearchField(
              controller: search,
              hint: tr3('名字、邮箱或账号 ID', 'Аты, email не аккаунт ID',
                  'Имя, email или ID аккаунта',
                  'Name, email or account ID', ky: 'Аты, email же аккаунт ID', uz: 'Ism, email yoki akkaunt ID'),
              onChanged: typed)),
      _Chips<_UserFilter>(options: [
        (_UserFilter.all, _all),
        (_UserFilter.restricted, tr3('受限', 'Шектелген', 'Ограниченные', 'Restricted', ky: 'Чектелген', uz: 'Cheklangan')),
        (_UserFilter.team, _teamTitle),
      ], selected: _filter, onSelect: (v) => setState(() => _filter = v)),
      Expanded(
          child: _PagedList<AdminUserRow>(
              key: ValueKey('users-$_q-$_filter'),
              load: (p) => context.read(adminRepositoryProvider).users(
                  query: _q,
                  restricted: _filter == _UserFilter.restricted,
                  admins: _filter == _UserFilter.team,
                  page: p),
              empty: tr3(
                  '没有找到用户', 'Пайдаланушы табылмады', 'Пользователи не найдены', 'No users found', ky: 'Колдонуучулар табылган жок', uz: 'Foydalanuvchilar topilmadi'),
              item: (context, u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(u.name.isEmpty ? '?' : u.name),
                  title: Text(u.name.isEmpty ? _unnamed : u.name),
                  subtitle: Text([
                    if (u.email.isNotEmpty) u.email,
                    _registered(u.createdAt),
                  ].join(' · ')),
                  trailing: Wrap(spacing: 4, children: [
                    if (u.role != null) StatusPill(roleName(u.role)),
                    if (u.restricted)
                      StatusPill(_restrictedPill, color: t.crit),
                  ]),
                  onTap: () => pushPage<void>(
                      context, (_) => AccountDetailPage(accountId: u.id))))),
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
                'Снятие ограничения: пояснение',
                'Lifting the restriction: explanation', ky: 'Чектөөнү алуу: түшүндүрмө', uz: 'Cheklovni olib tashlash: izoh'),
            hint: _userSees)
        : await _pickReason(
            context, tr3('限制原因', 'Шектеу себебі', 'Причина ограничения', 'Restriction reason', ky: 'Чектөөнүн себеби', uz: 'Cheklov sababi'),
            codes: const ['fake', 'abuse', 'spam', 'illegal']);
    if (note == null || !context.mounted) return;
    await attempt(
        context,
        () => context
            .read(adminRepositoryProvider)
            .setRestriction(a.id, !a.restricted, note),
        success: a.restricted
            ? tr3('已解除限制', 'Шектеу алынды', 'Ограничение снято', 'Restriction lifted', ky: 'Чектөө алынды', uz: 'Cheklov olib tashlandi')
            : tr3(
                '已限制：只能浏览，不能发布、报名和发消息',
                'Шектелді: тек қарай алады; жариялау, өтінім беру және хабар жазу жабық',
                'Ограничен: только просмотр, без публикаций, откликов и сообщений',
                'Restricted: view only, no posting, responses or messages', ky: 'Чектелди: көрүү гана, жарыялоо, жооп берүү жана билдирүү жазуу мүмкүн эмес', uz: 'Cheklandi: faqat koʻrish, eʼlon, javob va xabar yozish mumkin emas'));
  }

  Future<void> _ban(BuildContext context, Account a, bool banned) async {
    final api = _http(context);
    if (api == null) return;
    final note = banned
        ? await askText(
            context,
            tr3('解封：说明', 'Бұғаттан шығару: түсініктеме',
                'Разблокировка: пояснение',
                'Unblocking: explanation', ky: 'Бөгөттөн чыгаруу: түшүндүрмө', uz: 'Blokdan chiqarish: izoh'))
        : await _pickReason(
            context, tr3('封禁原因', 'Бұғаттау себебі', 'Причина блокировки', 'Block reason', ky: 'Бөгөттөөнүн себеби', uz: 'Bloklash sababi'),
            codes: const ['fake', 'abuse', 'spam', 'illegal']);
    if (note == null || !context.mounted) return;
    await attempt(context, () => api.setBanned(a.id, !banned, note),
        success: banned
            ? tr3('已解封', 'Бұғаттан шығарылды', 'Разблокирован', 'Unblocked', ky: 'Бөгөттөн чыгарылды', uz: 'Blokdan chiqarildi')
            : tr3('已封禁：不能登录和使用', 'Бұғатталды: кіре алмайды',
                'Заблокирован: войти нельзя',
                "Blocked: can't sign in", ky: 'Бөгөттөлдү: кире албайт', uz: 'Bloklandi: kira olmaydi'));
  }

  Future<void> _delete(BuildContext context, Account a) async {
    final api = _http(context);
    if (api == null) return;
    final note = await askText(
        context, tr3('注销原因', 'Жою себебі', 'Причина удаления', 'Deletion reason', ky: 'Өчүрүүнүн себеби', uz: 'Oʻchirish sababi'),
        hint: tr3(
            '名片和需求会下架，云端备份删除，不能恢复。',
            'Профильдер мен тапсырыстар алынады, қалпына келмейді.',
            'Профили и заявки снимаются, восстановить нельзя.',
            "Profiles and requests are taken down and can't be restored.", ky: 'Профилдер жана суроо-талаптар алынып салынат жана калыбына келтирилбейт.', uz: 'Profillar va soʻrovlar olib tashlanadi va tiklanmaydi.'));
    if (note == null || !context.mounted) return;
    if (!await confirmDialog(context,
            tr3('注销这个账号？', 'Аккаунтты жою керек пе?', 'Удалить аккаунт?', 'Delete the account?', ky: 'Аккаунтту өчүрөсүзбү?', uz: 'Akkaunt oʻchirilsinmi?'),
            ok: tr3('注销', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish'), danger: true) ||
        !context.mounted) {
      return;
    }
    await attempt(context, () => api.deleteAccountFor(a.id, note),
        success: tr3('已注销', 'Жойылды', 'Удалён', 'Deleted', ky: 'Өчүрүлдү', uz: 'Oʻchirildi'));
  }

  Future<void> _takeDown(BuildContext context, String target, String id) async {
    final api = _http(context);
    if (api == null) return;
    final note = await _pickReason(
        context, tr3('下架原因', 'Алып тастау себебі', 'Причина снятия', 'Takedown reason', ky: 'Алып салуунун себеби', uz: 'Olib tashlash sababi'));
    if (note == null || !context.mounted) return;
    await attempt(context, () => api.takeDown(target, id, note),
        success: tr3('已下架', 'Алынды', 'Снято', 'Taken down', ky: 'Алынып салынды', uz: 'Olib tashlandi'));
  }

  static String _methodName(String m) => switch (m) {
        'email' => tr3('邮箱', 'Пошта', 'Почта', 'Email', ky: 'Email', uz: 'Email'),
        'google' => 'Google',
        'apple' => 'Apple',
        _ => tr3('测试登录', 'Тест', 'Тест', 'Test', ky: 'Тест', uz: 'Test'),
      };

  Future<void> _role(BuildContext context, Account a) async {
    final v = await pickOne<String>(
        context,
        tr3('后台角色', 'Әкімшіліктегі рөл', 'Роль в админке', 'Admin role', ky: 'Админ ролу', uz: 'Admin roli'),
        [
          for (final r in AdminRoles.all) (r, roleName(r)),
          ('', tr3('无（撤销）', 'Жоқ (рөлді алу)', 'Нет (снять роль)', 'None (remove the role)', ky: 'Жок (ролду алуу)', uz: 'Yoʻq (rolni olib tashlash)')),
        ],
        selected: a.role ?? '');
    if (v == null || !context.mounted) return;
    await attempt(
        context,
        () => context
            .read(adminRepositoryProvider)
            .setRole(a.id, v.isEmpty ? null : v),
        success: tr3('已更新角色', 'Рөл жаңартылды', 'Роль обновлена', 'Role updated', ky: 'Роль жаңыланды', uz: 'Rol yangilandi'));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.session.currentAccount;
    return Scaffold(
        appBar: AppBar(
            title:
                Text(tr3('账号详情', 'Аккаунт мәліметі', 'Сведения об аккаунте', 'Account details', ky: 'Аккаунттун маалыматы', uz: 'Akkaunt maʼlumotlari'))),
        body: Live<AccountDetail>(
            provider: accountDetailProvider(accountId),
            builder: (context, d) {
              final a = d.account;
              final self = me?.id == a.id;
              return ListView(
                  padding: const EdgeInsets.all(YSpace.gutter),
                  children: [
                    Row(children: [
                      Avatar(a.displayName.isEmpty ? '?' : a.displayName,
                          size: 56),
                      const SizedBox(width: YSpace.md),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                a.displayName.isEmpty
                                    ? _unnamed
                                    : a.displayName,
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
                                        'Последний вход: ${_date(d.lastLogin!)}',
                                        'Last sign-in: ${_date(d.lastLogin!)}', ky: 'Акыркы кирүү: ${_date(d.lastLogin!)}', uz: 'Oxirgi kirish: ${_date(d.lastLogin!)}'),
                                ].join(' · '),
                                style: YText.caption.copyWith(color: t.muted)),
                          ])),
                    ]),
                    const SizedBox(height: YSpace.sm),
                    Wrap(spacing: 6, children: [
                      if (a.role != null) StatusPill(roleName(a.role)),
                      if (a.restricted)
                        StatusPill(_restrictedPill, color: t.crit),
                      if (d.banned)
                        StatusPill(tr3('已封禁', 'Бұғатталған', 'Заблокирован', 'Blocked', ky: 'Бөгөттөлгөн', uz: 'Bloklangan'),
                            color: t.crit),
                      if (a.deleted)
                        StatusPill(tr3('已注销', 'Жойылған', 'Удалён', 'Deleted', ky: 'Өчүрүлгөн', uz: 'Oʻchirilgan')),
                    ]),
                    if (!self && !a.deleted) ...[
                      const SizedBox(height: YSpace.md),
                      Wrap(spacing: YSpace.sm, children: [
                        if (_may(context, AdminPerms.moderate) &&
                            a.role == null)
                          OutlinedButton(
                              onPressed: () => _restrict(context, a),
                              child: Text(a.restricted
                                  ? tr3('解除限制', 'Шектеуді алу',
                                      'Снять ограничение',
                                      'Lift the restriction', ky: 'Чектөөнү алуу', uz: 'Cheklovni olib tashlash')
                                  : tr3('限制账号', 'Аккаунтты шектеу',
                                      'Ограничить аккаунт',
                                      'Restrict the account', ky: 'Аккаунтту чектөө', uz: 'Akkauntni cheklash'))),
                        if (_may(context, AdminPerms.team) && !a.restricted)
                          OutlinedButton(
                              onPressed: () => _role(context, a),
                              child: Text(tr3('设置后台角色', 'Рөл тағайындау',
                                  'Назначить роль',
                                  'Assign a role', ky: 'Роль берүү', uz: 'Rol berish'))),
                        if (_may(context, AdminPerms.moderate) &&
                            a.role == null)
                          OutlinedButton(
                              onPressed: () => _ban(context, a, d.banned),
                              child: Text(d.banned
                                  ? tr3(
                                      '解封', 'Бұғаттан шығару', 'Разблокировать', 'Unblock', ky: 'Бөгөттөн чыгаруу', uz: 'Blokdan chiqarish')
                                  : tr3('封禁', 'Бұғаттау', 'Заблокировать', 'Block', ky: 'Бөгөттөө', uz: 'Bloklash'))),
                        if (_may(context, AdminPerms.team) && a.role == null)
                          OutlinedButton(
                              onPressed: () => _delete(context, a),
                              child: Text(
                                  tr3('注销账号', 'Аккаунтты жою',
                                      'Удалить аккаунт',
                                      'Delete the account', ky: 'Аккаунтту өчүрүү', uz: 'Akkauntni oʻchirish'),
                                  style: TextStyle(color: t.crit))),
                      ]),
                    ],
                    const SizedBox(height: YSpace.lg),
                    Text(
                        tr3(
                            '报价/报名 ${d.applications} 次 · 举报他人 ${d.reportsFiled} 次',
                            'Өтінім: ${d.applications} · Берген шағымы: ${d.reportsFiled}',
                            'Откликов: ${d.applications} · Подано жалоб: ${d.reportsFiled}',
                            'Responses: ${d.applications} · Reports filed: ${d.reportsFiled}', ky: 'Жооптор: ${d.applications} · Берилген арыздар: ${d.reportsFiled}', uz: 'Javoblar: ${d.applications} · Berilgan shikoyatlar: ${d.reportsFiled}'),
                        style: YText.caption.copyWith(color: t.muted)),
                    if (d.profiles.isNotEmpty) ...[
                      SectionTitle(tr3('名片', 'Профильдер', 'Профили', 'Profiles', ky: 'Профилдер', uz: 'Profillar')),
                      for (final p in d.profiles)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.name),
                            subtitle: Text([
                              p.status == ProfileStatus.hidden
                                  ? tr3('隐藏', 'Жасырын', 'Скрыт', 'Hidden', ky: 'Жашырылган', uz: 'Yashirilgan')
                                  : tr3('公开', 'Жария', 'Опубликован', 'Published', ky: 'Жарыяланган', uz: 'Eʼlon qilingan'),
                              if (p.verified)
                                tr3('已核验', 'расталған', 'проверен', 'verified', ky: 'текшерилген', uz: 'tekshirilgan'),
                            ].join(' · ')),
                            onTap: () => pushPage<void>(
                                context, (_) => ProfilePage(profileId: p.id)),
                            trailing: _may(context, AdminPerms.moderate) &&
                                    p.status != ProfileStatus.hidden
                                ? TextButton(
                                    onPressed: () =>
                                        _takeDown(context, 'profile', p.id),
                                    child: Text(tr3('下架', 'Алу', 'Снять', 'Take down', ky: 'Алып салуу', uz: 'Olib tashlash')))
                                : null),
                    ],
                    if (d.posts.isNotEmpty) ...[
                      SectionTitle(tr3('房子', 'Үйлер', 'Дома', 'Houses', ky: 'Үйлөр', uz: 'Uylar')),
                      for (final p in d.posts)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.title),
                            subtitle: Text([
                              p.hidden
                                  ? tr3('已隐藏', 'Жасырылған', 'Скрыт', 'Hidden', ky: 'Жашырылган', uz: 'Yashirilgan')
                                  : tr3('公开', 'Жария', 'Опубликован', 'Published', ky: 'Жарыяланган', uz: 'Eʼlon qilingan'),
                              if (p.featured)
                                tr3('精选', 'Таңдаулы', 'В подборке', 'Featured', ky: 'Тандалган', uz: 'Tanlangan'),
                              if (_may(context, AdminPerms.operate) &&
                                  !p.hidden)
                                tr3('长按设精选', 'Ұзақ басып таңдау',
                                    'Удерживайте для подборки',
                                    'Hold to feature', ky: 'Тандалгандарга кошуу үчүн кармап туруңуз', uz: 'Tanlanganlarga qoʻshish uchun bosib turing'),
                            ].join(' · ')),
                            onLongPress: _may(context, AdminPerms.operate) &&
                                    !p.hidden &&
                                    _http(context) != null
                                ? () => attempt(
                                    context,
                                    () => _http(context)!.setFeatured(
                                        p.id, !p.featured),
                                    success: p.featured
                                        ? tr3('已取消精选', 'Таңдаулыдан алынды',
                                            'Убрано из подборки',
                                            'Removed from featured', ky: 'Тандалгандардан алынды', uz: 'Tanlanganlardan olib tashlandi')
                                        : tr3(
                                            '已设为精选，排在首页最前',
                                            'Басты бетте бірінші тұрады',
                                            'В подборке: первым на главной',
                                            'Featured: first on the home screen', ky: 'Тандалган: башкы экранда биринчи', uz: 'Tanlangan: bosh ekranda birinchi'))
                                : null,
                            onTap: () =>
                                pushPage<void>(context, (_) => PostPage(postId: p.id)),
                            trailing: _may(context, AdminPerms.moderate)
                                ? TextButton(
                                    onPressed: () async {
                                      final note = p.hidden
                                          ? await askText(
                                              context,
                                              tr3(
                                                  '恢复说明',
                                                  'Қайтару түсініктемесі',
                                                  'Пояснение к восстановлению',
                                                  'Restore explanation', ky: 'Калыбына келтирүүнүн түшүндүрмөсү', uz: 'Tiklash izohi'))
                                          : await _pickReason(
                                              context,
                                              tr3('隐藏原因', 'Жасыру себебі',
                                                  'Причина скрытия',
                                                  'Reason for hiding', ky: 'Жашыруунун себеби', uz: 'Yashirish sababi'));
                                      if (note == null || !context.mounted) {
                                        return;
                                      }
                                      await attempt(
                                          context,
                                          () => context
                                              .read(adminRepositoryProvider)
                                              .setPostHidden(
                                                  p.id, !p.hidden, note));
                                    },
                                    child: Text(p.hidden ? tr3('恢复', 'Қайтару', 'Вернуть', 'Restore', ky: 'Калыбына келтирүү', uz: 'Tiklash') : tr3('隐藏', 'Жасыру', 'Скрыть', 'Hide', ky: 'Жашыруу', uz: 'Yashirish')))
                                : null),
                    ],
                    if (d.demands.isNotEmpty) ...[
                      SectionTitle(tr3('需求', 'Тапсырыстар', 'Заявки', 'Requests', ky: 'Суроо-талаптар', uz: 'Soʻrovlar')),
                      for (final x in d.demands) ...[
                        _DemandCard(
                            demand: x,
                            onTap: () => pushPage<void>(context,
                                (_) => DemandDetailPage(demandId: x.id))),
                        if (_may(context, AdminPerms.moderate) &&
                            const [
                              DemandStatus.pendingReview,
                              DemandStatus.open,
                              DemandStatus.paused
                            ].contains(x.status))
                          Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                  onPressed: () =>
                                      _takeDown(context, 'demand', x.id),
                                  child: Text(tr3('下架这个需求', 'Тапсырысты алу',
                                      'Снять заявку',
                                      'Take down the request', ky: 'Суроо-талапты алып салуу', uz: 'Soʻrovni olib tashlash')))),
                      ],
                    ],
                    if (d.cooperations.isNotEmpty) ...[
                      SectionTitle(tr3(
                          '合作 ${d.cooperations.length}',
                          'Келісімдер: ${d.cooperations.length}',
                          'Сделки: ${d.cooperations.length}',
                          'Deals: ${d.cooperations.length}', ky: 'Келишимдер: ${d.cooperations.length}', uz: 'Bitimlar: ${d.cooperations.length}')),
                      for (final c in d.cooperations)
                        Text(
                            [
                              _date(c.createdAt),
                              c.status.name,
                              if (c.endRequest?.dispute != null)
                                tr3(
                                    '争议：${c.endRequest!.dispute}',
                                    'Дау: ${c.endRequest!.dispute}',
                                    'Спор: ${c.endRequest!.dispute}',
                                    'Dispute: ${c.endRequest!.dispute}', ky: 'Талаш: ${c.endRequest!.dispute}', uz: 'Nizo: ${c.endRequest!.dispute}'),
                            ].join(' · '),
                            style: YText.caption),
                    ],
                    if (d.reportsAbout.isNotEmpty) ...[
                      SectionTitle(tr3('被举报', 'Үстінен түскен шағымдар',
                          'Жалобы на аккаунт',
                          'Reports against the account', ky: 'Аккаунтка каршы арыздар', uz: 'Akkauntga qarshi shikoyatlar')),
                      for (final r in d.reportsAbout)
                        Text(
                            '${_date(r.createdAt)} · ${_reportTargetName(r.target)} · ${_reasonLabel(r.reason)} · ${_reportStatusName(r.status)}',
                            style: YText.caption),
                    ],
                    if (d.appeals.isNotEmpty) ...[
                      SectionTitle(tr3('申诉', 'Апелляциялар', 'Апелляции', 'Appeals', ky: 'Даттануулар', uz: 'Apellyatsiyalar')),
                      for (final x in d.appeals)
                        Text(
                            '${_date(x.createdAt)} · ${_targetName(x.target)} · ${x.text}',
                            style: YText.caption),
                    ],
                    if (d.audit.isNotEmpty) ...[
                      SectionTitle(
                          tr3('处理记录', 'Шешімдер тарихы', 'История решений', 'Decision history', ky: 'Чечимдердин тарыхы', uz: 'Qarorlar tarixi')),
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
            SettingsGroup(title: tr3('内容', 'Мазмұн', 'Контент', 'Content', ky: 'Мазмун', uz: 'Kontent'), children: [
              SettingsRow(
                  icon: Icons.list_alt,
                  title: tr3('全部需求', 'Барлық тапсырыстар', 'Все заявки', 'All requests', ky: 'Бардык суроо-талаптар', uz: 'Barcha soʻrovlar'),
                  subtitle: tr3(
                      '按状态筛选、搜索标题，可下架已公开的需求',
                      'Күйі бойынша сүзу, атауынан іздеу, жарияланған тапсырысты алып тастау',
                      'Фильтр по статусу, поиск по названию, снятие опубликованных заявок',
                      'Filter by status, search by title, take down published requests', ky: 'Абалы боюнча чыпкалоо, аталышы боюнча издөө, жарыяланган суроо-талаптарды алып салуу', uz: 'Holati boʻyicha filtrlash, nomi boʻyicha qidirish, eʼlon qilingan soʻrovlarni olib tashlash'),
                  onTap: () =>
                      pushPage<void>(context, (_) => const _AllDemandsPage())),
            ]),
            SettingsGroup(
                title: tr3('团队与记录', 'Команда және журнал', 'Команда и журнал', 'Team and log', ky: 'Команда жана журнал', uz: 'Jamoa va jurnal'),
                children: [
                  SettingsRow(
                      icon: Icons.badge_outlined,
                      title: _teamTitle,
                      onTap: () =>
                          pushPage<void>(context, (_) => const _TeamPage())),
                  SettingsRow(
                      icon: Icons.history,
                      title:
                          tr3('操作记录', 'Әрекеттер журналы', 'Журнал действий', 'Action log', ky: 'Аракеттер журналы', uz: 'Amallar jurnali'),
                      subtitle: tr3(
                          '每一个决定：谁、何时、为什么',
                          'Әр шешім: кім, қашан, не үшін',
                          'Каждое решение: кто, когда и почему',
                          'Every decision: who, when and why', ky: 'Ар бир чечим: ким, качан жана эмне үчүн', uz: 'Har bir qaror: kim, qachon va nima uchun'),
                      onTap: () =>
                          pushPage<void>(context, (_) => const AuditPage())),
                ]),
            SettingsGroup(
                title: tr3('用户与数据', 'Қолданушылар мен деректер',
                    'Пользователи и данные',
                    'Users and data', ky: 'Колдонуучулар жана маалыматтар', uz: 'Foydalanuvchilar va maʼlumotlar'),
                children: [
                  SettingsRow(
                      key: const Key('admin-feedback'),
                      icon: Icons.mark_email_unread_outlined,
                      title: tr3('用户反馈', 'Пікірлер', 'Обратная связь', 'Feedback', ky: 'Пикир-сунуштар', uz: 'Fikr-mulohazalar'),
                      onTap: () => pushPage<void>(
                          context, (_) => const FeedbackInboxPage())),
                  SettingsRow(
                      key: const Key('admin-trends'),
                      icon: Icons.insights_outlined,
                      title: tr3(
                          '近 30 天趋势', 'Соңғы 30 күн', 'Динамика за 30 дней', '30-day trends', ky: '30 күндүк тенденциялар', uz: '30 kunlik tendensiyalar'),
                      onTap: () =>
                          pushPage<void>(context, (_) => const TrendsPage())),
                  if (_may(context, AdminPerms.team)) ...[
                    SettingsRow(
                        icon: Icons.file_download_outlined,
                        title: tr3('导出用户表', 'Қолданушыларды экспорттау',
                            'Экспорт пользователей',
                            'Export users', ky: 'Колдонуучуларды экспорттоо', uz: 'Foydalanuvchilarni eksport qilish'),
                        onTap: () => _export(context, 'users')),
                    SettingsRow(
                        icon: Icons.file_download_outlined,
                        title: tr3('导出需求表', 'Тапсырыстарды экспорттау',
                            'Экспорт заявок',
                            'Export requests', ky: 'Суроо-талаптарды экспорттоо', uz: 'Soʻrovlarni eksport qilish'),
                        onTap: () => _export(context, 'demands')),
                  ],
                ]),
            SettingsGroup(
                title: tr3('运营', 'Операциялар', 'Операции', 'Operations', ky: 'Операциялар', uz: 'Operatsiyalar'),
                children: [
                  if (_may(context, AdminPerms.operate))
                    SettingsRow(
                        key: const Key('admin-broadcast'),
                        icon: Icons.campaign_outlined,
                        title: tr3('群发通知', 'Жаппай хабарландыру', 'Рассылка', 'Broadcast', ky: 'Жалпы билдирүү', uz: 'Ommaviy xabar'),
                        subtitle: tr3('推送到所有用户的手机', 'Барлық телефонға',
                            'На все телефоны',
                            'To all phones', ky: 'Бардык телефондорго', uz: 'Barcha telefonlarga'),
                        onTap: () => pushPage<void>(
                            context, (_) => const BroadcastPage())),
                  SettingsRow(
                      key: const Key('admin-prices'),
                      icon: Icons.sell_outlined,
                      title: tr3('地区价格', 'Аймақ бағалары', 'Цены по регионам', 'Regional prices', ky: 'Аймактык баалар', uz: 'Hududiy narxlar'),
                      subtitle: tr3('预算页按地区使用的单价', 'Сметада аймақ бойынша қолданылатын бағалар',
                          'Цены, которые смета берёт по региону',
                          'Prices the estimate uses by region', ky: 'Смета аймак боюнча колдонгон баалар', uz: 'Smeta hudud boʻyicha ishlatadigan narxlar'),
                      onTap: () =>
                          pushPage<void>(context, (_) => const PricesPage())),
                  SettingsRow(
                      key: const Key('admin-banned-words'),
                      icon: Icons.block_outlined,
                      title: tr3('违禁词', 'Тыйым сөздер', 'Запрещённые слова', 'Banned words', ky: 'Тыюу салынган сөздөр', uz: 'Taqiqlangan soʻzlar'),
                      onTap: () => pushPage<void>(
                          context, (_) => const BannedWordsPage())),
                ]),
            SettingsGroup(
                title: tr3('推送', 'Хабарландырулар', 'Уведомления', 'Notifications', ky: 'Билдирмелер', uz: 'Bildirishnomalar'),
                children: [
                  SettingsRow(
                      icon: Icons.notifications_paused_outlined,
                      title: _pushTitle,
                      subtitle: tr3(
                          '平台免打扰时段与每人每日上限',
                          '«Мазаламау» уақыты және бір адамға күндік шек',
                          'Тихие часы и дневной лимит на человека',
                          'Quiet hours and daily limit per person', ky: 'Тынч сааттар жана бир адамга күндүк чек', uz: 'Sokin soatlar va bir kishiga kunlik cheklov'),
                      onTap: () => pushPage<void>(
                          context, (_) => const _PushPolicyPage())),
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
            title: Text(tr3('全部需求', 'Барлық тапсырыстар', 'Все заявки', 'All requests', ky: 'Бардык суроо-талаптар', uz: 'Barcha soʻrovlar'))),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(
                  YSpace.gutter, YSpace.sm, YSpace.gutter, 0),
              child: SearchField(
                  controller: search,
                  hint: tr3('搜索标题', 'Атауы бойынша іздеу', 'Поиск по названию', 'Search by title', ky: 'Аталышы боюнча издөө', uz: 'Nomi boʻyicha qidirish'),
                  onChanged: typed)),
          _Chips<DemandStatus?>(options: [
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
          ], selected: _status, onSelect: (v) => setState(() => _status = v)),
          Expanded(
              child: _PagedList<Demand>(
                  key: ValueKey('all-$_status-$_q'),
                  load: (p) => context
                      .read(adminRepositoryProvider)
                      .adminDemands(status: _status, query: _q, page: p),
                  empty: tr3('没有需求', 'Тапсырыс жоқ', 'Заявок нет', 'No requests', ky: 'Суроо-талаптар жок', uz: 'Soʻrovlar yoʻq'),
                  item: (context, d) => _DemandCard(
                      demand: d,
                      onTap: () => pushPage<void>(
                          context, (_) => DemandDetailPage(demandId: d.id)),
                      onLongPress: canModerate &&
                              (d.status == DemandStatus.open ||
                                  d.status == DemandStatus.paused)
                          ? () async {
                              final r = await _pickReason(
                                  context,
                                  tr3('下架原因', 'Алып тастау себебі',
                                      'Причина снятия',
                                      'Takedown reason', ky: 'Алып салуунун себеби', uz: 'Olib tashlash sababi'));
                              if (r == null || !context.mounted) return;
                              await attempt(
                                  context,
                                  () => context
                                      .read(adminRepositoryProvider)
                                      .reject(d.id, r),
                                  success:
                                      tr3('已下架', 'Алып тасталды', 'Снято', 'Taken down', ky: 'Алынып салынды', uz: 'Olib tashlandi'));
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
          provider: adminTeamProvider,
          builder: (context, list) =>
              ListView(padding: const EdgeInsets.all(YSpace.gutter), children: [
                Text(
                    tr3(
                        '超级管理员：全部权限，管理团队；审核员：审核需求、处理举报申诉与认证、限制账号；运营：推送节制；只读：只能查看。角色在“用户”里点开账号设置，不能改自己的角色。',
                        'Бас әкімші: барлық құқық, команданы басқарады. Модератор: тапсырыстарды тексереді, шағымдарды, апелляцияларды және растауды қарайды, аккаунттарды шектейді. Оператор: хабарландыру шектеулері. Тек оқу: тек қарай алады. Рөл «Қолданушылар» қойындысында аккаунтты ашып тағайындалады; өз рөліңізді өзгерте алмайсыз.',
                        'Суперадмин: все права, управляет командой. Модератор: проверяет заявки, разбирает жалобы, апелляции и верификацию, ограничивает аккаунты. Оператор: ограничения уведомлений. Только чтение: только просмотр. Роль назначается на вкладке «Пользователи» в карточке аккаунта; свою роль изменить нельзя.',
                        "Super admin: all rights, manages the team. Moderator: reviews requests, handles reports, appeals and verification, restricts accounts. Operator: notification limits. Read only: view only. Roles are assigned on the “Users” tab in the account card; you can't change your own role.", ky: 'Супер админ: бардык укуктар, команданы башкарат. Модератор: суроо-талаптарды текшерет, арыздарды, даттанууларды жана текшерүүнү карайт, аккаунттарды чектейт. Оператор: билдирүү чектөөлөрү. Окуу гана: көрүү гана. Ролдор «Колдонуучулар» өтмөгүндөгү аккаунт карточкасында берилет; өз ролуңузду өзгөртө албайсыз.', uz: 'Super admin: barcha huquqlar, jamoani boshqaradi. Moderator: soʻrovlarni tekshiradi, shikoyatlar, apellyatsiyalar va tekshiruvni koʻradi, akkauntlarni cheklaydi. Operator: bildirishnoma cheklovlari. Faqat oʻqish: faqat koʻrish. Rollar “Foydalanuvchilar” boʻlimidagi akkaunt kartasida beriladi; oʻz rolingizni oʻzgartira olmaysiz.'),
                    style: YText.caption
                        .copyWith(color: YTokens.of(context).muted)),
                const SizedBox(height: YSpace.md),
                for (final u in list)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(u.name.isEmpty ? '?' : u.name),
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
              '${_actionName(e.action)}${e.target.isEmpty ? '' : ' · ${_targetName(e.target)}'}${e.title.isEmpty ? '' : tr3('「${e.title}」', ' «${e.title}»', ' «${e.title}»', ' “${e.title}”', ky: ' «${e.title}»', uz: ' “${e.title}”')}',
              style: YText.body),
          Text(
              '${e.by.isEmpty || e.by == 'system' ? tr3('自动审核', 'Автоматты тексеру', 'Автопроверка', 'Auto check', ky: 'Автоматтык текшерүү', uz: 'Avtomatik tekshiruv') : (e.byName.isEmpty ? e.by : e.byName)} · ${_date(e.at)}${e.reason.isEmpty ? '' : ' · ${_reasonLabel(e.reason)}'}',
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
          title: Text(tr3('操作记录', 'Әрекеттер журналы', 'Журнал действий', 'Action log', ky: 'Аракеттер журналы', uz: 'Amallar jurnali'))),
      body: _PagedList<AuditEntry>(
          key: const ValueKey('audit'),
          load: (p) => context.read(adminRepositoryProvider).audit(page: p),
          empty: tr3('还没有记录', 'Әзірге жазба жоқ', 'Записей пока нет', 'No entries yet', ky: 'Азырынча жазуулар жок', uz: 'Hozircha yozuvlar yoʻq'),
          item: (context, e) => _AuditRow(e)));
}

class _PushPolicyPage extends StatelessWidget {
  const _PushPolicyPage();

  static const _hours = ['', '20:00', '21:00', '22:00', '23:00', '00:00'];
  static const _ends = ['', '06:00', '07:00', '08:00', '09:00'];

  static String get _noQuiet => tr3('不限制', 'Шектеусіз', 'Не ограничено', 'Unlimited', ky: 'Чексиз', uz: 'Cheksiz');
  static String _cap(int n) => n == 0
      ? tr3('不限', 'Шексіз', 'Без лимита', 'No limit', ky: 'Чек жок', uz: 'Cheklov yoʻq')
      : tr3('$n 条', 'Күніне $n', '$n в день', '$n a day', ky: 'Күнүнө $n', uz: 'Kuniga $n');

  Future<void> _save(BuildContext context, PushPolicy p) => attempt(
      context, () => context.read(adminRepositoryProvider).savePushPolicy(p),
      success: tr3('已保存', 'Сақталды', 'Сохранено', 'Saved', ky: 'Сакталды', uz: 'Saqlandi'));

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canOperate = _may(context, AdminPerms.operate);
    final quietStart =
        tr3('免打扰开始', '«Мазаламау» басталуы', 'Начало тихих часов', 'Quiet hours start', ky: 'Тынч сааттардын башталышы', uz: 'Sokin soatlar boshlanishi');
    final quietEnd = tr3('免打扰结束', '«Мазаламау» аяқталуы', 'Конец тихих часов', 'Quiet hours end', ky: 'Тынч сааттардын аягы', uz: 'Sokin soatlar tugashi');
    final dailyCap =
        tr3('每人每日上限', 'Бір адамға күндік шек', 'Дневной лимит на человека', 'Daily limit per person', ky: 'Бир адамга күндүк чек', uz: 'Bir kishiga kunlik cheklov');
    return Scaffold(
        appBar: AppBar(title: Text(_pushTitle)),
        body: Live<PushPolicy>(
            provider: pushPolicyProvider,
            builder: (context, p) => ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: YSpace.gutter),
                    children: [
                      SettingsGroup(children: [
                        SettingsRow(
                            icon: Icons.bedtime_outlined,
                            title: quietStart,
                            value:
                                p.quietStart.isEmpty ? _noQuiet : p.quietStart,
                            onTap: canOperate
                                ? () async {
                                    final v = await pickOne<String>(
                                        context,
                                        quietStart,
                                        [
                                          for (final h in _hours)
                                            (h, h.isEmpty ? _noQuiet : h)
                                        ],
                                        selected: p.quietStart);
                                    if (v != null && context.mounted) {
                                      await _save(
                                          context,
                                          PushPolicy(
                                              quietStart: v,
                                              quietEnd: v.isEmpty
                                                  ? ''
                                                  : (p.quietEnd.isEmpty
                                                      ? '08:00'
                                                      : p.quietEnd),
                                              dailyCap: p.dailyCap));
                                    }
                                  }
                                : null),
                        SettingsRow(
                            icon: Icons.wb_sunny_outlined,
                            title: quietEnd,
                            value: p.quietEnd.isEmpty ? _noQuiet : p.quietEnd,
                            onTap: canOperate && p.quietStart.isNotEmpty
                                ? () async {
                                    final v = await pickOne<String>(
                                        context,
                                        quietEnd,
                                        [for (final h in _ends.skip(1)) (h, h)],
                                        selected: p.quietEnd);
                                    if (v != null && context.mounted) {
                                      await _save(
                                          context,
                                          PushPolicy(
                                              quietStart: p.quietStart,
                                              quietEnd: v,
                                              dailyCap: p.dailyCap));
                                    }
                                  }
                                : null),
                        SettingsRow(
                            icon: Icons.speed,
                            title: dailyCap,
                            value: _cap(p.dailyCap),
                            onTap: canOperate
                                ? () async {
                                    final v = await pickOne<int>(
                                        context,
                                        dailyCap,
                                        [
                                          for (final n in const [
                                            3,
                                            5,
                                            10,
                                            20,
                                            0
                                          ])
                                            (n, _cap(n)),
                                        ],
                                        selected: p.dailyCap);
                                    if (v != null && context.mounted) {
                                      await _save(
                                          context,
                                          PushPolicy(
                                              quietStart: p.quietStart,
                                              quietEnd: p.quietEnd,
                                              dailyCap: v));
                                    }
                                  }
                                : null),
                      ]),
                      Padding(
                          padding: const EdgeInsets.all(YSpace.sm),
                          child: Text(
                              tr3(
                                      '只限制点赞、点评和新需求提醒；报名、合作、验收等交易通知总会推送。时间按 UTC+5。消息列表不受影响。',
                                      'Тек ұнату, пікір және жаңа тапсырыс туралы хабарландырулар шектеледі; өтінім, келісім, қабылдау сияқты мәміле хабарландырулары әрдайым жіберіледі. Уақыт UTC+5 бойынша. Хабарлар тізіміне әсер етпейді.',
                                      'Ограничиваются только уведомления о лайках, отзывах и новых заявках; уведомления по сделкам (отклики, соглашения, приёмка) приходят всегда. Время по UTC+5. На список сообщений не влияет.',
                                      "Only notifications about likes, reviews and new requests are limited; deal notifications (responses, agreements, acceptance) always arrive. Times are UTC+5. Doesn't affect the message list.", ky: 'Жактыруулар, пикирлер жана жаңы суроо-талаптар жөнүндөгү билдирмелер гана чектелет; келишим билдирмелери (жооптор, макулдашуулар, кабыл алуу) ар дайым келет. Убакыт UTC+5. Билдирүүлөр тизмесине таасир этпейт.', uz: 'Faqat yoqtirishlar, sharhlar va yangi soʻrovlar haqidagi bildirishnomalar cheklanadi; bitim bildirishnomalari (javoblar, kelishuvlar, qabul qilish) har doim keladi. Vaqt UTC+5. Xabarlar roʻyxatiga taʼsir qilmaydi.') +
                                  (canOperate
                                      ? ''
                                      : tr3(
                                          '\n只有运营或超级管理员可以修改。',
                                          '\nТек оператор не бас әкімші өзгерте алады.',
                                          '\nМенять может только оператор или суперадмин.',
                                          '\nOnly an operator or super admin can change this.', ky: '\nМуну оператор же супер админ гана өзгөртө алат.', uz: '\nBuni faqat operator yoki super admin oʻzgartira oladi.')),
                              style: YText.caption.copyWith(color: t.muted))),
                    ])));
  }
}
