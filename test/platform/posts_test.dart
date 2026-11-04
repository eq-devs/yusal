import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/domain/models.dart';

MockBackend backend() => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero);

HousePost draft(String snapshotId,
        {String title = '我的房子', String story = ''}) =>
    HousePost(
        id: '',
        ownerId: '',
        projectId: 'p',
        snapshotId: snapshotId,
        title: title,
        story: story,
        region: 'almaty',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        area: 120,
        floors: 1,
        rooms: 4);

void main() {
  test('visitor can read a public standalone post snapshot', () async {
    final b = backend();
    expect(await b.snapshot('snap_erlan'), isNotNull);
    expect((await b.snapshot('snap_erlan'))!.planJson, isNotNull);
  });

  test('the feed shows seeded houses to a visitor, newest first', () async {
    final b = backend();
    final feed = await b.feed(const FeedFilter());
    expect(feed.map((p) => p.id),
        ['post_erlan', 'post_aigerim', 'post_dinara', 'post_team']);
    final popular = await b.feed(const FeedFilter(sort: FeedSort.popular));
    expect(popular.first.id, 'post_dinara');
    final open = await b.feed(const FeedFilter(openForBuilders: true));
    expect(open.any((p) => p.id == 'post_team'), isFalse);
    expect((await b.feed(const FeedFilter(region: 'esik'))).single.id,
        'post_team');
  });

  test('a house links to the demands recruiting for it', () async {
    final b = backend();
    final demands = await b.demandsForPost('post_aigerim');
    expect(demands.map((d) => d.id), ['dem_wall']);
    expect(await b.demandsForPost('post_dinara'), isEmpty);
  });

  test('publishing needs the owner\'s own snapshot and clean text', () async {
    final b = backend();
    b.signInAs(SeedIds.mason);
    expect(
        () => b.publishPost(draft('snap_aigerim')),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.forbidden)));
    b.signInAs(SeedIds.owner);
    expect(
        () => b.publishPost(draft('snap_aigerim', story: '需交押金')),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.invalidInput)));
    final p = await b.publishPost(draft('snap_aigerim', title: ' 新房子 '));
    expect(p.title, '新房子');
    expect(p.ownerId, SeedIds.owner);
    expect((await b.feed(const FeedFilter())).first.id, p.id);
    expect((await b.myPosts()).first.id, p.id);
    await b.hidePost(p.id);
    expect(
        (await b.feed(const FeedFilter())).any((x) => x.id == p.id), isFalse);
    b.signInAs(SeedIds.mason);
    expect(await b.post(p.id), isNull);
  });

  test('likes toggle and notify the owner', () async {
    final b = backend();
    b.signInAs(SeedIds.roofTeam);
    expect(await b.liked('post_aigerim'), isFalse);
    expect(await b.toggleLike('post_aigerim'), isTrue);
    expect((await b.post('post_aigerim'))!.likeCount, 4);
    expect(await b.likedPosts(), contains('post_aigerim'));
    expect(await b.toggleLike('post_aigerim'), isFalse);
    expect((await b.post('post_aigerim'))!.likeCount, 3);
    b.signInAs(SeedIds.owner);
    expect((await b.notifications()).any((n) => n.kind == NoticeKind.postLiked),
        isTrue);
  });

  test('one rating per person; owners cannot rate their own house', () async {
    final b = backend();
    b.signInAs(SeedIds.owner);
    expect(
        () => b.comment('post_aigerim', '好', rating: 5),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.invalidState)));
    b.signInAs(SeedIds.roofTeam);
    await b.comment('post_aigerim', '屋面可以再陡一点', rating: 3);
    var p = (await b.post('post_aigerim'))!;
    expect(p.ratingCount, 3);
    expect(p.rating, closeTo((5 + 4 + 3) / 3, 0.001));
    await b.comment('post_aigerim', '改主意了', rating: 5);
    p = (await b.post('post_aigerim'))!;
    expect(p.ratingCount, 3);
    expect(p.rating, closeTo((5 + 4 + 5) / 3, 0.001));
    expect(
        (await b.comments('post_aigerim'))
            .where((c) => c.authorId == SeedIds.roofTeam)
            .length,
        1);
    expect(
        () => b.comment('post_aigerim', '', rating: 9),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.invalidInput)));
    expect(
        () => b.comment('post_aigerim', '', rating: null),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.invalidInput)));
  });

  test('a comment can be removed by its author or the house owner', () async {
    final b = backend();
    b.signInAs(SeedIds.mason);
    expect(
        () => b.deleteComment('cmt2'),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.forbidden)));
    await b.deleteComment('cmt1');
    var p = (await b.post('post_aigerim'))!;
    expect(p.ratingCount, 1);
    expect(p.commentCount, 1);
    b.signInAs(SeedIds.owner);
    await b.deleteComment('cmt2');
    p = (await b.post('post_aigerim'))!;
    expect(p.rating, isNull);
    expect(p.commentCount, 0);
  });

  test('comments are rate limited', () async {
    final b = backend();
    b.signInAs(SeedIds.mason);
    for (var i = 0; i < 10; i++) await b.comment('post_dinara', '评论 $i');
    expect(
        () => b.comment('post_dinara', '再来'),
        throwsA(isA<ApiFailure>()
            .having((f) => f.code, 'code', ApiCodes.rateLimited)));
    b.advanceTime(const Duration(minutes: 2));
    await b.comment('post_dinara', '现在可以了');
  });

  test('a blocked person\'s house and comments disappear', () async {
    final b = backend();
    b.signInAs(SeedIds.owner2);
    await b.block(SeedIds.electrician);
    expect((await b.feed(const FeedFilter())).any((p) => p.id == 'post_erlan'),
        isFalse);
    expect(await b.post('post_erlan'), isNull);
  });
}
