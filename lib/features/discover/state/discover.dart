import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/shared/model/models.dart';

/// The "find people" search, keyed by the filter's fields:
/// (kind, trade, region, available now, query).
typedef PeopleQuery = (ProfileKind?, String?, String?, bool, String);

final peopleSearchProvider = FutureProvider.autoDispose
    .family<List<ServiceProfile>, PeopleQuery>((ref, q) {
  final (kind, trade, region, availableNow, query) = q;
  return ref.watch(profileRepositoryProvider).searchProfiles(ProfileFilter(
      kind: kind,
      trade: trade,
      region: region,
      availableNow: availableNow,
      query: query));
});

/// The "find work" search, keyed by (type, trade, region, query), with the
/// caller's favourites.
typedef WorkQuery = (DemandType?, String?, String?, String);

final workSearchProvider = FutureProvider.autoDispose
    .family<(List<Demand>, Set<String>), WorkQuery>((ref, q) async {
  final (type, trade, region, query) = q;
  return (
    await ref.watch(demandRepositoryProvider).searchDemands(
        DemandFilter(type: type, trade: trade, region: region, query: query)),
    await ref.watch(profileRepositoryProvider).favourites(),
  );
});
