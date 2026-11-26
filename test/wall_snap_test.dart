import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/util/wall_attachment_points.dart';
import 'package:yusal/features/editor/util/wall_snap.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'snap_${ids++}', now: () => '2026-10-08T00:00:00Z');
  HouseDocument house(List<List<int>> walls) {
    var s = extractDesignState(createHouse(
        name: '吸附',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
        newId: ctx.newId));
    for (final w in walls) {
      s = (executeCommand(
              s,
              DesignCommand('AddDrawnWall', {
                'floorId': s.floors.first.id,
                'x0': w[0],
                'y0': w[1],
                'x1': w[2],
                'y1': w[3]
              }),
              ctx) as Applied)
          .newState;
    }
    return composeDocument(
        Meta(name: '吸附', createdAt: ctx.now(), updatedAt: ctx.now()), s);
  }

  FloorBase base(HouseDocument doc) =>
      deriveFloorBase(doc, doc.floors.first.id);

  test('a wall end near a crossing wall joins it and reports the join', () {
    final b = base(house([]));
    final snap = snapWallEnd(
        b, const Offset(6000, 10000), const Offset(6040, 450),
        connectRadius: 600, alignRadius: 300);
    expect(snap.end, const Offset(6000, 0));
    expect(snap.connected, isTrue);
    expect(snap.horizontal, isFalse);
  });

  test('a free end stays where it is dropped, on the 100 mm grid', () {
    final b = base(house([]));
    final snap = snapWallEnd(
        b, const Offset(6000, 10000), const Offset(6000, 4440),
        connectRadius: 600, alignRadius: 300);
    expect(snap.end, const Offset(6000, 4400));
    expect(snap.connected, isFalse);
  });

  test('dragging past the house stops on the outer wall', () {
    final b = base(house([]));
    final snap = snapWallEnd(
        b, const Offset(0, 5000), const Offset(15000, 5100),
        connectRadius: 100, alignRadius: 100);
    expect(snap.end, const Offset(12000, 5000));
    expect(snap.connected, isTrue);
  });

  test('ends align with existing wall coordinates and join collinear ends', () {
    final b = base(house([
      [3000, 0, 3000, 4000],
      [8000, 6000, 12000, 6000]
    ]));
    // Aligns with x=3 m although no wall crosses y=7 m there.
    final aligned = snapWallEnd(
        b, const Offset(0, 7000), const Offset(3150, 7000),
        connectRadius: 100, alignRadius: 300);
    expect(aligned.end, const Offset(3000, 7000));
    expect(aligned.connected, isFalse);
    // Meets the start of the collinear wall at x=8 m.
    final collinear = snapWallEnd(
        b, const Offset(0, 6000), const Offset(7600, 6000),
        connectRadius: 600, alignRadius: 300);
    expect(collinear.end, const Offset(8000, 6000));
    expect(collinear.connected, isTrue);
  });

  test('resizing ignores the wall itself and its old end', () {
    final b = base(house([
      [6000, 0, 6000, 4000]
    ]));
    bool own(WallSegment w) =>
        w.axis.dir == AxisDir.V && w.axis.pos == 6000 && w.end.pos <= 4000;
    final snap = snapWallEnd(b, const Offset(6000, 0), const Offset(6000, 4100),
        connectRadius: 600,
        alignRadius: 300,
        forceHorizontal: false,
        ignore: own,
        skipAlong: {4000});
    expect(snap.end, const Offset(6000, 4100));
    expect(snap.connected, isFalse);
  });

  test('picking at a junction prefers the inner, shorter wall', () {
    final b = base(house([
      [6000, 0, 6000, 1000]
    ]));
    final wall = nearestWall(b, const Offset(6000, 30), 200)!;
    expect(wall.axis.kind, isNot('boundary'));
    expect(wall.axis.pos, 6000);
    expect(nearestWall(b, const Offset(3000, 5000), 200), isNull);
  });

  test('short walls keep finger-sized grips apart', () {
    final long = wallGrips(Offset.zero, const Offset(200, 0), zoom: 1);
    expect(long.middle, const Offset(100, 0));
    final short = wallGrips(Offset.zero, const Offset(20, 0), zoom: 1);
    expect(short.middle, isNull);
    expect((short.end - short.start).distance, 88);
    // Zooming in makes the same wall long enough on screen.
    expect(
        wallGrips(Offset.zero, const Offset(20, 0), zoom: 5).middle, isNotNull);
  });

  test('a T junction on the outer wall is a dead end for new walls', () {
    final doc = house([
      [6000, 0, 6000, 10000]
    ]);
    final b = base(doc);
    expect(canExtendWallFrom(b, const [], const Offset(6000, 0)), isFalse);
    expect(canExtendWallFrom(b, const [], const Offset(6000, 5000)), isTrue);
  });

  group('hysteresis', () {
    // A vertical wall at x = 6000 to join.
    final b = base(house([
      [6000, 0, 6000, 10000]
    ]));
    const origin = Offset(2000, 5000);
    WallEndSnap snap(Offset raw, [WallEndSnap? previous]) => snapWallEnd(
        b, origin, raw,
        connectRadius: 220, alignRadius: 140, previous: previous);

    test('a join holds until the finger is well past its radius', () {
      final joined = snap(const Offset(5900, 5000));
      expect(joined.connected, isTrue);
      expect(joined.end.dx, 6000);
      // 260 mm off: outside the 220 mm radius, inside 1.5 times it.
      expect(snap(const Offset(5740, 5000)).end.dx, isNot(6000));
      expect(snap(const Offset(5740, 5000), joined).end.dx, 6000);
      // 400 mm off lets go.
      expect(snap(const Offset(5600, 5000), joined).end.dx, isNot(6000));
    });

    test('the direction holds near the diagonal', () {
      final across = snap(const Offset(4000, 5100));
      expect(across.horizontal, isTrue);
      // Slightly more up than across: a fresh snap turns, a held one not.
      const raw = Offset(4000, 7100);
      expect(snap(raw).horizontal, isFalse);
      expect(snap(raw, across).horizontal, isTrue);
      // Clearly up turns it.
      expect(snap(const Offset(3000, 8000), across).horizontal, isFalse);
    });
  });

  group('measuring', () {
    const walls = [PlanRect(5940, 0, 6060, 10000)];
    test('a point near a wall corner lands on it', () {
      expect(snapMeasurePoint(walls, const Offset(5930, 30), 100),
          const Offset(5940, 0));
    });
    test('a point near a wall face lands on the face', () {
      expect(snapMeasurePoint(walls, const Offset(5900, 4003), 100),
          const Offset(5940, 4000));
      expect(snapMeasurePoint(walls, const Offset(6110, 4003), 100),
          const Offset(6060, 4000));
    });
    test('away from walls it keeps to the 50 mm grid', () {
      expect(snapMeasurePoint(walls, const Offset(2012, 3038), 100),
          const Offset(2000, 3050));
    });
  });
}
