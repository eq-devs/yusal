import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/core/serialization/house_codec.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_clock.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/snapshot/design_snapshot.dart';

MockBackend mock() => MockBackend(
    clock: MockClock(DateTime.utc(2026, 11, 3, 9)),
    latency: Duration.zero,
    autoReviewDelay: Duration.zero);

Matcher fails(String code) =>
    throwsA(isA<ApiFailure>().having((e) => e.code, 'code', code));

void main() {
  test('seeded designs decode and carry their stats', () async {
    final b = mock();
    final list = await b.showcases(const ShowcaseFilter());
    expect(list, hasLength(6));
    for (final s in list) {
      expect(loadHouse(utf8.encode(s.houseText)).isSuccess, isTrue);
    }
    final kz = await b.showcase('show_kz');
    expect(kz!.likes, 4);
    expect(kz.ratingCount, 3);
    expect(kz.rating, closeTo(14 / 3, 1e-9));
    expect(kz.openDemandIds, containsAll(['dem_wall', 'dem_hire']));
    expect(kz.hiring, isTrue);
  });

  test('filters by style, floors and hiring; sorts by rating', () async {
    final b = mock();
    final wood = await b.showcases(const ShowcaseFilter(style: 'wood'));
    expect(wood.map((s) => s.id), ['show_wood']);
    final two = await b.showcases(const ShowcaseFilter(floors: 2));
    expect(two.every((s) => s.floors >= 2), isTrue);
    expect(two, isNotEmpty);
    final hiring = await b.showcases(const ShowcaseFilter(hiringOnly: true));
    expect(hiring.map((s) => s.id), ['show_kz']);
    final top =
        await b.showcases(const ShowcaseFilter(sort: ShowcaseSort.topRated));
    expect(top.first.rating, 5);
  });

  test('likes need an account and toggle', () async {
    final b = mock();
    expect(() => b.toggleLike('show_two'), fails(ApiCodes.notSignedIn));
    b.signInAs(SeedIds.mason);
    await b.toggleLike('show_two');
    expect((await b.showcase('show_two'))!.likes, 3);
    expect(await b.likedShowcases(), contains('show_two'));
    await b.toggleLike('show_two');
    expect((await b.showcase('show_two'))!.likes, 2);
  });

  test('one rating per person; owners comment but cannot rate', () async {
    final b = mock()..signInAs(SeedIds.mason);
    await b.addComment('show_two', '', rating: 3);
    await b.addComment('show_two', '改主意了', rating: 5);
    final s = await b.showcase('show_two');
    expect(s!.ratingCount, 2); // the seeded 4 and mine
    expect(s.ratingSum, 9);
    expect(() => b.addComment('show_two', 'x', rating: 6),
        fails(ApiCodes.invalidInput));
    b.signInAs(SeedIds.owner2);
    expect(() => b.addComment('show_two', '', rating: 5),
        fails(ApiCodes.ownDemand));
    await b.addComment('show_two', '谢谢大家');
    expect((await b.comments('show_two')).first.text, '谢谢大家');
  });

  test('publishing the same project again updates it; only the owner removes',
      () async {
    final b = mock()..signInAs(SeedIds.owner2);
    var n = 0;
    final doc = createTemplate('three', '2026-01-01T00:00:00Z', () => 't${n++}');
    final f = showcaseFacts(doc);
    Future<Showcase> publish(String title) => b.publishShowcase(
        projectId: 'p1',
        title: title,
        story: '',
        region: 'almaty',
        styles: const ['compact'],
        houseText: encodeHouse(doc),
        width: f.width,
        depth: f.depth,
        floors: f.floors,
        rooms: f.rooms,
        area: f.area);
    final first = await publish('第一版');
    final second = await publish('第二版');
    expect(second.id, first.id);
    expect((await b.showcasesOf(SeedIds.owner2)).first.title, '第二版');
    expect(f.rooms, 3);
    b.signInAs(SeedIds.mason);
    expect(() => b.removeShowcase(first.id), fails(ApiCodes.forbidden));
    b.signInAs(SeedIds.owner2);
    await b.removeShowcase(first.id);
    expect(await b.showcase(first.id), isNull);
  });

  test('a blocked owner\'s designs disappear for the blocker', () async {
    final b = mock()..signInAs(SeedIds.mason);
    await b.block(SeedIds.owner2);
    final ids = (await b.showcases(const ShowcaseFilter())).map((s) => s.id);
    expect(ids, isNot(contains('show_two')));
  });
}
