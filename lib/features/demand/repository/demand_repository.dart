import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/codec.dart';
import 'package:yusal/shared/model/models.dart';

/// Demands: what owners publish to find builders.

abstract interface class DemandRepository {
  Future<List<Demand>> searchDemands(DemandFilter filter);
  Future<Demand?> demand(String id);
  Future<List<Demand>> myDemands();

  /// Saves a draft (only visible to the owner).
  Future<Demand> saveDraft(DemandType type, DemandVersion draft,
      {PublisherRole role = PublisherRole.owner,
      String? existingId,
      String? designProjectId});

  /// Sends a draft for review.
  Future<Demand> publish(String demandId);

  /// Publishes a new version; live applications are marked for re-confirm.
  Future<Demand> revise(String demandId, DemandVersion next);
  Future<Demand> pause(String demandId);
  Future<Demand> resume(String demandId);
  Future<Demand> renew(String demandId);
  Future<Demand> markFound(String demandId, OutcomeKind outcome);
  Future<Demand> close(String demandId, String reason);
  Future<Demand> recordOutcome(String demandId, OutcomeKind outcome);
  Future<Demand> setShareRevoked(String demandId, bool revoked);

  /// What an outside web visitor may see through a share link; null when the
  /// link is unknown. The result only carries public fields.
  Future<PublicDemandView?> publicView(String shareToken);
}

/// Overridden in `lib/app` with the one backend (the fake in tests).
final demandRepositoryProvider = Provider<DemandRepository>((ref) =>
    throw UnimplementedError('demandRepositoryProvider is not overridden'));

/// [DemandRepository] over yusal-api.
mixin HttpDemandRepository on ApiClient implements DemandRepository {
  @override
  Future<List<Demand>> searchDemands(DemandFilter f) async {
    final list = [
      for (final j in await getList('/client/demands', query: {
        if (f.type != null) 'type': f.type!.name,
        if (f.trade != null) 'trade': f.trade!,
        if (f.region != null) 'region': f.region!,
        if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
        if (f.includeInactive) 'include_inactive': 'true',
      }))
        demandFrom(j)
    ];
    await loadNames(list.map((d) => d.ownerId));
    return list;
  }

  @override
  Future<Demand?> demand(String id) async {
    final j = await maybe('/client/demands/$id');
    if (j == null) return null;
    final d = demandFrom(j);
    await loadNames([d.ownerId]);
    return d;
  }

  @override
  Future<List<Demand>> myDemands() async =>
      [for (final j in await getList('/client/me/demands')) demandFrom(j)];

  @override
  Future<Demand> saveDraft(DemandType type, DemandVersion draft,
          {PublisherRole role = PublisherRole.owner,
          String? existingId,
          String? designProjectId}) =>
      _demand(write('POST', '/client/demands', body: {
        'type': type.name,
        'version': versionJson(draft),
        'publisher_role': role.name,
        if (existingId != null) 'existing_id': existingId,
        if (designProjectId != null) 'design_project_id': designProjectId,
      }));

  @override
  Future<Demand> publish(String demandId) =>
      _demand(write('POST', '/client/demands/$demandId/publish'));

  @override
  Future<Demand> revise(String demandId, DemandVersion next) =>
      _demand(write('POST', '/client/demands/$demandId/revise',
          body: {'version': versionJson(next)}));

  @override
  Future<Demand> pause(String demandId) =>
      _demand(write('POST', '/client/demands/$demandId/pause'));

  @override
  Future<Demand> resume(String demandId) =>
      _demand(write('POST', '/client/demands/$demandId/resume'));

  @override
  Future<Demand> renew(String demandId) =>
      _demand(write('POST', '/client/demands/$demandId/renew'));

  @override
  Future<Demand> markFound(String demandId, OutcomeKind outcome) =>
      _demand(write('POST', '/client/demands/$demandId/found',
          body: {'outcome': outcome.name}));

  @override
  Future<Demand> close(String demandId, String reason) =>
      _demand(write('POST', '/client/demands/$demandId/close',
          body: {'reason': reason}));

  @override
  Future<Demand> recordOutcome(String demandId, OutcomeKind outcome) =>
      _demand(write('POST', '/client/demands/$demandId/outcome',
          body: {'outcome': outcome.name}));

  @override
  Future<Demand> setShareRevoked(String demandId, bool revoked) =>
      _demand(write('POST', '/client/demands/$demandId/share',
          body: {'revoked': revoked}));

  @override
  Future<PublicDemandView?> publicView(String shareToken) async {
    final token = Uri.encodeComponent(shareToken);
    final j = await maybe('/client/share/$token');
    if (j == null) return null;
    DesignSnapshot? snap;
    if (j['available'] == true && j['snapshot_id'] != null) {
      final s = await maybe('/client/share/$token/snapshot');
      if (s != null) snap = snapshotFrom(s);
    }
    return publicViewFrom(j, snap);
  }

  Future<Demand> _demand(Future<dynamic> f) async =>
      demandFrom(await f as Map<String, dynamic>);
}
