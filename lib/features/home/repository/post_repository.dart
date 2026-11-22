import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/demand/model/demand_json.dart';
import 'package:yusal/features/home/model/home_json.dart';
import 'package:yusal/features/shared/model/models.dart';

/// Published houses: the feed, likes, critiques and reuse.

abstract interface class PostRepository {
  Future<List<HousePost>> feed(FeedFilter filter);
  Future<HousePost?> post(String id);
  Future<List<HousePost>> myPosts();
  Future<List<HousePost>> postsBy(String accountId);

  /// Publishes a design. The snapshot must belong to the caller.
  Future<HousePost> publishPost(HousePost draft);
  Future<HousePost> updatePost(HousePost post);
  Future<void> hidePost(String id);

  /// Counts someone starting their own house from this design and tells
  /// the author. Works signed out; returns the frozen plan to copy.
  Future<String?> reusePost(String postId);

  /// Toggles the like; returns the new state.
  Future<bool> toggleLike(String postId);
  Future<bool> liked(String postId);

  /// The plan thumbnail of a post whose list left [HousePost.preview] out
  /// (feeds do, so cards can show before their pictures arrive). The bytes
  /// themselves, not a future, when they are already at hand.
  FutureOr<List<int>?> postPreview(String postId);
  Future<List<String>> likedPosts();

  Future<List<PostComment>> comments(String postId);

  /// A critique (optionally rated and about one [feedbackTopics] entry) or,
  /// with [parentId], a reply to one. Replies carry no rating or topic.
  Future<PostComment> comment(String postId, String text,
      {int? rating, String? topic, String? parentId});
  Future<void> deleteComment(String id);

  /// The house's author marks a critique as useful (or takes it back).
  Future<PostComment> markHelpful(String commentId, bool helpful);

  /// Open demands recruiting for this house.
  Future<List<Demand>> demandsForPost(String postId);

  /// Who builds this house and how far it got. Null unless the owner
  /// chose to show it (the owner always sees it).
  Future<PostBuild?> postBuild(String postId);

  /// The public house a demand belongs to, if its owner published one.
  Future<HousePost?> postForDemand(String demandId);
}

final postRepositoryProvider =
    Provider<PostRepository>((ref) => HttpPostRepository(ApiClient.app));

/// [PostRepository] over yusal-api.
final class HttpPostRepository implements PostRepository {
  HttpPostRepository(this.api) {
    // Likes seen belong to the account that saw them.
    api.onForget.add(_likedSeen.clear);
  }
  final ApiClient api;

  /// Posts' plan thumbnails, fetched once per post.
  final _previews = <String, List<int>?>{};
  final _previewLoads = <String, Future<void>>{};

  /// "Liked" as the last [post] call reported it, for the [liked] call
  /// that follows it on the house page.
  final _likedSeen = <String, bool>{};

  HousePost _post(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return HousePost(
        id: id,
        ownerId: j['owner_id'] as String,
        projectId: j['project_id'] as String? ?? '',
        snapshotId: j['snapshot_id'] as String,
        title: j['title'] as String,
        story: j['story'] as String? ?? '',
        region: j['region'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        area: (j['area'] as num? ?? 0).toDouble(),
        floors: j['floors'] as int? ?? 1,
        rooms: j['rooms'] as int? ?? 0,
        estimatedCost: j['estimated_cost'] as int?,
        tags: [for (final t in j['tags'] as List? ?? const []) t as String],
        openForBuilders: j['open_for_builders'] as bool? ?? false,
        status:
            j['status'] == 'hidden' ? PostStatus.hidden : PostStatus.published,
        likeCount: j['like_count'] as int? ?? 0,
        commentCount: j['comment_count'] as int? ?? 0,
        ratingSum: j['rating_sum'] as int? ?? 0,
        ratingCount: j['rating_count'] as int? ?? 0,
        reuseCount: j['reuse_count'] as int? ?? 0,
        featured: j['featured'] == true,
        showBuild: j['show_build'] as bool? ?? false,
        focus: [for (final f in j['focus'] as List? ?? const []) f as String],
        preview: _previews[id]);
  }

  /// Maps posts and fills in their thumbnails (fetched once each). With
  /// [previews] off only thumbnails already here are filled in; the rest
  /// come through [postPreview] as their cards scroll into view.
  Future<List<HousePost>> _posts(List raw, {bool previews = true}) async {
    final list = [for (final j in raw) j as Map<String, dynamic>];
    if (previews) {
      await Future.wait([
        for (final j in list)
          if (!_previews.containsKey(j['id'])) _loadPreview(j['id'] as String)
      ]);
    }
    return [for (final j in list) _post(j)];
  }

  @override
  FutureOr<List<int>?> postPreview(String postId) {
    if (_previews.containsKey(postId)) return _previews[postId];
    return _loadPreview(postId).then((_) => _previews[postId]);
  }

  Future<void> _loadPreview(String postId) =>
      _previewLoads[postId] ??= _fetchPreview(postId).whenComplete(() {
        _previewLoads.remove(postId);
      });

  Future<void> _fetchPreview(String postId) async {
    try {
      final res = await api.sendRaw('GET', '/client/posts/$postId/preview');
      _previews[postId] = res.statusCode == 200 ? res.bodyBytes : null;
    } on ApiFailure {
      // Leave it uncached; the card shows without a picture.
    }
  }

  @override
  Future<List<HousePost>> feed(FeedFilter f) async {
    final data = await api.request('GET', '/client/posts', query: {
      if (f.region != null) 'region': f.region!,
      'sort': f.sort.name,
      if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
      if (f.openForBuilders) 'open_for_builders': 'true',
      if (f.askingFeedback) 'asking_feedback': 'true',
      'page_size': '100',
    }) as Map<String, dynamic>;
    return _posts(data['items'] as List, previews: false);
  }

  @override
  Future<HousePost?> post(String id) async {
    try {
      final j =
          await api.request('GET', '/client/posts/$id') as Map<String, dynamic>;
      if (api.currentId != null) _likedSeen[id] = j['liked'] == true;
      return (await _posts([j])).single;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<List<HousePost>> myPosts() async {
    if (api.currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return _posts(await api.request('GET', '/client/me/posts') as List);
  }

  @override
  Future<List<HousePost>> postsBy(String accountId) async => _posts(
      await api.request('GET', '/client/accounts/$accountId/posts') as List);

  @override
  Future<HousePost> publishPost(HousePost d) async {
    final j = await api.request('POST', '/client/posts', body: {
      'snapshot_id': d.snapshotId,
      'project_id': d.projectId,
      'title': d.title,
      'story': d.story,
      'region': d.region,
      'area': d.area,
      'floors': d.floors,
      'rooms': d.rooms,
      if (d.estimatedCost != null) 'estimated_cost': d.estimatedCost,
      'tags': d.tags,
      'open_for_builders': d.openForBuilders,
      'focus': d.focus,
    }) as Map<String, dynamic>;
    api.notify();
    return (await _posts([j])).single;
  }

  @override
  Future<HousePost> updatePost(HousePost p) async {
    final j = await api.request('PATCH', '/client/posts/${p.id}', body: {
      'title': p.title,
      'story': p.story,
      'region': p.region,
      'tags': p.tags,
      'open_for_builders': p.openForBuilders,
      'show_build': p.showBuild,
      'focus': p.focus,
    }) as Map<String, dynamic>;
    api.notify();
    return (await _posts([j])).single;
  }

  @override
  Future<void> hidePost(String id) async {
    await api.request('POST', '/client/posts/$id/hide');
    api.notify();
  }

  @override
  Future<String?> reusePost(String postId) async {
    final data = await api.request('POST', '/client/posts/$postId/reuse')
        as Map<String, dynamic>;
    api.notify();
    return data['plan_json'] as String?;
  }

  @override
  Future<bool> toggleLike(String postId) async {
    final data = await api.request('POST', '/client/posts/$postId/like')
        as Map<String, dynamic>;
    _likedSeen.remove(postId);
    api.notify();
    return data['liked'] as bool;
  }

  @override
  Future<bool> liked(String postId) async {
    if (api.currentId == null) return false;
    if (_likedSeen.remove(postId) case final seen?) return seen;
    final j = await api.request('GET', '/client/posts/$postId')
        as Map<String, dynamic>;
    return j['liked'] == true;
  }

  @override
  Future<List<String>> likedPosts() async {
    if (api.currentId == null) return const [];
    return [
      for (final id
          in await api.request('GET', '/client/me/liked-posts') as List)
        id as String
    ];
  }

  static PostComment _comment(Map<String, dynamic> j) => PostComment(
      id: j['id'] as String,
      postId: j['post_id'] as String,
      authorId: j['author_id'] as String,
      text: j['text'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String),
      rating: j['rating'] as int?,
      topic: j['topic'] as String?,
      parentId: j['parent_id'] as String?,
      helpful: j['helpful'] as bool? ?? false);

  @override
  Future<List<PostComment>> comments(String postId) async {
    try {
      final list = [
        for (final c in await api.request(
            'GET', '/client/posts/$postId/comments') as List)
          _comment(c as Map<String, dynamic>)
      ];
      return list;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return const [];
      rethrow;
    }
  }

  @override
  Future<PostComment> comment(String postId, String text,
      {int? rating, String? topic, String? parentId}) async {
    final c = _comment(
        await api.request('POST', '/client/posts/$postId/comments', body: {
      'text': text,
      if (rating != null) 'rating': rating,
      if (topic != null) 'topic': topic,
      if (parentId != null) 'parent_id': parentId,
    }) as Map<String, dynamic>);
    api.notify();
    return c;
  }

  @override
  Future<void> deleteComment(String id) async {
    await api.request('DELETE', '/client/comments/$id');
    api.notify();
  }

  @override
  Future<PostComment> markHelpful(String commentId, bool helpful) async {
    final c = _comment(await api.request(
        'POST', '/client/comments/$commentId/helpful',
        body: {'helpful': helpful}) as Map<String, dynamic>);
    api.notify();
    return c;
  }

  @override
  Future<List<Demand>> demandsForPost(String postId) async => [
        for (final j in await api.getList('/client/posts/$postId/demands'))
          demandFrom(j)
      ];

  @override
  Future<PostBuild?> postBuild(String postId) async {
    final j = await api.request('GET', '/client/posts/$postId/build');
    if (j == null) return null;
    final b = postBuildFrom(j as Map<String, dynamic>);
    return b;
  }

  @override
  Future<HousePost?> postForDemand(String demandId) async {
    final j = await api.request('GET', '/client/demands/$demandId/post');
    if (j == null) return null;
    return (await _posts([j])).single;
  }
}
