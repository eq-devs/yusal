import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';

void main() {
  test('10,000 seeded cell sets preserve cells and canonical idempotence', () {
    var sequence = 0;
    final doc = createHouse(
        name: '性质测试',
        width: 12000,
        depth: 10000,
        columns: 5,
        rows: 5,
        timestamp: '2026-09-30T00:00:00Z',
        newId: () => 'id${sequence++}');
    final axes = resolveFloorAxes(doc, doc.floors.first.id)!;
    final random = Random(712345);
    for (var sample = 0; sample < 10000; sample++) {
      final cells = <Cell>{
        for (var j = 0; j < 5; j++)
          for (var i = 0; i < 5; i++)
            if (random.nextBool()) Cell(i, j),
      };
      final first = canonicalizeCells(axes, cells);
      expect(first.isSuccess, isTrue);
      final expanded = regionCells(axes, first.regions);
      expect(expanded.cells, cells);
      expect(expanded.selfOverlap, isFalse);
      expect(canonicalizeCells(axes, expanded.cells).regions, first.regions);
      final blocks = components(axes, cells).cells;
      expect(blocks.expand((c) => c).toSet(), cells);
      expect(blocks.every(isConnected), isTrue);
    }
  });
}
