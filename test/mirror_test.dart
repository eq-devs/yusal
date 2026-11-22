import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/checks/check_engine.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/house_core.dart';

void main() {
  var n = 0;
  String next() => 'mi${n++}';
  const stamp = '2026-11-16T00:00:00Z';
  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        extractDesignState(doc),
        DesignCommand(kind, args),
        CommandContext(newId: next, now: () => stamp));
    expect(result, isA<Applied>(),
        reason: result is Rejected ? result.message : kind);
    return composeDocument(doc.meta, (result as Applied).newState);
  }

  final houses = <String, HouseDocument Function()>{
    'kz': () => createKazakhTemplate(stamp, next),
    for (final kind in ['three', 'five', 'two'])
      kind: () => createTemplate(kind, stamp, next),
    'L-shaped': () => run(
        createHouse(
            name: 'L',
            width: 10000,
            depth: 8000,
            columns: 1,
            rows: 1,
            initialRoom: true,
            timestamp: stamp,
            newId: next),
        'CutOutline',
        {'corner': 'tr', 'width': 3000, 'depth': 2500}),
  };

  for (final direction in ['horizontal', 'vertical']) {
    final horizontal = direction == 'horizontal';
    for (final entry in houses.entries) {
      test('${entry.key} flipped $direction mirrors every wall and opening',
          () {
        final before = entry.value();
        final after = run(before, 'MirrorPlan', {'direction': direction});
        final a = deriveHouse(before);
        final b = deriveHouse(after);
        final size =
            (horizontal ? before.footprint.width : before.footprint.depth)
                .toDouble();
        for (var f = 0; f < a.floors.length; f++) {
          // Walls: the same segments at mirrored places.
          String wall(AxisDir dir, num pos, num start, num end, num t) =>
              '$dir ${pos.round()} ${start.round()} ${end.round()} ${t.round()}';
          final flips = horizontal ? AxisDir.V : AxisDir.H;
          expect({
            for (final w in b.floors[f].base.wallSegments)
              wall(w.axis.dir, w.axis.pos, w.start.pos, w.end.pos, w.thickness)
          }, {
            for (final w in a.floors[f].base.wallSegments)
              w.axis.dir == flips
                  ? wall(w.axis.dir, size - w.axis.pos, w.start.pos, w.end.pos,
                      w.thickness)
                  : wall(w.axis.dir, w.axis.pos, size - w.end.pos,
                      size - w.start.pos, w.thickness)
          });
          // Openings stay valid and land at the mirrored stretch.
          for (final p in a.floors[f].openings) {
            final q = b.floors[f].openings
                .firstWhere((x) => x.opening.id == p.opening.id);
            expect(q.status, p.status);
            if (p.axis.dir == flips) {
              expect(q.axis.pos, size - p.axis.pos);
              expect((q.start, q.end), (p.start, p.end));
            } else {
              expect(q.axis.pos, p.axis.pos);
              expect((q.start, q.end), (size - p.end, size - p.start));
            }
          }
          // Rooms keep their areas.
          for (final r in a.floors[f].base.roomGeometry) {
            final s =
                b.floors[f].base.roomGeometry.firstWhere((x) => x.id == r.id);
            expect(s.clearArea, r.clearArea, reason: r.id);
          }
          // Stairs still fit, with as many steps.
          for (final s in a.floors[f].stairs) {
            final t =
                b.floors[f].stairs.firstWhere((x) => x.stairId == s.stairId);
            expect(t.fits, s.fits);
            expect(t.steps.length, s.steps.length);
          }
        }
        expect(runChecks(after, b).map((c) => c.ruleId).toList(),
            runChecks(before, a).map((c) => c.ruleId).toList());
        // Furniture stays inside the house, mirrored.
        for (final item in before.extras.furniture) {
          final moved =
              after.extras.furniture.firstWhere((x) => x.id == item.id);
          if (horizontal) {
            expect(moved.x, before.footprint.width - item.x - item.width);
            expect(moved.y, item.y);
          } else {
            expect(moved.y, before.footprint.depth - item.y - item.depth);
            expect(moved.x, item.x);
          }
        }
        // Flipping back gives the design it started from.
        expect(encodeHouse(run(after, 'MirrorPlan', {'direction': direction})),
            encodeHouse(before));
      });
    }
  }

  test('a hinged door swings to the mirrored side', () {
    final before = createKazakhTemplate(stamp, next);
    final after = run(before, 'MirrorPlan', {'direction': 'horizontal'});
    final axes = resolveFloorAxes(before, before.floors.first.id)!;
    for (final o in before.floors.first.openings.whereType<DoorOpening>()) {
      final m = after.floors.first.openings
          .whereType<DoorOpening>()
          .firstWhere((x) => x.id == o.id);
      final vertical = lookupAxis(axes, o.anchor.axisId).axis!.dir == AxisDir.V;
      // A door in a wall running up the plan opens to the other side of
      // it; one in a wall running across keeps its side and swaps hinge.
      expect(m.opensTo == o.opensTo, !vertical, reason: o.id);
      expect(m.hinge == o.hinge, vertical, reason: o.id);
    }
  });
}
