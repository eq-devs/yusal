import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/history/design_history.dart';

void main() {
  test('G1 exterior wall dimensions and net area', () {
    final d =
        loadHouse(File('test/fixtures/minimal_flat.house').readAsBytesSync())
            .document!;
    final g = deriveFloorBase(d, 'f1');
    expect(g.wallSegments.length, 4);
    expect(g.roomGeometry.single.clearArea, 5520 * 4520);
    expect(g.roomGeometry.single.minClearSpan, 4520);
  });
  test('paint connects cells, derives no shared wall, and supports undo', () {
    var id = 0;
    String next() => 'id${id++}';
    final d = createHouse(
        name: '样例',
        width: 12000,
        depth: 10000,
        columns: 3,
        rows: 2,
        timestamp: '2026-09-30T00:00:00Z',
        newId: next);
    final painted = paintCells(d, d.floors.first.id,
        [const Cell(0, 0), const Cell(1, 0)], RoomType.bedroom, next);
    expect(validateHouse(painted), isEmpty);
    expect(painted.floors.first.rooms.length, 1);
    final g = deriveFloorBase(painted, painted.floors.first.id);
    expect(
        g.edges
            .where((e) =>
                e.negative == const Cell(0, 0) &&
                e.positive == const Cell(1, 0))
            .single
            .kind,
        'none');
    final h = DesignHistory(d);
    h.commit(painted);
    h.undo();
    expect(h.present, d);
    h.redo();
    expect(h.present, painted);
  });
}
