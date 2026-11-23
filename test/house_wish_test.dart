import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/house_spec.dart';
import 'package:yusal/features/editor/engine/core/commands/house_wish.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

void main() {
  var n = 0;
  HouseSpecResult build(int w, int d, int floors, int beds, int baths,
          {bool extras = true}) =>
      buildHouseFromSpec(
          wishSpec(
              name: '初稿',
              width: w,
              depth: d,
              floors: floors,
              bedrooms: beds,
              bathrooms: baths,
              hall: extras,
              boiler: extras,
              storage: extras,
              dining: extras),
          '2026-11-17T00:00:00Z',
          () => 'w${n++}');

  test('the usual wish becomes a whole house with nothing left out', () {
    final built = build(12000, 10000, 1, 3, 1);
    expect(built.errors, isEmpty);
    expect(built.notes, isEmpty);
    final doc = built.document!;
    final types = [for (final r in doc.floors.single.rooms) r.type];
    expect(types.where((t) => t == RoomType.bedroom), hasLength(3));
    for (final t in [
      RoomType.living,
      RoomType.kitchen,
      RoomType.bathroom,
      RoomType.hall,
      RoomType.boiler,
      RoomType.corridor
    ]) {
      expect(types, contains(t), reason: '$t');
    }
    expect(doc.mainEntranceOpeningId, isNotNull);
    // Every room can be walked into and the day rooms have windows.
    final issues = [
      for (final c in runChecks(doc, deriveHouse(doc)))
        if (c.level == 'error') '${c.ruleId}: ${c.message}'
    ];
    expect(issues, isEmpty);
  });

  test('two floors get a stair that can be climbed, open to its hall', () {
    final built = build(12000, 10000, 2, 4, 2);
    expect(built.errors, isEmpty);
    expect(built.notes, isEmpty);
    final doc = built.document!;
    expect(doc.floors, hasLength(2));
    expect(doc.floors.first.stairs, hasLength(1));
    expect(deriveHouse(doc).floors.first.stairs.single.fits, isTrue);
    final beds = [
      for (final f in doc.floors)
        f.rooms.where((r) => r.type == RoomType.bedroom).length
    ];
    expect(beds, [1, 3]);
  });

  test('any answer the questions allow gives a house', () {
    final notes = <String>[];
    var refused = 0;
    for (final (w, d) in [
      (12000, 10000),
      (10000, 12000),
      (8000, 8000),
      (15000, 9000),
      (9500, 10000),
      (7000, 5500),
      (20000, 12000),
      (6000, 6000)
    ]) {
      for (final floors in [1, 2]) {
        for (final beds in [1, 2, 3, 4, 5]) {
          for (final baths in [1, 2]) {
            for (final extras in [true, false]) {
              final what = '$w×$d f$floors b$beds t$baths x$extras';
              // A wish the house cannot hold is turned down by the
              // questions before anything is drawn.
              if (wishTooSmall(wishSpec(
                  name: '初稿',
                  width: w,
                  depth: d,
                  floors: floors,
                  bedrooms: beds,
                  bathrooms: baths,
                  hall: extras,
                  boiler: extras,
                  storage: extras,
                  dining: extras))) {
                refused++;
                continue;
              }
              final built = build(w, d, floors, beds, baths, extras: extras);
              expect(built.document, isNotNull,
                  reason: '$what: ${built.errors}');
              final doc = built.document!;
              expect(doc.floors, hasLength(floors), reason: what);
              final all = [
                for (final f in doc.floors)
                  for (final r in f.rooms) r.type
              ];
              expect(all.where((t) => t == RoomType.bedroom), hasLength(beds),
                  reason: what);
              expect(all, contains(RoomType.living), reason: what);
              expect(all, contains(RoomType.kitchen), reason: what);
              if (built.notes.isNotEmpty) {
                notes.add('$what: ${built.notes.join('; ')}');
              }
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print(
        '$refused refused, ${notes.length} with notes\n${notes.take(40).join('\n')}');
  });
}
