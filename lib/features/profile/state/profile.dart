import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/shared/model/models.dart';

/// What a profile's public page shows.
class ProfileData {
  ProfileData(this.profile, this.stats, this.owner, this.reviews,
      {this.favourite = false});
  final ServiceProfile? profile;
  final bool favourite;
  final ProfileStats? stats;
  final Account? owner;
  final List<Review> reviews;
}

/// A profile's public page, by profile id.
final profilePageProvider = FutureProvider.autoDispose
    .family<ProfileData, String>((ref, profileId) async {
  final profiles = ref.watch(profileRepositoryProvider);
  final p = await profiles.profile(profileId);
  if (p == null) return ProfileData(null, null, null, const []);
  final (stats, owner, reviews, favs) = await (
    profiles.stats(p.id),
    ref.watch(authRepositoryProvider).account(p.ownerId),
    ref.watch(reviewRepositoryProvider).reviewsAbout(p.ownerId),
    profiles.favourites()
  ).wait;
  return ProfileData(p, stats, owner, reviews, favourite: favs.contains(p.id));
});

/// Public reviews about an account.
final reviewsAboutProvider = FutureProvider.autoDispose
    .family<List<Review>, String>((ref, accountId) =>
        ref.watch(reviewRepositoryProvider).reviewsAbout(accountId));

/// The signed-in account's own profiles.
final myProfilesProvider = FutureProvider.autoDispose<List<ServiceProfile>>(
    (ref) => ref.watch(profileRepositoryProvider).myProfiles());
