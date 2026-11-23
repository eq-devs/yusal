import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/coop/model/coop_json.dart';
import 'package:yusal/utils/json.dart';
import 'package:yusal/features/shared/model/models.dart';

/// Cooperations (an agreed job) and the reviews that close them.

abstract interface class CooperationRepository {
  /// The publisher proposes an agreement on an application and confirms
  /// their own side.
  Future<Cooperation> invite(String applicationId, Agreement terms);
  Future<Cooperation> confirm(String cooperationId);
  Future<Cooperation> decline(String cooperationId);

  /// The publisher takes back an unanswered invitation.
  Future<Cooperation> revoke(String cooperationId);
  Future<Cooperation> proposeChange(String cooperationId, Agreement terms);
  Future<Cooperation> answerChange(String cooperationId, bool accept);
  Future<Cooperation> requestEnd(String cooperationId, String note);
  Future<Cooperation> confirmEnd(String cooperationId);
  Future<Cooperation> disputeEnd(String cooperationId, String note);
  Future<Cooperation> addUpdate(String cooperationId, String text);

  /// The pro asks the owner to inspect a milestone (with photos).
  Future<Cooperation> requestMilestone(String cooperationId, int index,
      {String note = '', List<List<int>> photos = const []});

  /// Replans the inspection points while the agreement is still waiting
  /// for confirmation. Shares must add up to 100. Both sides confirm again.
  Future<Cooperation> setMilestones(String cooperationId, List<Milestone> plan);

  /// The owner accepts a requested milestone or raises a problem (note
  /// required). Only records the inspection; no money moves.
  Future<Cooperation> answerMilestone(
      String cooperationId, int index, bool accept,
      {String note = ''});

  /// The pro logs today's crew on site; one entry per day, latest wins.
  Future<Cooperation> logWork(String cooperationId, int headcount,
      {String note = '', List<List<int>> photos = const []});

  /// The owner confirms a logged day.
  Future<Cooperation> confirmWork(String cooperationId, String logId);
  Future<Cooperation?> cooperation(String id);
  Future<List<Cooperation>> myCooperations();
  Future<List<Cooperation>> cooperationsFor(String demandId);
}

abstract interface class ReviewRepository {
  Future<Review> submitReview(
      String cooperationId, Map<String, int> scores, String text);

  /// Reviews of one cooperation the caller may see: their own, plus the
  /// other side's once visible.
  Future<List<Review>> reviewsFor(String cooperationId);

  /// Public reviews about an account.
  Future<List<Review>> reviewsAbout(String accountId);
}

String _c(String id) => '/client/cooperations/$id';

final cooperationRepositoryProvider = Provider<CooperationRepository>(
    (ref) => HttpCooperationRepository(ApiClient.app));
final reviewRepositoryProvider =
    Provider<ReviewRepository>((ref) => HttpReviewRepository(ApiClient.app));

/// [CooperationRepository] over yusal-api.
final class HttpCooperationRepository implements CooperationRepository {
  HttpCooperationRepository(this.api);
  final ApiClient api;

  /// Photo bytes by `/media/` path; photos never change, so fetched once.
  final _media = <String, List<int>>{};

  Future<Cooperation> _withMedia(Map<String, dynamic> j) async {
    await Future.wait([
      for (final path in cooperationMedia(j).toSet())
        if (!_media.containsKey(path)) _loadMedia(path)
    ]);
    return cooperationFrom(j, media: _media);
  }

  Future<void> _loadMedia(String path) async {
    try {
      final res = await api.sendRaw('GET', path, auth: false);
      if (res.statusCode == 200) _media[path] = res.bodyBytes;
    } on ApiFailure {
      // Shown without that photo; retried on the next load.
    }
  }

  @override
  Future<Cooperation> invite(String applicationId, Agreement terms) =>
      _cooperation(api.write(
          'POST', '/client/applications/$applicationId/invite',
          body: agreementJson(terms)));

  @override
  Future<Cooperation> confirm(String id) =>
      _cooperation(api.write('POST', '${_c(id)}/confirm'));

  @override
  Future<Cooperation> decline(String id) =>
      _cooperation(api.write('POST', '${_c(id)}/decline'));

  @override
  Future<Cooperation> revoke(String id) =>
      _cooperation(api.write('POST', '${_c(id)}/revoke'));

  @override
  Future<Cooperation> proposeChange(String id, Agreement terms) => _cooperation(
      api.write('POST', '${_c(id)}/change', body: agreementJson(terms)));

  @override
  Future<Cooperation> answerChange(String id, bool accept) => _cooperation(
      api.write('POST', '${_c(id)}/change/answer', body: {'accept': accept}));

  @override
  Future<Cooperation> requestEnd(String id, String note) => _cooperation(
      api.write('POST', '${_c(id)}/end-request', body: {'note': note}));

  @override
  Future<Cooperation> confirmEnd(String id) =>
      _cooperation(api.write('POST', '${_c(id)}/end-confirm'));

  @override
  Future<Cooperation> disputeEnd(String id, String note) => _cooperation(
      api.write('POST', '${_c(id)}/end-dispute', body: {'note': note}));

  @override
  Future<Cooperation> addUpdate(String id, String text) => _cooperation(
      api.write('POST', '${_c(id)}/updates', body: {'text': text}));

  @override
  Future<Cooperation> requestMilestone(String id, int index,
          {String note = '', List<List<int>> photos = const []}) =>
      _cooperation(api.write('POST', '${_c(id)}/milestones/$index/request',
          body: {'note': note, 'photos': photosJson(photos)}));

  @override
  Future<Cooperation> setMilestones(String id, List<Milestone> plan) =>
      _cooperation(api.write('PUT', '${_c(id)}/milestones', body: {
        'milestones': [for (final m in plan) milestoneJson(m)]
      }));

  @override
  Future<Cooperation> answerMilestone(String id, int index, bool accept,
          {String note = ''}) =>
      _cooperation(api.write('POST', '${_c(id)}/milestones/$index/answer',
          body: {'accept': accept, 'note': note}));

  @override
  Future<Cooperation> logWork(String id, int headcount,
          {String note = '', List<List<int>> photos = const []}) =>
      _cooperation(api.write('POST', '${_c(id)}/work-logs', body: {
        'headcount': headcount,
        'note': note,
        'photos': photosJson(photos),
      }));

  @override
  Future<Cooperation> confirmWork(String id, String logId) =>
      _cooperation(api.write('POST', '${_c(id)}/work-logs/$logId/confirm'));

  @override
  Future<Cooperation?> cooperation(String id) async {
    if (api.currentId == null) return null;
    final j = await api.maybe(_c(id));
    if (j == null) return null;
    final c = await _withMedia(j);
    return c;
  }

  @override
  Future<List<Cooperation>> myCooperations() async {
    final list = await Future.wait([
      for (final j in await api.getList('/client/me/cooperations'))
        _withMedia(j)
    ]);
    return list;
  }

  @override
  Future<List<Cooperation>> cooperationsFor(String demandId) async =>
      Future.wait([
        for (final j
            in await api.getList('/client/demands/$demandId/cooperations'))
          _withMedia(j)
      ]);

  Future<Cooperation> _cooperation(Future<dynamic> f) async =>
      _withMedia(await f as Map<String, dynamic>);
}

/// [ReviewRepository] over yusal-api.
final class HttpReviewRepository implements ReviewRepository {
  HttpReviewRepository(this.api);
  final ApiClient api;

  @override
  Future<Review> submitReview(
          String cooperationId, Map<String, int> scores, String text) async =>
      reviewFrom(await api.write('POST', '${_c(cooperationId)}/reviews',
          body: {'scores': scores, 'text': text}) as Map<String, dynamic>);

  @override
  Future<List<Review>> reviewsFor(String cooperationId) async => [
        for (final j in await api.getList('${_c(cooperationId)}/reviews'))
          reviewFrom(j)
      ];

  @override
  Future<List<Review>> reviewsAbout(String accountId) async {
    final list = [
      for (final j in await api.getList('/client/accounts/$accountId/reviews'))
        reviewFrom(j)
    ];
    return list;
  }
}
