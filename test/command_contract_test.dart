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
}
