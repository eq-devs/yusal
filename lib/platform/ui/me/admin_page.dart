import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../data/http/http_backend.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../components.dart';
import '../demand/demand_detail_page.dart';
import '../home/post_page.dart';
import '../l10n.dart';
import '../profile/profile_page.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

// The back office, in Chinese only like gooddeal's: a to-do first screen,
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
              body: const EmptyState(
                  icon: Icons.lock_outline, title: '没有后台权限'));
        }
        final pages = [
          _Workbench(open: _open),
          _ReviewTab(kind: _reviewKind),
          const _UsersTab(),
          const _MoreTab(),
        ];
        return Scaffold(
            appBar: AppBar(
                title: Text(const ['工作台', '审核', '用户', '更多'][_tab]),
                actions: [
                  Padding(
                      padding: const EdgeInsets.only(right: YSpace.lg),
                      child: Center(child: StatusPill(roleName(me.role)))),
                ]),
            body: IndexedStack(index: _tab, children: pages),
            bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined), label: '工作台'),
                  NavigationDestination(
                      icon: Icon(Icons.fact_check_outlined), label: '审核'),
                  NavigationDestination(
                      icon: Icon(Icons.people_outline), label: '用户'),
                  NavigationDestination(icon: Icon(Icons.more_horiz), label: '更多'),
                ]));
      });
}

String roleName(String? role) => switch (role) {
      AdminRoles.superadmin => '超级管理员',
      AdminRoles.moderator => '审核员',
      AdminRoles.operator => '运营',
      AdminRoles.viewer => '只读',
      _ => '无',
    };

bool _may(BuildContext context, String perm) =>
    context.repos.currentAccount?.can(perm) ?? false;

String _date(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.month}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String _reportTargetName(ReportTarget t) => switch (t) {
      ReportTarget.demand => '需求',
      ReportTarget.profile => '名片',
      ReportTarget.account => '账号',
      ReportTarget.message => '消息',
      ReportTarget.post => '房子',
      ReportTarget.comment => '评论',
    };

String _targetName(String t) => switch (t) {
      'demand' => '需求',
      'profile' => '名片',
      'account' => '账号',
      'message' => '消息',
      'post' => '房子',
      'comment' => '评论',
      _ => t,
    };

/// A reason as moderators read it: preset codes in Chinese.
String _reasonZh(String r) => switch (r) {
      'code:contact' => '含联系方式',
      'code:fake' => '虚假信息',
      'code:illegal' => '违规内容',
      'code:incomplete' => '信息不全',
      'code:duplicate' => '重复发布',
      'code:abuse' => '辱骂骚扰',
      'code:spam' => '广告引流',
      'code:ok' => '未发现问题',
      _ when r.startsWith('banned:') => '命中禁用词：${r.substring(7)}',
      _ => r,
    };

String _actionName(String a) => switch (a) {
      'approve' => '通过需求',
      'reject' => '拒绝需求',
      'uphold' => '举报成立',
      'dismiss' => '驳回举报',
      'restrict' => '限制账号',
      'unrestrict' => '解除限制',
      'post_hide' => '隐藏房子',
      'post_show' => '恢复房子',
      'appeal_accept' => '申诉成立',
      'appeal_reject' => '申诉驳回',
      'verify_approve' => '认证通过',
      'verify_reject' => '认证驳回',
      'role_revoke' => '撤销角色',
      _ when a.startsWith('role_grant:') => '授予${roleName(a.substring(11))}',
      _ => a,
    };

/// Picks a preset reason or takes the moderator's own words.
Future<String?> _pickReason(BuildContext context, String title,
    {List<String> codes = const [
      'contact', 'fake', 'illegal', 'incomplete', 'duplicate', 'abuse', 'spam'
    ]}) async {
  final v = await pickOne<String>(context, title, [
    for (final c in codes) ('code:$c', _reasonZh('code:$c')),
    ('', '自己填写…'),
  ]);
  if (v == null || !context.mounted) return null;
  if (v.isNotEmpty) return v;
  return askText(context, title, hint: '用户会看到这段说明');
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
                                child: const Text('加载更多'))),
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
                                'sweep_stalled' => '定时任务超过 5 分钟没有运行：到期、提醒和单方结束会停住，请检查服务器。',
                                'manual_review_on' => '已开启人工审核：新需求要等审核员通过才会公开。',
                                _ => h,
                              },
                              warn: h != 'manual_review_on')),
                    Text(todo.total == 0 ? '没有待办，一切正常' : '待办 ${todo.total} 项',
                        style: display(size: 22)),
                    const SizedBox(height: YSpace.md),
                    _TodoTile(
                        icon: Icons.fact_check_outlined,
                        title: '需求审核',
                        count: todo.review.count,
                        lines: [for (final x in todo.review.items) x.current.title],
                        onTap: () => open(_Review.demands)),
                    _TodoTile(
                        icon: Icons.flag_outlined,
                        title: '举报',
                        count: todo.reports.count,
                        lines: [
                          for (final x in todo.reports.items)
                            '${_reportTargetName(x.target)} · ${_reasonZh(x.reason)}'
                        ],
                        onTap: () => open(_Review.reports)),
                    _TodoTile(
                        icon: Icons.gavel_outlined,
                        title: '申诉',
                        count: todo.appeals.count,
                        lines: [for (final x in todo.appeals.items) x.text],
                        onTap: () => open(_Review.appeals)),
                    _TodoTile(
                        icon: Icons.verified_outlined,
                        title: '工人认证',
                        count: todo.verifications.count,
                        lines: [for (final x in todo.verifications.items) x.name],
                        onTap: () => open(_Review.verifications)),
                    _TodoTile(
                        icon: Icons.report_problem_outlined,
                        title: '超过 3 天未解决的争议',
                        count: todo.disputes.count,
                        lines: [
                          for (final c in todo.disputes.items)
                            c.endRequest?.dispute ?? '节点验收有异议'
                        ]),
                    const SizedBox(height: YSpace.xl),
                    Text('今天', style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    Wrap(spacing: YSpace.sm, runSpacing: YSpace.sm, children: [
                      for (final (k, label) in const [
                        ('active', '活跃设备'),
                        ('new_users', '新用户'),
                        ('new_posts', '新房子'),
                        ('new_demands', '新需求'),
                        ('new_quotes', '新报价'),
                        ('new_cooperations', '新合作'),
                        ('inspections', '节点验收'),
                      ])
                        _Stat(label, d.today[k] ?? 0),
                    ]),
                    const SizedBox(height: YSpace.xl),
                    Text('近 7 天', style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    _Bars(days: d.daily),
                    const SizedBox(height: YSpace.xl),
                    Text('从房子到验收', style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    _Funnel(steps: d.funnel),
                    if (d.firstQuoteHours != null) ...[
                      const SizedBox(height: YSpace.sm),
                      Text('需求发布后收到第一个报价：中位 ${d.firstQuoteHours!.toStringAsFixed(1)} 小时',
                          style: YText.caption.copyWith(color: t.muted)),
                    ],
                    const SizedBox(height: YSpace.xl),
                    Text('各地区供需（招募中的需求 / 可接活的名片）', style: YText.bodyStrong),
                    const SizedBox(height: YSpace.sm),
                    YCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          if (d.regions.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(YSpace.lg),
                                child: Text('暂无数据')),
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
                        '累计：用户 ${d.totals['users'] ?? 0} · 房子 ${d.totals['posts'] ?? 0} · 名片 ${d.totals['profiles'] ?? 0} · 需求 ${d.totals['demands'] ?? 0}',
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
                      Text('活跃 ${d.active}',
                          style: YText.caption.copyWith(color: t.muted)),
                    ]))),
        ]));
  }
}

class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});
  final List<(String, int)> steps;
  static const _names = {
    'posts': '公开的房子',
    'reuses': '被复用',
    'demands': '发布的需求',
    'quoted': '收到报价的需求',
    'cooperations': '达成合作',
    'inspected': '有节点验收',
    'reviews': '评价',
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
              SizedBox(width: 110, child: Text(_names[k] ?? k, style: YText.caption)),
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
                options: const [
                  (_Review.demands, '需求'),
                  (_Review.reports, '举报'),
                  (_Review.appeals, '申诉'),
                  (_Review.verifications, '认证'),
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
      final r = await _pickReason(context, '拒绝 ${_selected.length} 个需求的原因');
      if (r == null || !mounted) return;
      reason = r;
    }
    final res = await attempt(context,
        () => context.repos.decideMany(_selected.toList(), approve, reason: reason));
    if (res == null || !mounted) return;
    toast(context,
        res.failed.isEmpty ? '已处理 ${res.done} 个' : '已处理 ${res.done} 个，${res.failed.length} 个状态已变化未处理');
    setState(_selected.clear);
  }

  Future<bool> _reject(Demand d) async {
    final r = await _pickReason(context, '拒绝原因');
    if (r == null || !mounted) return false;
    return await attempt(context, () async {
          await context.repos.reject(d.id, r);
          return true;
        }, success: '已拒绝') ==
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
                  Text('已选 ${_selected.length}'),
                  const Spacer(),
                  TextButton(onPressed: () => setState(_selected.clear), child: const Text('取消')),
                  TextButton(onPressed: () => _batch(false), child: const Text('批量拒绝')),
                  FilledButton(onPressed: () => _batch(true), child: const Text('批量通过')),
                ]))),
      Expanded(
          child: _PagedList<Demand>(
              key: const ValueKey('queue'),
              load: (p) => context.repos.reviewQueue(page: p),
              empty: '没有待审核的需求',
              header: canModerate
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: YSpace.sm),
                      child: Text('右滑通过，左滑拒绝，长按多选',
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
                    background: _SwipeBg(color: t.ok, icon: Icons.check, label: '通过', left: true),
                    secondaryBackground:
                        _SwipeBg(color: t.crit, icon: Icons.close, label: '拒绝', left: false),
                    confirmDismiss: (dir) async {
                      if (dir == DismissDirection.startToEnd) {
                        return await attempt(context, () async {
                              await context.repos.approve(d.id);
                              return true;
                            }, success: '已通过') ==
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
                      '${regionName(v.region)} · ${demandTypeName(demand.type)} · 第 ${v.no} 版 · ${_date(demand.createdAt)}',
                      style: YText.caption.copyWith(color: t.muted)),
                  if (demand.rejectReason != null && demand.status == DemandStatus.rejected)
                    Text('拒绝原因：${_reasonZh(demand.rejectReason!)}',
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
        ? await _pickReason(context, '举报成立：给对方的说明')
        : await _pickReason(context, '驳回举报：给举报人的说明', codes: const ['ok']);
    if (note == null || !mounted) return;
    await attempt(context, () => context.repos.resolveReport(v.report.id, upheld, note),
        success: upheld ? '已处理，内容已下架/账号已限制，双方已通知' : '已驳回，举报人已通知');
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
          options: const [
            (ReportStatus.open, '待处理'),
            (ReportStatus.upheld, '已成立'),
            (ReportStatus.dismissed, '已驳回'),
            (null, '全部'),
          ],
          selected: _status,
          onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<ReportView>(
              key: ValueKey('reports-$_status'),
              load: (p) => context.repos.reports(status: _status, page: p),
              empty: '没有举报',
              item: (context, v) {
                final r = v.report;
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
                          Text('原因：${_reasonZh(r.reason)}'),
                          Text(
                              '举报人 ${v.reporterName.isEmpty ? '—' : v.reporterName} · 被举报 ${v.targetOwnerName.isEmpty ? '—' : v.targetOwnerName} · ${_date(r.createdAt)}',
                              style: YText.caption.copyWith(color: t.muted)),
                          if (r.status != ReportStatus.open)
                            Text(
                                '${r.status == ReportStatus.upheld ? '成立' : '驳回'}：${_reasonZh(r.resolution)}',
                                style: YText.caption.copyWith(color: t.muted)),
                          if (r.status == ReportStatus.open && canModerate) ...[
                            const SizedBox(height: YSpace.sm),
                            Row(children: [
                              if (v.targetOwnerId.isNotEmpty)
                                TextButton(
                                    onPressed: () => pushPage<void>(context,
                                        (_) => AccountDetailPage(accountId: v.targetOwnerId)),
                                    child: const Text('看此人')),
                              const Spacer(),
                              OutlinedButton(
                                  onPressed: () => _resolve(v, false), child: const Text('驳回')),
                              const SizedBox(width: YSpace.sm),
                              FilledButton(
                                  onPressed: () => _resolve(v, true),
                                  child: Text(switch (r.target) {
                                    ReportTarget.account || ReportTarget.message => '成立并限制',
                                    ReportTarget.comment => '成立并删除',
                                    _ => '成立并下架',
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
    final note = await askText(context, accept ? '申诉成立：说明' : '维持原处理：说明',
        hint: '用户会看到这段说明');
    if (note == null || !mounted) return;
    await attempt(context, () => context.repos.resolveAppeal(a.id, accept, note),
        success: accept ? '已恢复并通知用户' : '已回复用户');
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<AppealStatus?>(
          options: const [
            (AppealStatus.open, '待处理'),
            (AppealStatus.accepted, '已成立'),
            (AppealStatus.rejected, '已驳回'),
            (null, '全部'),
          ],
          selected: _status,
          onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<Appeal>(
              key: ValueKey('appeals-$_status'),
              load: (p) => context.repos.appeals(status: _status, page: p),
              empty: '没有申诉',
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
                          Text('回复：${_reasonZh(a.resolution)}',
                              style: YText.caption.copyWith(color: t.muted)),
                        if (a.status == AppealStatus.open && canModerate)
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            OutlinedButton(
                                onPressed: () => _resolve(a, false), child: const Text('维持')),
                            const SizedBox(width: YSpace.sm),
                            FilledButton(
                                onPressed: () => _resolve(a, true), child: const Text('成立并恢复')),
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
        : await askText(context, '驳回原因', hint: '例如：照片看不出是本人施工的现场');
    if (note == null || !mounted) return;
    await attempt(context, () => context.repos.resolveVerification(v.id, approve, note),
        success: approve ? '已通过，名片显示“已核验”' : '已驳回并通知');
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canModerate = _may(context, AdminPerms.moderate);
    return Column(children: [
      _Chips<VerificationStatus?>(
          options: const [
            (VerificationStatus.pending, '待审核'),
            (VerificationStatus.approved, '已通过'),
            (VerificationStatus.rejected, '已驳回'),
            (null, '全部'),
          ],
          selected: _status,
          onSelect: (v) => setState(() => _status = v)),
      Expanded(
          child: _PagedList<Verification>(
              key: ValueKey('verif-$_status'),
              load: (p) => context.repos.verifications(status: _status, page: p),
              empty: '没有认证申请',
              item: (context, v) => Padding(
                  padding: const EdgeInsets.only(bottom: YSpace.sm),
                  child: YCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InkWell(
                        onTap: () =>
                            pushPage<void>(context, (_) => ProfilePage(profileId: v.profileId)),
                        child: Text(v.name, style: YText.bodyStrong)),
                    Text('${v.ownerName} · 电话 ${v.phone} · ${_date(v.createdAt)}',
                        style: YText.caption.copyWith(color: t.muted)),
                    if (v.note.isNotEmpty) Text(v.note),
                    const SizedBox(height: YSpace.sm),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in v.photos) _Photo(p),
                    ]),
                    if (v.resolution.isNotEmpty)
                      Text('说明：${v.resolution}',
                          style: YText.caption.copyWith(color: t.muted)),
                    if (v.status == VerificationStatus.pending && canModerate)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        OutlinedButton(
                            onPressed: () => _resolve(v, false), child: const Text('驳回')),
                        const SizedBox(width: YSpace.sm),
                        FilledButton(
                            onPressed: () => _resolve(v, true), child: const Text('通过')),
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
              controller: search, hint: '名字、邮箱或账号 ID', onChanged: typed)),
      _Chips<_UserFilter>(
          options: const [
            (_UserFilter.all, '全部'),
            (_UserFilter.restricted, '受限'),
            (_UserFilter.team, '后台成员'),
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
              empty: '没有找到用户',
              item: (context, u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(u.name.isEmpty ? '?' : u.name, size: 40),
                  title: Text(u.name.isEmpty ? '（未命名）' : u.name),
                  subtitle: Text([
                    if (u.email.isNotEmpty) u.email,
                    '注册 ${_date(u.createdAt)}',
                  ].join(' · ')),
                  trailing: Wrap(spacing: 4, children: [
                    if (u.role != null) StatusPill(roleName(u.role)),
                    if (u.restricted) StatusPill('受限', color: t.crit),
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
        ? await askText(context, '解除限制：说明', hint: '用户会看到这段说明')
        : await _pickReason(context, '限制原因', codes: const ['fake', 'abuse', 'spam', 'illegal']);
    if (note == null || !context.mounted) return;
    await attempt(context, () => context.repos.setRestriction(a.id, !a.restricted, note),
        success: a.restricted ? '已解除限制' : '已限制：只能浏览，不能发布、报名和发消息');
  }

  Future<void> _role(BuildContext context, Account a) async {
    final v = await pickOne<String>(context, '后台角色', [
      for (final r in AdminRoles.all) (r, roleName(r)),
      ('', '无（撤销）'),
    ], selected: a.role ?? '');
    if (v == null || !context.mounted) return;
    await attempt(context, () => context.repos.setRole(a.id, v.isEmpty ? null : v),
        success: '已更新角色');
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final me = context.repos.currentAccount;
    return Scaffold(
        appBar: AppBar(title: const Text('账号详情')),
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
                    Text(a.displayName.isEmpty ? '（未命名）' : a.displayName,
                        style: display(size: 22)),
                    Text(
                        [
                          if (d.email.isNotEmpty) d.email,
                          if (a.phone.isNotEmpty) a.phone,
                          '注册 ${_date(a.createdAt)}',
                          if (d.lastLogin != null) '最近登录 ${_date(d.lastLogin!)}',
                        ].join(' · '),
                        style: YText.caption.copyWith(color: t.muted)),
                  ])),
                ]),
                const SizedBox(height: YSpace.sm),
                Wrap(spacing: 6, children: [
                  if (a.role != null) StatusPill(roleName(a.role)),
                  if (a.restricted) StatusPill('受限', color: t.crit),
                  if (a.deleted) const StatusPill('已注销'),
                ]),
                if (!self && !a.deleted) ...[
                  const SizedBox(height: YSpace.md),
                  Wrap(spacing: YSpace.sm, children: [
                    if (_may(context, AdminPerms.moderate) && a.role == null)
                      OutlinedButton(
                          onPressed: () => _restrict(context, a),
                          child: Text(a.restricted ? '解除限制' : '限制账号')),
                    if (_may(context, AdminPerms.team) && !a.restricted)
                      OutlinedButton(
                          onPressed: () => _role(context, a), child: const Text('设置后台角色')),
                  ]),
                ],
                const SizedBox(height: YSpace.lg),
                Text('报价/报名 ${d.applications} 次 · 举报他人 ${d.reportsFiled} 次',
                    style: YText.caption.copyWith(color: t.muted)),
                if (d.profiles.isNotEmpty) ...[
                  const SectionTitle('名片'),
                  for (final p in d.profiles)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name),
                        subtitle: Text(
                            '${p.status == ProfileStatus.hidden ? '隐藏' : '公开'}${p.verified ? ' · 已核验' : ''}'),
                        onTap: () =>
                            pushPage<void>(context, (_) => ProfilePage(profileId: p.id))),
                ],
                if (d.posts.isNotEmpty) ...[
                  const SectionTitle('房子'),
                  for (final p in d.posts)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.title),
                        subtitle: Text(p.hidden ? '已隐藏' : '公开'),
                        onTap: () => pushPage<void>(context, (_) => PostPage(postId: p.id)),
                        trailing: _may(context, AdminPerms.moderate)
                            ? TextButton(
                                onPressed: () async {
                                  final note = p.hidden
                                      ? await askText(context, '恢复说明')
                                      : await _pickReason(context, '隐藏原因');
                                  if (note == null || !context.mounted) return;
                                  await attempt(context,
                                      () => context.repos.setPostHidden(p.id, !p.hidden, note));
                                },
                                child: Text(p.hidden ? '恢复' : '隐藏'))
                            : null),
                ],
                if (d.demands.isNotEmpty) ...[
                  const SectionTitle('需求'),
                  for (final x in d.demands)
                    _DemandCard(
                        demand: x,
                        onTap: () =>
                            pushPage<void>(context, (_) => DemandDetailPage(demandId: x.id))),
                ],
                if (d.cooperations.isNotEmpty) ...[
                  SectionTitle('合作 ${d.cooperations.length}'),
                  for (final c in d.cooperations)
                    Text(
                        '${_date(c.createdAt)} · ${c.status.name}${c.endRequest?.dispute != null ? ' · 争议：${c.endRequest!.dispute}' : ''}',
                        style: YText.caption),
                ],
                if (d.reportsAbout.isNotEmpty) ...[
                  const SectionTitle('被举报'),
                  for (final r in d.reportsAbout)
                    Text(
                        '${_date(r.createdAt)} · ${_reportTargetName(r.target)} · ${_reasonZh(r.reason)} · ${switch (r.status) {
                          ReportStatus.open => '待处理',
                          ReportStatus.upheld => '成立',
                          ReportStatus.dismissed => '驳回',
                        }}',
                        style: YText.caption),
                ],
                if (d.appeals.isNotEmpty) ...[
                  const SectionTitle('申诉'),
                  for (final x in d.appeals)
                    Text('${_date(x.createdAt)} · ${_targetName(x.target)} · ${x.text}',
                        style: YText.caption),
                ],
                if (d.audit.isNotEmpty) ...[
                  const SectionTitle('处理记录'),
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
            SettingsGroup(title: '内容', children: [
              SettingsRow(
                  icon: Icons.list_alt,
                  title: '全部需求',
                  subtitle: '按状态筛选、搜索标题，可下架已公开的需求',
                  onTap: () => pushPage<void>(context, (_) => const _AllDemandsPage())),
            ]),
            SettingsGroup(title: '团队与记录', children: [
              SettingsRow(
                  icon: Icons.badge_outlined,
                  title: '后台成员',
                  onTap: () => pushPage<void>(context, (_) => const _TeamPage())),
              SettingsRow(
                  icon: Icons.history,
                  title: '操作记录',
                  subtitle: '每一个决定：谁、何时、为什么',
                  onTap: () => pushPage<void>(context, (_) => const AuditPage())),
            ]),
            SettingsGroup(title: '推送', children: [
              SettingsRow(
                  icon: Icons.notifications_paused_outlined,
                  title: '推送节制',
                  subtitle: '平台免打扰时段与每人每日上限',
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
        appBar: AppBar(title: const Text('全部需求')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(YSpace.gutter, YSpace.sm, YSpace.gutter, 0),
              child: SearchField(controller: search, hint: '搜索标题', onChanged: typed)),
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
                (null, '全部'),
              ],
              selected: _status,
              onSelect: (v) => setState(() => _status = v)),
          Expanded(
              child: _PagedList<Demand>(
                  key: ValueKey('all-$_status-$_q'),
                  load: (p) => context.repos.adminDemands(status: _status, query: _q, page: p),
                  empty: '没有需求',
                  item: (context, d) => _DemandCard(
                      demand: d,
                      onTap: () =>
                          pushPage<void>(context, (_) => DemandDetailPage(demandId: d.id)),
                      onLongPress: canModerate &&
                              (d.status == DemandStatus.open || d.status == DemandStatus.paused)
                          ? () async {
                              final r = await _pickReason(context, '下架原因');
                              if (r == null || !context.mounted) return;
                              await attempt(context, () => context.repos.reject(d.id, r),
                                  success: '已下架');
                            }
                          : null))),
        ]));
  }
}

class _TeamPage extends StatelessWidget {
  const _TeamPage();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('后台成员')),
      body: Live<List<AdminUserRow>>(
          load: (r) => r.team(),
          builder: (context, list) => ListView(padding: const EdgeInsets.all(YSpace.gutter), children: [
                Text(
                    '超级管理员：全部权限，管理团队；审核员：审核需求、处理举报申诉与认证、限制账号；运营：推送节制；只读：只能查看。角色在“用户”里点开账号设置，不能改自己的角色。',
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
              '${_actionName(e.action)}${e.target.isEmpty ? '' : ' · ${_targetName(e.target)}'}${e.title.isEmpty ? '' : '「${e.title}」'}',
              style: YText.body),
          Text(
              '${e.by.isEmpty || e.by == 'system' ? '自动审核' : (e.byName.isEmpty ? e.by : e.byName)} · ${_date(e.at)}${e.reason.isEmpty ? '' : ' · ${_reasonZh(e.reason)}'}',
              style: YText.caption.copyWith(color: t.muted)),
        ]));
  }
}

/// The audit log: every decision with who, when and why.
class AuditPage extends StatelessWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('操作记录')),
      body: _PagedList<AuditEntry>(
          key: const ValueKey('audit'),
          load: (p) => context.repos.audit(page: p),
          empty: '还没有记录',
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

  Future<void> _save(PushPolicy p) =>
      attempt(context, () => context.repos.savePushPolicy(p), success: '已保存');

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final canOperate = _may(context, AdminPerms.operate);
    return Scaffold(
        appBar: AppBar(title: const Text('推送节制')),
        body: Live<PushPolicy>(
            load: (r) => r.pushPolicy(),
            builder: (context, p) => ListView(
                    padding: const EdgeInsets.symmetric(horizontal: YSpace.gutter),
                    children: [
                      SettingsGroup(children: [
                        SettingsRow(
                            icon: Icons.bedtime_outlined,
                            title: '免打扰开始',
                            value: p.quietStart.isEmpty ? '不限制' : p.quietStart,
                            onTap: canOperate
                                ? () async {
                                    final v = await pickOne<String>(context, '免打扰开始',
                                        [for (final h in _hours) (h, h.isEmpty ? '不限制' : h)],
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
                            title: '免打扰结束',
                            value: p.quietEnd.isEmpty ? '不限制' : p.quietEnd,
                            onTap: canOperate && p.quietStart.isNotEmpty
                                ? () async {
                                    final v = await pickOne<String>(context, '免打扰结束',
                                        [for (final h in _ends.skip(1)) (h, h)],
                                        selected: p.quietEnd);
                                    if (v != null)
                                      await _save(PushPolicy(
                                          quietStart: p.quietStart, quietEnd: v, dailyCap: p.dailyCap));
                                  }
                                : null),
                        SettingsRow(
                            icon: Icons.speed,
                            title: '每人每日上限',
                            value: p.dailyCap == 0 ? '不限' : '${p.dailyCap} 条',
                            onTap: canOperate
                                ? () async {
                                    final v = await pickOne<int>(context, '每人每日上限', [
                                      for (final n in const [3, 5, 10, 20, 0])
                                        (n, n == 0 ? '不限' : '$n 条'),
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
                              '只限制点赞、点评和新需求提醒；报名、合作、验收等交易通知总会推送。时间按 UTC+5。消息列表不受影响。${canOperate ? '' : '\n只有运营或超级管理员可以修改。'}',
                              style: YText.caption.copyWith(color: t.muted))),
                    ])));
  }
}
