import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/shared/model/models.dart';

/// What the cooperation page shows: the cooperation (null when it is gone
/// or not the caller's), its demand, both sides, the profile and reviews.
class CoopData {
  CoopData(this.coop, this.demand, this.owner, this.provider, this.profile,
      this.reviews);
  final Cooperation? coop;
  final Demand? demand;
  final Account? owner;
  final Account? provider;
  final ServiceProfile? profile;
  final List<Review> reviews;
}

/// One cooperation with everything around it, by id.
final coopDataProvider =
    FutureProvider.autoDispose.family<CoopData, String>((ref, id) async {
  final coops = ref.watch(cooperationRepositoryProvider);
  final auth = ref.watch(authRepositoryProvider);
  final c = await coops.cooperation(id);
  if (c == null) return CoopData(null, null, null, null, null, const []);
  final (demand, owner, provider, profile, reviews) = await (
    ref.watch(demandRepositoryProvider).demand(c.demandId),
    auth.account(c.ownerId),
    auth.account(c.providerId),
    ref.watch(profileRepositoryProvider).profile(c.profileId),
    ref.watch(reviewRepositoryProvider).reviewsFor(c.id)
  ).wait;
  return CoopData(c, demand, owner, provider, profile, reviews);
});
