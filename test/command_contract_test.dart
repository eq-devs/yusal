import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';

void main() {
  var sequence = 0;
  String next() => 'id${sequence++}';
  final context = CommandContext(
      newId: next, now: () => throw StateError('Core must not read the clock'));
  UndoableDesignState state() => extractDesignState(createHouse(
      name: '测试',
      width: 12000,
      depth: 10000,
      columns: 2,
      rows: 1,
      timestamp: '2026-09-30T00:00:00Z',
      newId: next));
  test('applied commands use design state and never read clocks or metadata',
      () {
    final initial = state();
    final result = executeCommand(
        initial,
        DesignCommand('SetFloorHeight',
            {'floorId': initial.floors.first.id, 'value': 3200}),
        context);
    expect(result, isA<Applied>());
    expect(validateDesignState((result as Applied).newState), isEmpty);
    expect(initial.floors.first.height, 3000);
    expect(result.newState.floors.first.height, 3200);
  });
  test('missing objects are rejected with stable reason codes', () {
    final result = executeCommand(state(),
        DesignCommand('MoveAxis', {'axisId': 'missing', 'pos': 4500}), context);
    expect((result as Rejected).reason, 'NOT_FOUND');
  });
  test('erase of unassigned cells allocates no identities', () {
    final initial = state();
    var allocated = 0;
    final result = executeCommand(
        initial,
        DesignCommand('EraseCells', {
          'floorId': initial.floors.first.id,
          'cells': [const Cell(0, 0)]
        }),
        CommandContext(
            newId: () {
              allocated++;
              return 'new';
            },
            now: () => 'unused'));
    expect((result as Applied).newState, initial);
    expect(allocated, 0);
  });
  test('merging rooms resolves disappearing hosted doors as one transaction',
      () {
    var doc = createHouse(
        name: '合并',
        width: 12000,
        depth: 10000,
        columns: 2,
        rows: 1,
        timestamp: '2026-09-30T00:00:00Z',
        newId: next);
    doc = paintCells(
        doc, doc.floors.first.id, [const Cell(0, 0)], RoomType.living, next);
    doc = paintCells(
        doc, doc.floors.first.id, [const Cell(1, 0)], RoomType.bedroom, next);
    final added = executeCommand(
        extractDesignState(doc),
        DesignCommand('AddOpening', {
          'floorId': doc.floors.first.id,
          'kind': OpeningKind.door,
          'tapT': 5000,
          'centerAtTap': true,
          'anchor': BoundaryAnchor(
              axisId: doc.axes.global.single.id,
              startAxisId: '@bottom',
              endAxisId: '@top'),
        }),
        context) as Applied;
    final arguments = <String, dynamic>{
      'roomIdA': added.newState.floors.first.rooms.first.id,
      'roomIdB': added.newState.floors.first.rooms.last.id
    };
    final preview = executeCommand(
        added.newState, DesignCommand('MergeRooms', arguments), context);
    expect(preview, isA<NeedsResolution>());
    expect(added.newState.floors.first.openings.length, 1);
    final applied = executeCommand(
        added.newState,
        DesignCommand(
            'MergeRooms', {...arguments, 'deleteHostedObjects': true}),
        context) as Applied;
    expect(applied.newState.floors.first.rooms.length, 1);
    expect(applied.newState.floors.first.openings, isEmpty);
    expect(validateDesignState(applied.newState), isEmpty);
  });
  test('direct opening placement follows the drop and rejects overlap', () {
    final initial = state();
    final arguments = <String, dynamic>{
      'floorId': initial.floors.first.id,
      'anchor': const BoundaryAnchor(
          axisId: '@bottom', startAxisId: '@left', endAxisId: '@right'),
      'tapT': 5000,
      'kind': OpeningKind.door,
      'centerAtTap': true
    };
    final first =
        executeCommand(initial, DesignCommand('AddOpening', arguments), context)
            as Applied;
    final position = first.newState.floors.first.openings.single.position
        as FromStartPosition;
    expect(position.d, 4550);
    final overlapping = executeCommand(
        first.newState, DesignCommand('AddOpening', arguments), context);
    expect(overlapping, isA<Rejected>());
    expect(first.newState.floors.first.openings.length, 1);
  });
}
