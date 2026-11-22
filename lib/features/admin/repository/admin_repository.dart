import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/api/codec.dart';
import 'package:yusal/features/shared/model/admin_models.dart';
import 'package:yusal/features/shared/model/models.dart';

/// The back office. Every call checks the caller's role.

/// The back office. Every call checks the caller's role.
abstract interface class AdminRepository {
  Future<AdminTodo> todo();
  Future<AdminDashboard> dashboard();
  Future<Paged<Demand>> reviewQueue({int page = 1, int pageSize = 20});
  Future<Paged<Demand>> adminDemands(
      {DemandStatus? status,
      String query = '',
      int page = 1,
      int pageSize = 20});
  Future<void> approve(String demandId);

  /// [reason] is free text or a preset code (`code:<name>`).
  Future<void> reject(String demandId, String reason);
  Future<BatchResult> decideMany(List<String> ids, bool approve,
      {String reason = ''});
  Future<Paged<ReportView>> reports(
      {ReportStatus? status, int page = 1, int pageSize = 20});
  Future<void> resolveReport(String reportId, bool upheld, String note);
  Future<Paged<Appeal>> appeals(
      {AppealStatus? status, int page = 1, int pageSize = 20});
  Future<void> resolveAppeal(String id, bool accept, String note);
  Future<Paged<Verification>> verifications(
      {VerificationStatus? status, int page = 1, int pageSize = 20});
  Future<void> resolveVerification(String id, bool approve, String note);
  Future<void> setRestriction(String accountId, bool restricted, String note);
  Future<void> setPostHidden(String postId, bool hidden, String note);
  Future<Paged<AuditEntry>> audit(
      {String? by, String? targetId, int page = 1, int pageSize = 20});
  Future<Paged<AdminUserRow>> users(
      {String query = '',
      bool restricted = false,
      bool admins = false,
      int page = 1,
      int pageSize = 20});
  Future<List<AdminUserRow>> team();
  Future<void> setRole(String accountId, String? role);
  Future<AccountDetail> accountDetail(String accountId);
  Future<PushPolicy> pushPolicy();
  Future<PushPolicy> savePushPolicy(PushPolicy policy);
}

final adminRepositoryProvider = Provider<AdminRepository>(
    (ref) => HttpAdminRepository(ref.watch(apiClientProvider)));

/// [AdminRepository] over yusal-api.
final class HttpAdminRepository implements AdminRepository {
  HttpAdminRepository(this.api);
  final ApiClient api;

  Future<Paged<T>> _paged<T>(String path, T Function(Map<String, dynamic>) item,
          {int page = 1,
          int pageSize = 20,
          Map<String, String> query = const {}}) async =>
      pagedFrom(
          await api.request('GET', path, query: {
            ...query,
            'page': '$page',
            'page_size': '$pageSize',
          }),
          item);

  @override
  Future<AdminTodo> todo() async => todoFrom(
      await api.request('GET', '/admin/todo') as Map<String, dynamic>,
      api.plainCooperation);

  @override
  Future<AdminDashboard> dashboard() async => dashboardFrom(
      await api.request('GET', '/admin/dashboard') as Map<String, dynamic>);

  @override
  Future<Paged<Demand>> reviewQueue({int page = 1, int pageSize = 20}) =>
      _paged('/admin/review-queue', demandFrom, page: page, pageSize: pageSize);

  @override
  Future<Paged<Demand>> adminDemands(
          {DemandStatus? status,
          String query = '',
          int page = 1,
          int pageSize = 20}) =>
      _paged('/admin/demands', demandFrom,
          page: page,
          pageSize: pageSize,
          query: {
            if (status != null) 'status': status.name,
            if (query.trim().isNotEmpty) 'q': query.trim(),
          });

  @override
  Future<void> approve(String demandId) async {
    await api.write('POST', '/admin/demands/$demandId/approve');
  }

  @override
  Future<void> reject(String demandId, String reason) async {
    await api.write('POST', '/admin/demands/$demandId/reject',
        body: {'reason': reason});
  }

  @override
  Future<BatchResult> decideMany(List<String> ids, bool approve,
      {String reason = ''}) async {
    final j = await api.write('POST', '/admin/demands/batch',
            body: {'ids': ids, 'approve': approve, 'reason': reason})
        as Map<String, dynamic>;
    return BatchResult(_int(j['done']),
        [for (final f in j['failed'] as List? ?? const []) f as String]);
  }

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Future<Paged<ReportView>> reports(
          {ReportStatus? status, int page = 1, int pageSize = 20}) =>
      _paged('/admin/reports', reportViewFrom,
          page: page,
          pageSize: pageSize,
          query: {if (status != null) 'status': status.name});

  @override
  Future<void> resolveReport(String reportId, bool upheld, String note) async {
    await api.write('POST', '/admin/reports/$reportId/resolve',
        body: {'upheld': upheld, 'note': note});
  }

  @override
  Future<Paged<Appeal>> appeals(
          {AppealStatus? status, int page = 1, int pageSize = 20}) =>
      _paged('/admin/appeals', appealFrom,
          page: page,
          pageSize: pageSize,
          query: {if (status != null) 'status': status.name});

  @override
  Future<void> resolveAppeal(String id, bool accept, String note) async {
    await api.write('POST', '/admin/appeals/$id/resolve',
        body: {'accept': accept, 'note': note});
  }

  @override
  Future<Paged<Verification>> verifications(
          {VerificationStatus? status, int page = 1, int pageSize = 20}) =>
      _paged('/admin/verifications', verificationFrom,
          page: page,
          pageSize: pageSize,
          query: {if (status != null) 'status': status.name});

  @override
  Future<void> resolveVerification(String id, bool approve, String note) async {
    await api.write('POST', '/admin/verifications/$id/resolve',
        body: {'accept': approve, 'note': note});
  }

  @override
  Future<void> setRestriction(
      String accountId, bool restricted, String note) async {
    await api.write('POST', '/admin/accounts/$accountId/restriction',
        body: {'restricted': restricted, 'note': note});
  }

  @override
  Future<void> setPostHidden(String postId, bool hidden, String note) async {
    await api.write('POST', '/admin/posts/$postId/visibility',
        body: {'hidden': hidden, 'note': note});
  }

  @override
  Future<Paged<AuditEntry>> audit(
          {String? by, String? targetId, int page = 1, int pageSize = 20}) =>
      _paged('/admin/audit', auditFrom, page: page, pageSize: pageSize, query: {
        if (by != null) 'by': by,
        if (targetId != null) 'target_id': targetId,
      });

  @override
  Future<Paged<AdminUserRow>> users(
          {String query = '',
          bool restricted = false,
          bool admins = false,
          int page = 1,
          int pageSize = 20}) =>
      _paged('/admin/users', userRowFrom,
          page: page,
          pageSize: pageSize,
          query: {
            if (query.trim().isNotEmpty) 'q': query.trim(),
            if (restricted) 'restricted': 'true',
            if (admins) 'admins': 'true',
          });

  @override
  Future<List<AdminUserRow>> team() async =>
      [for (final j in await api.getList('/admin/team')) userRowFrom(j)];

  @override
  Future<void> setRole(String accountId, String? role) async {
    await api.write('PUT', '/admin/users/$accountId/role',
        body: {'role': role ?? ''});
  }

  @override
  Future<AccountDetail> accountDetail(String accountId) async {
    final j = await api.request('GET', '/admin/accounts/$accountId')
        as Map<String, dynamic>;
    return accountDetailFrom(j, api.plainCooperation);
  }

  // ── back office, HTTP only ──

  Future<void> setBanned(String accountId, bool banned, String note) =>
      api.write('POST', '/admin/accounts/$accountId/ban',
          body: {'banned': banned, 'note': note});

  Future<void> deleteAccountFor(String accountId, String note) =>
      api.write('POST', '/admin/accounts/$accountId/delete',
          body: {'note': note});

  /// [target] is demand, profile, post, comment or message.
  Future<void> takeDown(String target, String id, String note) =>
      api.write('POST', '/admin/content/$target/$id/takedown',
          body: {'note': note});

  Future<void> setFeatured(String postId, bool featured) =>
      api.write('POST', '/admin/posts/$postId/featured',
          body: {'featured': featured});

  Future<Paged<FeedbackItem>> feedbackInbox(
          {bool open = false, int page = 1, int pageSize = 20}) =>
      _paged('/admin/feedback', feedbackFrom,
          page: page, pageSize: pageSize, query: {if (open) 'open': 'true'});

  Future<void> markFeedbackHandled(String id) =>
      api.write('POST', '/admin/feedback/$id/handled');

  /// Pushes [texts] (by zh / kk / ru) to every device, or only those in
  /// [lang]; returns how many devices it went to.
  Future<int> broadcast(String title, Map<String, String> texts,
      {String? lang}) async {
    final r = await api.write('POST', '/admin/broadcast',
        body: {'title': title, 'texts': texts, if (lang != null) 'lang': lang});
    return ((r as Map?)?['sent'] as num?)?.toInt() ?? 0;
  }

  /// The built-in banned words and the ones the back office added.
  Future<({List<String> builtin, List<String> words})> bannedWords(
      [List<String>? save]) async {
    final r = (save == null
        ? await api.request('GET', '/admin/banned-words')
        : await api.write('PUT', '/admin/banned-words',
            body: {'words': save})) as Map<String, dynamic>;
    List<String> list(Object? v) =>
        [for (final w in (v as List? ?? const [])) '$w'];
    return (builtin: list(r['builtin']), words: list(r['words']));
  }

  Future<List<TrendDay>> trends() async => [
        for (final d in ((await api.request('GET', '/admin/trends')) as List? ??
            const []))
          trendFrom(d as Map<String, dynamic>)
      ];

  /// A CSV of every account (`users`) or demand (`demands`).
  Future<List<int>> export(String what) async {
    final res = await api.sendRaw('GET', '/admin/export/$what');
    if (res.statusCode != 200) ApiClient.decode(res);
    return res.bodyBytes;
  }

  @override
  Future<PushPolicy> pushPolicy() async => policyFrom(
      await api.request('GET', '/admin/push-policy') as Map<String, dynamic>);

  @override
  Future<PushPolicy> savePushPolicy(PushPolicy p) async =>
      policyFrom(await api.write('PUT', '/admin/push-policy', body: {
        'quiet_start': p.quietStart,
        'quiet_end': p.quietEnd,
        'daily_cap': p.dailyCap
      }) as Map<String, dynamic>);
}
