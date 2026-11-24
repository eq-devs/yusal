import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/features/apply/model/apply_json.dart';
import 'package:yusal/features/shared/model/models.dart';

/// Builders' quotes on demands.

abstract interface class ApplicationRepository {
  /// The publisher's view of all applications of one demand.
  Future<List<Application>> applicationsFor(String demandId);

  /// Per demand of mine: active sign-ups/quotes and how many I haven't
  /// opened yet. Does not mark anything read.
  Future<Map<String, ({int total, int unread})>> myQuoteCounts();
  Future<List<Application>> myApplications();
  Future<Application?> application(String id);

  /// Idempotent per [requestId]; one live application per profile and
  /// demand, later submissions become new versions.
  Future<Application> submit(
      {required String demandId,
      required String profileId,
      required ApplicationVersion version,
      required String requestId});
  Future<Application> withdraw(String applicationId);
  Future<Application> markNotSelected(String applicationId);
}

final applicationRepositoryProvider = Provider<ApplicationRepository>(
    (ref) => HttpApplicationRepository(ApiClient.app));

/// [ApplicationRepository] over yusal-api.
final class HttpApplicationRepository implements ApplicationRepository {
  HttpApplicationRepository(this.api);
  final ApiClient api;

  @override
  Future<Map<String, ({int total, int unread})>> myQuoteCounts() async {
    final m = await api.request('GET', '/client/me/quote-counts')
        as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: (
          total: ((e.value as Map)['total'] as num).toInt(),
          unread: ((e.value as Map)['unread'] as num).toInt()
        )
    };
  }

  @override
  Future<List<Application>> applicationsFor(String demandId) async {
    final list = [
      for (final j
          in await api.getList('/client/demands/$demandId/applications'))
        applicationFrom(j)
    ];
    return list;
  }

  @override
  Future<List<Application>> myApplications() async => [
        for (final j in await api.getList('/client/me/applications'))
          applicationFrom(j)
      ];

  @override
  Future<Application?> application(String id) async {
    if (api.currentId == null) return null;
    final j = await api.maybe('/client/applications/$id');
    return j == null ? null : applicationFrom(j);
  }

  @override
  Future<Application> submit(
          {required String demandId,
          required String profileId,
          required ApplicationVersion version,
          required String requestId}) =>
      _application(api.write('POST', '/client/applications', body: {
        'demand_id': demandId,
        'profile_id': profileId,
        'version': appVersionJson(version),
        'request_id': requestId,
      }));

  @override
  Future<Application> withdraw(String applicationId) => _application(
      api.write('POST', '/client/applications/$applicationId/withdraw'));

  @override
  Future<Application> markNotSelected(String applicationId) => _application(
      api.write('POST', '/client/applications/$applicationId/not-selected'));

  Future<Application> _application(Future<dynamic> f) async =>
      applicationFrom(await f as Map<String, dynamic>);
}
