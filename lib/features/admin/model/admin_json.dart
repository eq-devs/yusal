import 'package:yusal/features/demand/model/demand_json.dart';
import 'package:yusal/features/me/model/me_json.dart';
import 'package:yusal/features/profile/model/profile_json.dart';
import 'package:yusal/features/shared/model/admin_models.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Admin models to and from yusal-api JSON.

Report reportFrom(Map<String, dynamic> j) => Report(
    id: j['id'] as String,
    reporterId: j['reporter_id'] as String,
    target: jsonEnum(ReportTarget.values, j['target'], ReportTarget.account),
    targetId: j['target_id'] as String,
    reason: j['reason'] as String? ?? '',
    createdAt: jsonTime(j['created_at']),
    status: jsonEnum(ReportStatus.values, j['status'], ReportStatus.open),
    handledBy: j['handled_by'] as String?,
    handledAt: jsonTimeOrNull(j['handled_at']),
    resolution: j['resolution'] as String? ?? '');

AuditEntry auditFrom(Map<String, dynamic> j) => AuditEntry(
    by: j['by'] as String? ?? '',
    at: jsonTime(j['at']),
    action: j['action'] as String? ?? '',
    targetId: j['target_id'] as String? ?? '',
    reason: j['reason'] as String? ?? '',
    target: j['target'] as String? ?? '',
    title: j['title'] as String? ?? '',
    byName: j['by_name'] as String? ?? '');

// ── back office ──
Paged<T> pagedFrom<T>(Object? v, T Function(Map<String, dynamic>) item) {
  final j = v! as Map<String, dynamic>;
  return Paged([for (final m in jsonMaps(j['items'])) item(m)],
      total: jsonInt(j['total']) ?? 0,
      page: jsonInt(j['page']) ?? 1,
      pageSize: jsonInt(j['page_size']) ?? 20);
}

ReportView reportViewFrom(Map<String, dynamic> j) => ReportView(
    report: reportFrom(j),
    reporterName: j['reporter_name'] as String? ?? '',
    targetTitle: j['target_title'] as String? ?? '',
    targetOwnerId: j['target_owner_id'] as String? ?? '',
    targetOwnerName: j['target_owner_name'] as String? ?? '',
    postId: j['post_id'] as String?);

PushPolicy policyFrom(Map<String, dynamic> j) => PushPolicy(
    quietStart: j['quiet_start'] as String? ?? '',
    quietEnd: j['quiet_end'] as String? ?? '',
    dailyCap: jsonInt(j['daily_cap']) ?? 0);

TodoList<T> _todo<T>(Object? v, T Function(Map<String, dynamic>) item) {
  final j = v as Map<String, dynamic>? ?? const {};
  return TodoList(jsonInt(j['count']) ?? 0,
      [for (final m in jsonMaps(j['items'])) item(m)]);
}

AdminTodo todoFrom(Map<String, dynamic> j,
        Cooperation Function(Map<String, dynamic>) coop) =>
    AdminTodo(
        review: _todo(j['review'], demandFrom),
        reports: _todo(j['reports'], reportFrom),
        appeals: _todo(j['appeals'], appealFrom),
        verifications: _todo(j['verifications'], verificationFrom),
        disputes: _todo(j['disputes'], coop),
        health: jsonStrings(j['health']));

Map<String, int> _ints(Object? v) => {
      for (final e in (v as Map<String, dynamic>? ?? const {}).entries)
        e.key: (e.value as num?)?.toInt() ?? 0
    };

AdminDashboard dashboardFrom(Map<String, dynamic> j) => AdminDashboard(
    today: _ints(j['today']),
    daily: [
      for (final d in jsonMaps(j['daily']))
        DashboardDay(d['day'] as String? ?? '',
            active: jsonInt(d['active']) ?? 0,
            demands: jsonInt(d['demands']) ?? 0,
            quotes: jsonInt(d['quotes']) ?? 0)
    ],
    funnel: [
      for (final f in jsonMaps(j['funnel']))
        (f['key'] as String? ?? '', jsonInt(f['count']) ?? 0)
    ],
    regions: [
      for (final r in jsonMaps(j['regions']))
        RegionSupply(r['region'] as String? ?? '',
            demands: jsonInt(r['demands']) ?? 0,
            workers: jsonInt(r['workers']) ?? 0)
    ],
    firstQuoteHours: (j['first_quote_hours'] as num?)?.toDouble(),
    totals: _ints(j['totals']));

AdminUserRow userRowFrom(Map<String, dynamic> j) => AdminUserRow(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    restricted: j['restricted'] == true || j['status'] == 'blocked',
    deleted: j['status'] == 'deleted',
    role: (j['admin_role'] as String?)?.nullIfEmpty,
    createdAt: jsonTimeOrNull(j['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0));

AccountDetail accountDetailFrom(
    Map<String, dynamic> j, Cooperation Function(Map<String, dynamic>) coop) {
  final a = j['account'] as Map<String, dynamic>;
  return AccountDetail(
      account: Account(
          id: a['id'] as String,
          phone: a['phone'] as String? ?? '',
          displayName: a['name'] as String? ?? '',
          createdAt: jsonTime(a['created_at']),
          deleted: a['status'] == 'deleted',
          restricted: a['restricted'] == true,
          role: (a['admin_role'] as String?)?.nullIfEmpty),
      email: a['email'] as String? ?? '',
      lastLogin: jsonTimeOrNull(a['last_login_at']),
      profiles: [for (final p in jsonMaps(j['profiles'])) profileFrom(p)],
      demands: [for (final d in jsonMaps(j['demands'])) demandFrom(d)],
      applications: jsonInt(j['applications']) ?? 0,
      cooperations: [for (final c in jsonMaps(j['cooperations'])) coop(c)],
      posts: [
        for (final p in jsonMaps(j['posts']))
          (
            id: p['id'] as String,
            title: p['title'] as String? ?? '',
            hidden: p['status'] == 'hidden',
            featured: p['featured'] == true
          )
      ],
      reportsAbout: [
        for (final r in jsonMaps(j['reports_about'])) reportFrom(r)
      ],
      reportsFiled: jsonInt(j['reports_filed']) ?? 0,
      appeals: [for (final x in jsonMaps(j['appeals'])) appealFrom(x)],
      audit: [for (final e in jsonMaps(j['audit'])) auditFrom(e)],
      banned: a['status'] == 'blocked',
      methods: [for (final m in (a['methods'] as List? ?? const [])) '$m']);
}

FeedbackItem feedbackFrom(Map<String, dynamic> j) => FeedbackItem(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    accountId: (j['account_id'] as String?)?.nullIfEmpty,
    context: {
      for (final e in ((j['context'] as Map?) ?? const {}).entries)
        if ('${e.value}'.isNotEmpty) '${e.key}': '${e.value}'
    },
    createdAt: jsonTime(j['created_at']),
    handledAt: jsonTimeOrNull(j['handled_at']));

TrendDay trendFrom(Map<String, dynamic> j) => TrendDay(
    j['date'] as String? ?? '',
    jsonInt(j['users']) ?? 0,
    jsonInt(j['posts']) ?? 0,
    jsonInt(j['demands']) ?? 0,
    jsonInt(j['quotes']) ?? 0);
