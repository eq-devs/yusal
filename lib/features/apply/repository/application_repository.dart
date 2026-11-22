import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/codec.dart';
import 'package:yusal/shared/model/models.dart';

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


/// Overridden in `lib/app` with the one backend (the fake in tests).
final applicationRepositoryProvider = Provider<ApplicationRepository>(
    (ref) => throw UnimplementedError('applicationRepositoryProvider is not overridden'));

/// [ApplicationRepository] over yusal-api.
mixin HttpApplicationRepository on ApiClient implements ApplicationRepository {
  @override
  Future<Map<String, ({int total, int unread})>> myQuoteCounts() async {
    final m =
        await request('GET', '/client/me/quote-counts') as Map<String, dynamic>;
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
      for (final j in await getList('/client/demands/$demandId/applications'))
        applicationFrom(j)
    ];
    await loadNames(list.map((a) => a.applicantId));
    return list;
  }

  @override
  Future<List<Application>> myApplications() async => [
        for (final j in await getList('/client/me/applications'))
          applicationFrom(j)
      ];

  @override
  Future<Application?> application(String id) async {
    if (currentId == null) return null;
    final j = await maybe('/client/applications/$id');
    return j == null ? null : applicationFrom(j);
  }

  @override
  Future<Application> submit(
          {required String demandId,
          required String profileId,
          required ApplicationVersion version,
          required String requestId}) =>
      _application(write('POST', '/client/applications', body: {
        'demand_id': demandId,
        'profile_id': profileId,
        'version': appVersionJson(version),
        'request_id': requestId,
      }));

  @override
  Future<Application> withdraw(String applicationId) => _application(
      write('POST', '/client/applications/$applicationId/withdraw'));

  @override
  Future<Application> markNotSelected(String applicationId) => _application(
      write('POST', '/client/applications/$applicationId/not-selected'));

  Future<Application> _application(Future<dynamic> f) async =>
      applicationFrom(await f as Map<String, dynamic>);
}
