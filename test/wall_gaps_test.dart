// A drawn wall that stops short of the next one leaves the room open: the
// checks say so and say where.
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/wall_gaps.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'gap_${ids++}', now: () => '2026-11-23T00:00:00Z');
  UndoableDesignState initial() => extractDesignState(createHouse(
      name: '缺口',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: ctx.newId));
  HouseDocument doc(UndoableDesignState s) => composeDocument(
      Meta(name: '缺口', createdAt: ctx.now(), updatedAt: ctx.now()), s);
  UndoableDesignState add(
      UndoableDesignState s, int x0, int y0, int x1, int y1) {
    final r = executeCommand(
        s,
        DesignCommand('AddDrawnWall', {
          'floorId': s.floors.first.id,
          'x0': x0,
          'y0': y0,
          'x1': x1,
          'y1': y1
        }),
        ctx);
    expect(r, isA<Applied>(), reason: r is Rejected ? r.message : null);
    return (r as Applied).newState;
  }

  List<WallGap> gaps(UndoableDesignState s) =>
      findWallGaps(deriveHouse(doc(s)).floors.first.base);
  List<CheckResult> r14(UndoableDesignState s) {
    final d = doc(s);
    return runChecks(d, deriveHouse(d))
        .where((c) => c.ruleId == 'R14')
        .toList();
  }

  test('a wall drawn from side to side leaves no gap', () {
    final s = add(initial(), 6000, 0, 6000, 10000);
    expect(s.floors.first.rooms, hasLength(2));
    expect(gaps(s), isEmpty);
    expect(r14(s), isEmpty);
  });

  test('a wall that stops a metre short is found, with where', () {
    final s = add(initial(), 6000, 0, 6000, 9000);
    // Both sides are still one room.
    expect(s.floors.first.rooms, hasLength(1));
    final found = gaps(s);
    expect(found, hasLength(1));
    final g = found.single;
    expect((g.x0, g.y0, g.x1, g.y1), (6000.0, 9000.0, 6000.0, 10000.0));
    expect(g.length, 1000);
    expect(g.roomId, s.floors.first.rooms.single.id);
    final check = r14(s).single;
    expect(check.level, 'suggestion');
    expect(check.message, contains('1.00'));
    expect(check.focus!.left, 6000);
    expect(check.focus!.bottom, 9000);
    expect(check.focus!.top, 10000);
    expect(check.objectIds, [s.floors.first.rooms.single.id]);
  });

  test('closing the wall clears it', () {
    var s = add(initial(), 6000, 0, 6000, 9000);
    expect(gaps(s), hasLength(1));
    s = add(s, 6000, 9000, 6000, 10000);
    expect(gaps(s), isEmpty);
    expect(s.floors.first.rooms, hasLength(2));
  });

  test('a wall that stops far from the next is an open plan, not a gap', () {
    final s = add(initial(), 6000, 0, 6000, 5000);
    expect(gaps(s), isEmpty);
    expect(r14(s), isEmpty);
    // Asked with a wider limit, the same end is reported.
    expect(findWallGaps(deriveHouse(doc(s)).floors.first.base, widest: 6000),
        hasLength(1));
  });

  test('two wall ends that face each other are one gap', () {
    var s = add(initial(), 0, 5000, 5400, 5000);
    s = add(s, 6600, 5000, 12000, 5000);
    final found = gaps(s);
    expect(found, hasLength(1));
    expect(found.single.length, 1200);
    expect(found.single.area.left, 5400);
    expect(found.single.area.right, 6600);
  });

  test('a floor without drawn walls reports none', () {
    final s = initial();
    expect(s.floors.first.explicitWalls, isFalse);
    expect(r14(s), isEmpty);
  });
}
