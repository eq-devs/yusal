// Low walls: knee walls, bars and balustrades. One can see over them, so
// they divide no room.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/command_catalog.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'low_${ids++}', now: () => '2026-11-23T00:00:00Z');
  UndoableDesignState initial() => extractDesignState(createHouse(
      name: '矮墙',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: ctx.newId));
  HouseDocument doc(UndoableDesignState s) => composeDocument(
      Meta(name: '矮墙', createdAt: ctx.now(), updatedAt: ctx.now()), s);
  CommandResult run(
          UndoableDesignState s, String kind, Map<String, dynamic> args) =>
      executeCommand(
          s, DesignCommand(kind, {'floorId': s.floors.first.id, ...args}), ctx);
  UndoableDesignState ok(CommandResult r) {
    expect(r, isA<Applied>(), reason: r is Rejected ? r.message : null);
    return (r as Applied).newState;
  }

  Map<String, dynamic> line(int x0, int y0, int x1, int y1) =>
      {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1};
  SolidWall only(UndoableDesignState s) =>
      s.floors.first.wallOverrides.whereType<SolidWall>().single;

  test('a low wall from side to side leaves one room', () {
    final s = ok(run(initial(), 'AddDrawnWall',
        {...line(6000, 0, 6000, 10000), 'height': 1100}));
    expect(only(s).height, 1100);
    expect(s.floors.first.rooms, hasLength(1));
    final base = deriveHouse(doc(s)).floors.first.base;
    expect(base.lowWalls, hasLength(1));
    final low = base.lowWalls.single;
    expect(low.height, 1100);
    expect((low.rect.left, low.rect.right), (5940.0, 6060.0));
    expect((low.rect.bottom, low.rect.top), (0.0, 10000.0));
    expect(base.wallSegments.any((w) => w.axis.pos == 6000), isFalse);
    expect(base.allWallSegments.any((w) => w.kind == 'low'), isTrue);
  });

  test('raising it to the ceiling divides the room, lowering joins it again',
      () {
    var s = ok(run(initial(), 'AddDrawnWall',
        {...line(6000, 0, 6000, 10000), 'height': 900}));
    final id = only(s).id;
    s = ok(run(s, 'SetDrawnWallHeight', {'wallId': id, 'height': 0}));
    expect(only(s).height, isNull);
    expect(only(s).id, id);
    expect(s.floors.first.rooms, hasLength(2));
    s = ok(run(s, 'SetDrawnWallHeight', {'wallId': id, 'height': 1500}));
    expect(only(s).height, 1500);
    expect(s.floors.first.rooms, hasLength(1));
  });

  test('a low wall keeps its height when stretched or moved', () {
    var s = ok(run(initial(), 'AddDrawnWall',
        {...line(6000, 0, 6000, 4000), 'height': 900}));
    final id = only(s).id;
    s = ok(run(
        s, 'UpdateDrawnWall', {'wallId': id, ...line(6000, 0, 6000, 6000)}));
    expect(only(s).height, 900);
    s = ok(run(s, 'MoveDrawnWall', {'wallId': id, 'pos': 7000}));
    expect(only(s).height, 900);
    final low = deriveHouse(doc(s)).floors.first.base.lowWalls.single;
    expect(low.rect.left, 6940);
    expect(low.rect.top, 6000);
  });

  test('heights outside 0.3 to 2.1 m are refused', () {
    for (final h in [100, 299, 2101, 5000]) {
      final r = run(initial(), 'AddDrawnWall',
          {...line(6000, 0, 6000, 10000), 'height': h});
      expect(r, isA<Rejected>(), reason: '$h');
    }
  });

  test('a wall with a door cannot be made low', () {
    var s = ok(run(initial(), 'AddDrawnWall', line(6000, 0, 6000, 10000)));
    final wall = only(s);
    s = ok(run(s, 'AddOpening',
        {'anchor': wall.anchor, 'kind': OpeningKind.door, 'tapT': 5000.0}));
    expect(s.floors.first.openings, hasLength(1));
    final r = run(s, 'SetDrawnWallHeight', {'wallId': wall.id, 'height': 900});
    expect(r, isA<Rejected>());
    expect((r as Rejected).message, contains('门窗'));
  });

  test('a low wall end is no gap, and the room it stands in keeps its area',
      () {
    final whole = initial();
    final s = ok(run(
        whole, 'AddDrawnWall', {...line(6000, 0, 6000, 9000), 'height': 900}));
    final d = doc(s);
    final derived = deriveHouse(d);
    expect(runChecks(d, derived).where((c) => c.ruleId == 'R14'), isEmpty);
    final before =
        deriveHouse(doc(whole)).floors.first.base.roomGeometry.single.clearArea;
    expect(derived.floors.first.base.roomGeometry.single.clearArea, before);
  });

  test('it survives saving and reading, and a room edit beside it', () {
    var s = ok(run(initial(), 'AddDrawnWall',
        {...line(6000, 0, 6000, 5000), 'height': 1100}));
    final text = encodeHouse(doc(s));
    expect(text, contains('"height": 1100'));
    final back = loadHouse(utf8.encode(text));
    expect([for (final e in back.failure?.errors ?? const <LoadError>[]) '${e.code} ${e.path} ${e.message}'], isEmpty, reason: back.failure?.stage);
    expect(back.document, doc(s));
    expect(
        back.document!.floors.first.wallOverrides
            .whereType<SolidWall>()
            .single
            .height,
        1100);
    // A full wall drawn elsewhere re-reads the rooms; the low wall stays.
    s = ok(run(s, 'AddDrawnWall', line(0, 7000, 12000, 7000)));
    final walls = s.floors.first.wallOverrides.whereType<SolidWall>().toList();
    expect(walls.where((w) => w.low), hasLength(1));
    expect(walls.where((w) => !w.low), isNotEmpty);
    expect(s.floors.first.rooms, hasLength(2));
    // And a room command that brings walls in line with rooms.
    final room = s.floors.first.rooms.first;
    s = ok(run(s, 'RenameRoom', {'roomId': room.id, 'value': '客厅'}));
    expect(
        s.floors.first.wallOverrides.whereType<SolidWall>().where((w) => w.low),
        hasLength(1));
  });

  test('in 3D it stands as high as it is and can be picked as a wall', () {
    final s = ok(run(initial(), 'AddDrawnWall',
        {...line(6000, 0, 6000, 10000), 'height': 1100}));
    final d = doc(s);
    final derived = deriveHouse(d);
    final model = buildScene(d, derived, const SceneOptions(), (r) => r.name);
    final ref = derived.floors.first.base.lowWalls.single.ref;
    final faces = model.faces
        .where((f) =>
            f.source is WallSource && (f.source! as WallSource).wall == ref)
        .toList();
    expect(faces, isNotEmpty);
    final top = faces
        .expand((f) => f.points)
        .map((p) => p.y)
        .reduce((a, b) => a > b ? a : b);
    final bottom = faces
        .expand((f) => f.points)
        .map((p) => p.y)
        .reduce((a, b) => a < b ? a : b);
    expect(top - bottom, closeTo(1.1, 1e-6));
  });

  test('the catalog offers the height to an assistant', () {
    final spec = commandSpec('SetDrawnWallHeight')!;
    expect(spec.arguments.map((a) => a.name),
        containsAll(['floorId', 'wallId', 'height']));
    expect(commandSpec('AddDrawnWall')!.arguments.map((a) => a.name),
        contains('height'));
    final state = initial();
    final r = executeJsonCommand(
        state,
        'AddDrawnWall',
        {
          'floorId': state.floors.first.id,
          ...line(6000, 0, 6000, 10000),
          'height': 900
        },
        ctx);
    expect(r, isA<Applied>());
  });
}
