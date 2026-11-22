import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/shared/model/models.dart';

/// Houses I published.
final myPostsProvider = FutureProvider.autoDispose<List<HousePost>>(
    (ref) => ref.watch(postRepositoryProvider).myPosts());

/// My quotes, each with its demand (null once it is out of sight).
final myApplicationsProvider =
    FutureProvider.autoDispose<List<(Application, Demand?)>>((ref) async {
  final demands = ref.watch(demandRepositoryProvider);
  return [
    for (final a
        in await ref.watch(applicationRepositoryProvider).myApplications())
      (a, await demands.demand(a.demandId))
  ];
});

/// Everything I saved: hearted houses, then favourite profiles and demands.
/// Favourites hold profile and demand ids together, so each id is looked
/// up as either.
final favouritesProvider = FutureProvider.autoDispose<
    (List<HousePost>, List<ServiceProfile>, List<Demand>)>((ref) async {
  final posts = ref.watch(postRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final demandRepo = ref.watch(demandRepositoryProvider);
  final houses = [
    for (final id in await posts.likedPosts())
      if (await posts.post(id) case final p?) p
  ];
  final profiles = <ServiceProfile>[];
  final demands = <Demand>[];
  for (final id in await profileRepo.favourites()) {
    if (await demandRepo.demand(id) case final d?) {
      demands.add(d);
    } else if (await profileRepo.profile(id) case final p?) {
      profiles.add(p);
    }
  }
  return (houses, profiles, demands);
});

/// The accounts I blocked (null where one is gone).
final blockedAccountsProvider =
    FutureProvider.autoDispose<List<Account?>>((ref) async {
  final auth = ref.watch(authRepositoryProvider);
  return Future.wait([
    for (final id in await ref.watch(chatRepositoryProvider).blocked())
      auth.account(id)
  ]);
});
