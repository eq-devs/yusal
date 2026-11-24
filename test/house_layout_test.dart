import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/house_layout.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

void main() {
  var n = 0;
  List<HousePlan> plans(HouseBrief brief, {int count = 3}) => housePlans(brief,
      name: '初稿',
      timestamp: '2026-11-23T00:00:00Z',
      newId: () => 'p${n++}',
      count: count);

  test('the usual brief gives three different layouts, best first', () {
    final found = plans(const HouseBrief(width: 12000, depth: 10000));
    expect(found, hasLength(3));
    expect({for (final p in found) p.layout}, hasLength(3));
    expect(
        [for (final p in found) p.score],
        [
          ...[for (final p in found) p.score]
        ]..sort((a, b) => b.compareTo(a)));
    for (final p in found) {
      final rooms = p.document.floors.single.rooms;
      expect(rooms.where((r) => r.type == RoomType.bedroom), hasLength(3),
          reason: p.layout);
      for (final t in [RoomType.living, RoomType.kitchen, RoomType.bathroom]) {
        expect(rooms.map((r) => r.type), contains(t), reason: p.layout);
      }
      expect(p.document.mainEntranceOpeningId, isNotNull, reason: p.layout);
      expect(p.score, p.marks.values.reduce((a, b) => a + b));
    }
  });

  test('the same brief gives the same plans', () {
    const brief = HouseBrief(width: 11000, depth: 9000, bedrooms: 2);
    final once = plans(brief);
    final again = plans(brief);
    expect([for (final p in again) p.spec], [for (final p in once) p.spec]);
  });

  test('the entrance faces the side asked for', () {
    for (final side in ['north', 'east', 'south', 'west']) {
      for (final hall in [true, false]) {
        final best = plans(HouseBrief(
                width: 12000, depth: 10000, entrance: side, hall: hall))
            .first;
        expect(best.entrance, side, reason: '$side hall $hall');
        expect(best.marks['entrance'], 30);
      }
    }
  });

  test('a plan with no corridor loses no floor to one', () {
    final found = plans(const HouseBrief(width: 12000, depth: 10000));
    final hub = found.firstWhere((p) => p.layout == 'hub');
    expect(hub.marks['passage'], 0);
    expect(
        hub.document.floors.single.rooms
            .where((r) => r.type == RoomType.corridor),
        isEmpty);
    final rows = found.firstWhere((p) => p.layout == 'rows');
    expect(rows.marks['passage'], lessThan(0));
  });

  test('two floors get a stair that can be climbed, whichever way round', () {
    final found = plans(const HouseBrief(
        width: 12000, depth: 10000, floors: 2, bedrooms: 4, bathrooms: 2));
    expect(found, isNotEmpty);
    expect({for (final p in found) p.layout},
        containsAll(['rows', 'rows_turned']));
    for (final p in found) {
      expect(p.document.floors, hasLength(2), reason: p.layout);
      expect(deriveHouse(p.document).floors.first.stairs.single.fits, isTrue,
          reason: p.layout);
    }
  });

  test('a house too small for the rooms has no plan', () {
    expect(plans(const HouseBrief(width: 6000, depth: 6000, bedrooms: 5)),
        isEmpty);
  });

  test('every plan of any brief is a whole house the rules find no error in',
      () {
    for (final (w, d) in [
      (10000, 12000),
      (8000, 8000),
      (15000, 9000),
      (9000, 14000)
    ]) {
      for (final floors in [1, 2]) {
        for (final beds in [2, 4]) {
          for (final extras in [true, false]) {
            final brief = HouseBrief(
                width: w,
                depth: d,
                floors: floors,
                bedrooms: beds,
                bathrooms: extras ? 2 : 1,
                hall: extras,
                boiler: extras,
                storage: extras,
                dining: extras);
            for (final p in plans(brief, count: 4)) {
              final what = '$w×$d f$floors b$beds x$extras ${p.layout}';
              final doc = p.document;
              expect(doc.footprint.width, w, reason: what);
              expect(doc.footprint.depth, d, reason: what);
              expect(doc.floors, hasLength(floors), reason: what);
              expect([
                for (final f in doc.floors)
                  for (final r in f.rooms)
                    if (r.type == RoomType.bedroom) r
              ], hasLength(beds), reason: what);
              expect(
                  runChecks(doc, deriveHouse(doc))
                      .where((c) => c.level == 'error'),
                  isEmpty,
                  reason: what);
            }
          }
        }
      }
    }
  });
}
