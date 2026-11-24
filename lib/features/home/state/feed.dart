import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:yusal/features/shared/model/models.dart';

/// The feed's filter as a key: (region, sort, query, open for builders,
/// asking feedback, retry). The retry count makes "try again" a new load.
typedef FeedQuery = (String?, FeedSort, String, bool, bool, int);

/// The houses in the feed and which of them the caller liked.
final feedProvider = FutureProvider.autoDispose
    .family<(List<HousePost>, Set<String>), FeedQuery>((ref, q) async {
  final (region, sort, query, openForBuilders, askingFeedback, _) = q;
  final posts = ref.watch(postRepositoryProvider);
  return (
    await posts.feed(FeedFilter(
        region: region,
        sort: sort,
        query: query,
        openForBuilders: openForBuilders,
        askingFeedback: askingFeedback)),
    (await posts.likedPosts()).toSet()
  );
});
