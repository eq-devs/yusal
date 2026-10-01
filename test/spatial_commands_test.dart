import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';

void main() {
  var sequence = 0;
  String next() => 'spatial${sequence++}';
  final context = CommandContext(newId: next, now: () => 'unused');
  UndoableDesignState blank() => extractDesignState(createHouse(
      name: '空间',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      timestamp: '2026-09-30T00:00:00Z',
      newId: next));
  CommandResult carve(UndoableDesignState state, int left, int bottom,
          int right, int top) =>
      executeCommand(
          state,
          DesignCommand('CarveRoom', {
            'floorId': state.floors.first.id,
            'left': left,
            'bottom': bottom,
            'right': right,
            'top': top,
            'roomType': RoomType.bathroom,
          }),
          context);

  test('rectangle creates a room with floor-local axes atomically', () {
    final initial = blank();
    final result = carve(initial, 0, 0, 3000, 4000) as Applied;
    expect(initial.axes.floor, isEmpty);
    expect(initial.floors.first.rooms, isEmpty);
    expect(result.newState.axes.global, isEmpty);
    expect(result.newState.axes.floor.length, 2);
    expect(result.newState.floors.first.rooms.single.type, RoomType.bathroom);
    expect(validateDesignState(result.newState), isEmpty);
  });
  test('carving a corner preserves the existing room as an L', () {
    final whole = (carve(blank(), 0, 0, 12000, 10000) as Applied).newState;
    final result = (carve(whole, 0, 0, 3000, 4000) as Applied).newState;
    expect(result.floors.first.rooms.length, 2);
    expect(
        result.floors.first.rooms.first.id, whole.floors.first.rooms.single.id);
    expect(result.floors.first.rooms.first.regions.length, 2);
    expect(validateDesignState(result), isEmpty);
  });
  test('crossing two spaces is rejected and leaves the input intact', () {
    final initial = (carve(blank(), 0, 0, 6000, 10000) as Applied).newState;
    expect(carve(initial, 3000, 0, 9000, 3000), isA<Rejected>());
    expect(initial.floors.first.rooms.length, 1);
    expect(initial.axes.floor.length, 1);
  });
  test('nearby axes reject instead of creating invalid geometry', () {
    final initial = (carve(blank(), 0, 0, 3000, 4000) as Applied).newState;
    expect(carve(initial, 3100, 0, 6000, 4000), isA<Rejected>());
    expect(validateDesignState(initial), isEmpty);
  });
  test('out of bounds and minimum dimensions are rejected', () {
    expect(carve(blank(), -1, 0, 3000, 4000), isA<Rejected>());
    expect(carve(blank(), 0, 0, 299, 4000), isA<Rejected>());
  });
  test('line splits blank space into two rooms with one local axis', () {
    final initial = blank();
    final result = executeCommand(
        initial,
        DesignCommand('SplitSpace', {
          'floorId': initial.floors.first.id,
          'dir': AxisDir.V,
          'pos': 6000,
          'x': 6000,
          'y': 5000,
        }),
        context) as Applied;
    expect(result.newState.floors.first.rooms.length, 2);
    expect(result.newState.axes.floor.length, 1);
    expect(validateDesignState(result.newState), isEmpty);
  });
  test('line partition leaves adjacent room unchanged', () {
    final initial = (carve(blank(), 0, 0, 6000, 10000) as Applied).newState;
    final neighbour = initial.floors.first.rooms.single;
    final result = executeCommand(
        initial,
        DesignCommand('SplitSpace', {
          'floorId': initial.floors.first.id,
          'dir': AxisDir.H,
          'pos': 5000,
          'x': 9000,
          'y': 5000,
        }),
        context) as Applied;
    expect(result.newState.floors.first.rooms.length, 3);
    expect(result.newState.floors.first.rooms.first, neighbour);
    expect(validateDesignState(result.newState), isEmpty);
  });
  test('moving one wall segment preserves neighbours and global coordinates',
      () {
    var doc = createHouse(
        name: '局部墙',
        width: 12000,
        depth: 10000,
        columns: 2,
        rows: 2,
        timestamp: '2026-09-30T00:00:00Z',
        newId: next);
    for (var j = 0; j < 2; j++) {
      for (var i = 0; i < 2; i++) {
        doc = paintCells(
            doc, doc.floors.first.id, [Cell(i, j)], RoomType.custom, next);
      }
    }
    final copied = executeCommand(
        extractDesignState(doc),
        DesignCommand('CopyFloor', {'floorId': doc.floors.first.id}),
        context) as Applied;
    doc = composeDocument(doc.meta, copied.newState);
    final original = extractDesignState(doc);
    final v = doc.axes.global.firstWhere((a) => a.dir == AxisDir.V);
    final h = doc.axes.global.firstWhere((a) => a.dir == AxisDir.H);
    final result = executeCommand(
        original,
        DesignCommand('MoveLocalWall', {
          'floorId': doc.floors.first.id,
          'anchor': BoundaryAnchor(
              axisId: v.id, startAxisId: h.id, endAxisId: '@top'),
          'pos': 7000,
        }),
        context) as Applied;
    expect(result.newState.axes.global, original.axes.global);
    expect(result.newState.floors.last, original.floors.last);
    for (final room in original.floors.first.rooms.where((r) => r.regions
        .every((region) => region.y0 == '@bottom' && region.y1 == h.id))) {
      expect(
          result.newState.floors.first.rooms.firstWhere((r) => r.id == room.id),
          room);
    }
    expect(result.newState.axes.floor.single.pos, 7000);
    expect(validateDesignState(result.newState), isEmpty);
  });
}
