import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/auth/repository/auth_repository.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/shared/state/session.dart';

/// Everything the house page shows: the post (null when it is gone), whether
/// the caller liked it, the demands recruiting for it, critiques, the
/// design, whether the caller is a pro, and the build progress.
typedef PostPageData = (
  HousePost?,
  bool,
  List<Demand>,
  List<PostComment>,
  DesignSnapshot?,
  bool,
  PostBuild?
);

final postPageProvider = FutureProvider.autoDispose
    .family<PostPageData, String>((ref, postId) async {
  final posts = ref.watch(postRepositoryProvider);
  final p = await posts.post(postId);
  if (p == null) {
    return (
      null,
      false,
      const <Demand>[],
      const <PostComment>[],
      null,
      false,
      null
    );
  }
  // Independent of each other: asked together, not one by one.
  final (liked, demands, comments, snap, isPro, build) = await (
    posts.liked(postId),
    posts.demandsForPost(postId),
    posts.comments(postId),
    ref.watch(snapshotRepositoryProvider).snapshot(p.snapshotId, postId: p.id),
    ref.watch(sessionProvider).currentAccount == null
        ? Future.value(false)
        : ref
            .watch(profileRepositoryProvider)
            .myProfiles()
            .then((list) => list.isNotEmpty),
    posts.postBuild(postId)
  ).wait;
  return (p, liked, demands, comments, snap, isPro, build);
});

/// An account by id, for bylines and cards that name a person.
final accountProvider = FutureProvider.autoDispose.family<Account?, String>(
    (ref, id) => ref.watch(authRepositoryProvider).account(id));

/// A critique's author and their profiles, by account id.
final authorProvider = FutureProvider.autoDispose
    .family<(Account?, List<ServiceProfile>), String>((ref, id) => (
          ref.watch(authRepositoryProvider).account(id),
          ref.watch(profileRepositoryProvider).profilesOf(id)
        ).wait);
