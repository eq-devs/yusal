import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

void main() {
  var n = 0;
  String next() => 'so${n++}';
  final ctx = CommandContext(newId: next, now: () => '2026-11-17T00:00:00Z');

  HouseDocument house() => createHouse(
      name: '楼梯',
      width: 10000,
      depth: 12000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: next);

  CommandResult attempt(
          HouseDocument doc, String kind, Map<String, dynamic> a) =>
      executeCommand(extractDesignState(doc), DesignCommand(kind, a), ctx);

  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> a) {
    final r = attempt(doc, kind, a);
    expect(r, isA<Applied>(),
        reason: '$kind: ${r is Rejected ? r.message : r}');
    return composeDocument(doc.meta, (r as Applied).newState);
  }

  HouseDocument twoFloors() {
    final doc = house();
    return run(doc, 'AddFloor', {'floorId': doc.floors.first.id});
  }

  List<int> xs(HouseDocument doc) =>
      [for (final a in resolveFloorAxes(doc, doc.floors.first.id)!.v) a.pos];
  List<int> ys(HouseDocument doc) =>
      [for (final a in resolveFloorAxes(doc, doc.floors.first.id)!.h) a.pos];

  Map<String, dynamic> at(HouseDocument doc, int l, int b, int r, int t) => {
        'floorId': doc.floors.first.id,
        'left': l,
        'bottom': b,
        'right': r,
        'top': t
      };

  test('a stair is put down in a room and stays open to it', () {
    var doc = twoFloors();
    doc = run(doc, 'PlaceStair', at(doc, 0, 0, 2400, 3600));
    final floor = doc.floors.first;
    expect(floor.stairs, hasLength(1));
    expect(floor.rooms, hasLength(1), reason: 'the room is not cut in two');
    final geometry = deriveHouse(doc).floors.first.stairs.single;
    expect(geometry.fits, isTrue);
    // Nothing is built between the stair and its room.
    final walls = deriveFloorBase(doc, floor.id).wallSegments;
    expect(
        walls.where((w) =>
            w.kind != 'open' &&
            ((w.axis.dir == AxisDir.V && w.axis.pos == 2400) ||
                (w.axis.dir == AxisDir.H && w.axis.pos == 3600))),
        isEmpty);
  });

  test('a long narrow place gets a straight flight', () {
    var doc = twoFloors();
    doc = run(doc, 'PlaceStair', at(doc, 0, 0, 1200, 5000));
    expect(doc.floors.first.stairs.single.type, StairType.straight);
    // Lying down in the corner, its first step is at the end the room
    // reaches, not the one against the outer wall.
    var wide = twoFloors();
    wide = run(wide, 'PlaceStair', at(wide, 0, 0, 5000, 1200));
    expect(wide.floors.first.stairs.single.startEdge, StairEdge.right);
    expect(deriveHouse(wide).floors.first.stairs.single.fits, isTrue);
  });

  test('a stair moves and leaves nothing behind', () {
    var doc = twoFloors();
    doc = run(doc, 'PlaceStair', at(doc, 0, 0, 2400, 3600));
    final id = doc.floors.first.stairs.single.id;
    final shape = doc.floors.first.stairs.single.type;
    doc = run(doc, 'PlaceStair',
        {...at(doc, 7600, 8400, 10000, 12000), 'stairId': id});
    expect(doc.floors.first.stairs, hasLength(1));
    expect(doc.floors.first.stairs.single.type, shape);
    expect(doc.floors.first.rooms, hasLength(1));
    expect(xs(doc), [0, 7600, 10000]);
    expect(ys(doc), [0, 8400, 12000]);
    // Nudged by a hand's width: its own old lines are not in the way.
    final moved = doc.floors.first.stairs.single.id;
    doc = run(doc, 'PlaceStair',
        {...at(doc, 7300, 8100, 9700, 11500), 'stairId': moved});
    expect(xs(doc), [0, 7300, 9700, 10000]);
  });

  test('a removed stair gives its place back to the room', () {
    var doc = twoFloors();
    doc = run(doc, 'PlaceStair', at(doc, 0, 0, 2400, 3600));
    doc =
        run(doc, 'RemoveStair', {'stairId': doc.floors.first.stairs.single.id});
    final floor = doc.floors.first;
    expect(floor.stairs, isEmpty);
    expect(floor.wallOverrides, isEmpty);
    expect(xs(doc), [0, 10000]);
    expect(ys(doc), [0, 12000]);
    final axes = resolveFloorAxes(doc, floor.id)!;
    final r = resolveRect(axes, floor.rooms.single.regions.single).rect!;
    expect((r.left, r.bottom, r.right, r.top), (0, 0, 10000, 12000));
  });

  test('a stair that cannot work is refused with the size it needs', () {
    final single = house();
    final top = attempt(single, 'PlaceStair', at(single, 0, 0, 2400, 3600));
    expect(top, isA<Rejected>());
    expect((top as Rejected).message, contains('上方'));
    final doc = twoFloors();
    final small = attempt(doc, 'PlaceStair', at(doc, 0, 0, 1000, 1500));
    expect((small as Rejected).message, contains('放不下'));
    // Across two rooms.
    var split = run(doc, 'AddDrawnWall', {
      'floorId': doc.floors.first.id,
      'x0': 0,
      'y0': 5000,
      'x1': 10000,
      'y1': 5000
    });
    final across = attempt(split, 'PlaceStair', at(split, 0, 3000, 2400, 6600));
    expect(across, isA<Rejected>());
    // Inside one of them it works, walls drawn by hand or not.
    split = run(split, 'PlaceStair', at(split, 0, 0, 2400, 3600));
    expect(split.floors.first.rooms, hasLength(2));
    expect(deriveHouse(split).floors.first.stairs.single.fits, isTrue);
    final walls = deriveFloorBase(split, split.floors.first.id).wallSegments;
    expect(
        walls.where((w) =>
            w.kind != 'open' && w.axis.dir == AxisDir.V && w.axis.pos == 2400),
        isEmpty);
    split = run(
        split, 'RemoveStair', {'stairId': split.floors.first.stairs.single.id});
    expect(split.floors.first.rooms, hasLength(2));
    expect(xs(split), [0, 10000]);
  });
}
