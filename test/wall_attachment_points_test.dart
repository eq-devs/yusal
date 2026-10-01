import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/features/wall_attachment_points.dart';

void main() {
  test('occupied exterior corners and door holes have no extension marker', () {
    var id = 0;
    String next() => 'attachment_${id++}';
    var doc = createHouse(
        name: '接点',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: '2026-10-01T00:00:00Z',
        newId: next);
    final ctx = CommandContext(newId: next, now: () => 'unused');
    void edit(String kind, Map<String, dynamic> args) {
      final result = executeCommand(
          extractDesignState(doc),
          DesignCommand(kind, {'floorId': doc.floors.first.id, ...args}),
          ctx) as Applied;
      doc = composeDocument(doc.meta, result.newState);
    }

    final first = deriveHouse(doc).floors.first;
    expect(wallAttachmentPoints(first.base, first.openings).length, 4);
    expect(wallAttachmentPoints(first.base, first.openings),
        isNot(contains(Offset.zero)));
    edit('AddDrawnWall', {'x0': 2000, 'y0': 3000, 'x1': 6000, 'y1': 3000});
    final wall = doc.floors.first.wallOverrides.whereType<SolidWall>().single;
    edit('AddOpening', {
      'anchor': wall.anchor,
      'kind': OpeningKind.door,
      'centerAtTap': true,
      'tapT': 2000.0
    });
    final derived = deriveHouse(doc).floors.first;
    final nodes = wallAttachmentPoints(derived.base, derived.openings);
    expect(nodes, contains(const Offset(2000, 3000)));
    expect(nodes, contains(const Offset(6000, 3000)));
    expect(nodes, isNot(contains(const Offset(4000, 3000))));
  });
}
