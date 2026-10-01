import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/geometry/derived_house.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'wall_test_${ids++}', now: () => '2026-10-01T00:00:00Z');
  UndoableDesignState initial() => extractDesignState(createHouse(
      name: '绘墙',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: ctx.newId));
  CommandResult edit(
          UndoableDesignState s, String kind, Map<String, dynamic> args) =>
      executeCommand(
          s, DesignCommand(kind, {'floorId': s.floors.first.id, ...args}), ctx);
  UndoableDesignState add(
      UndoableDesignState s, int x0, int y0, int x1, int y1) {
    final r = edit(s, 'AddDrawnWall', {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1});
    expect(r, isA<Applied>(), reason: r is Rejected ? r.message : null);
    return (r as Applied).newState;
  }

  HouseDocument doc(UndoableDesignState s) => composeDocument(
      Meta(name: '绘墙', createdAt: ctx.now(), updatedAt: ctx.now()), s);
  test(
      'legacy open-plan zones survive migration and can receive a partial wall',
      () {
    var s = initial();
    s = (edit(s, 'SplitSpace',
            {'dir': AxisDir.V, 'pos': 6000, 'x': 3000, 'y': 5000}) as Applied)
        .newState;
    final legacy = deriveFloorBase(doc(s), s.floors.first.id)
        .wallSegments
        .firstWhere((w) => w.axis.kind != 'boundary');
    s = (edit(s, 'SetWallOverride',
            {'anchor': legacy.ref.anchor, 'type': 'open'}) as Applied)
        .newState;
    final names = s.floors.first.rooms.map((r) => r.id).toSet();
    expect(names.length, 2);
    s = add(s, 2000, 3000, 4000, 3000);
    expect(s.floors.first.rooms.map((r) => r.id).toSet(), names);
    expect(s.floors.first.wallOverrides.whereType<OpenWall>().length, 1);
    s = add(s, 6000, 2000, 6000, 4000);
    expect(s.floors.first.rooms.map((r) => r.id).toSet(), names);
    expect(s.floors.first.wallOverrides.whereType<OpenWall>().length, 2);
    expect(validateDesignState(s), isEmpty);
    expect(loadHouse(utf8.encode(encodeHouse(doc(s)))).document, doc(s));
  });
  test(
      'short unfinished wall persists, renders in both views and keeps one room',
      () {
    final before = initial(), s = add(before, 2000, 3000, 6000, 3000);
    expect(before.floors.first.explicitWalls, false);
    expect(s.floors.first.explicitWalls, true);
    expect(s.floors.first.rooms.length, 1);
    expect(s.floors.first.rooms.single.id, before.floors.first.rooms.single.id);
    expect(doc(s).schemaVersion, 2);
    expect(validateDesignState(s), isEmpty);
    final loaded = loadHouse(utf8.encode(encodeHouse(doc(s))));
    expect(loaded.document, doc(s));
    expect(
        deriveFloorBase(doc(s), s.floors.first.id)
            .wallSegments
            .any((w) => w.axis.pos == 3000),
        true);
    final drawn = deriveFloorBase(doc(s), s.floors.first.id)
        .wallSegments
        .singleWhere((w) => w.axis.pos == 3000);
    final mesh = deriveHouse(doc(s))
        .scene3d
        .where(
            (e) => e.kind == 'WallPiece' && e.source == WallSource(drawn.ref))
        .toList();
    expect(mesh, isNotEmpty);
    expect(
        mesh
            .expand((e) => e.vertices)
            .map((v) => v.x)
            .reduce((a, b) => a < b ? a : b),
        2000);
    expect(
        mesh
            .expand((e) => e.vertices)
            .map((v) => v.x)
            .reduce((a, b) => a > b ? a : b),
        6000);
  });
  test('closed chain creates an enclosed room only after the final segment',
      () {
    var s = add(initial(), 2000, 2000, 6000, 2000);
    s = add(s, 6000, 2000, 6000, 6000);
    s = add(s, 6000, 6000, 2000, 6000);
    expect(s.floors.first.rooms.length, 1);
    s = add(s, 2000, 6000, 2000, 2000);
    expect(s.floors.first.rooms.length, 2);
    expect(validateDesignState(s), isEmpty);
    final wall = s.floors.first.wallOverrides.whereType<SolidWall>().last;
    final result = edit(s, 'DeleteDrawnWall', {'wallId': wall.id}) as Applied;
    expect(result.newState.floors.first.rooms.length, 1);
  });
  test('wall reaching opposite exterior boundaries splits the room', () {
    final s = add(initial(), 6000, 0, 6000, 10000);
    expect(s.floors.first.rooms.length, 2);
    expect(s.floors.first.rooms.map((r) => r.id).toSet().length, 2);
  });
  test('reject diagonal, too short, duplicate, and outside walls atomically',
      () {
    final s = add(initial(), 2000, 3000, 6000, 3000);
    for (final a in [
      {'x0': 2000, 'y0': 3000, 'x1': 6000, 'y1': 3000},
      {'x0': 2000, 'y0': 3000, 'x1': 6000, 'y1': 4000},
      {'x0': 2000, 'y0': 3000, 'x1': 2100, 'y1': 3000},
      {'x0': 2000, 'y0': 3000, 'x1': 14000, 'y1': 3000}
    ]) expect(edit(s, 'AddDrawnWall', a), isA<Rejected>());
    expect(s.floors.first.wallOverrides.length, 1);
  });
  test('independent wall moves 100mm without the legacy 300mm axis restriction',
      () {
    var s = add(initial(), 2000, 3000, 6000, 3000);
    final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'UpdateDrawnWall', {
      'wallId': wall.id,
      'x0': 2000,
      'y0': 3100,
      'x1': 6000,
      'y1': 3100
    }) as Applied)
        .newState;
    final axes = resolveFloorAxes(doc(s), s.floors.first.id)!;
    expect(
        resolveAnchor(axes, s.floors.first.wallOverrides.single.anchor)
            .chain!
            .carrier
            .pos,
        3100);
    expect(validateDesignState(s), isEmpty);
  });
  test(
      'hosted door follows moved wall; shortening and unconfirmed deletion reject',
      () {
    var s = add(initial(), 2000, 3000, 6000, 3000);
    final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'AddOpening', {
      'anchor': wall.anchor,
      'kind': OpeningKind.door,
      'centerAtTap': true,
      'tapT': 2000.0
    }) as Applied)
        .newState;
    final oid = s.floors.first.openings.single.id;
    s = (edit(s, 'UpdateDrawnWall', {
      'wallId': wall.id,
      'x0': 2000,
      'y0': 3500,
      'x1': 6000,
      'y1': 3500
    }) as Applied)
        .newState;
    final placement = deriveHouse(doc(s)).floors.first.openings.single;
    expect(placement.status, 'ok');
    expect(placement.axis.pos, 3500);
    expect(s.floors.first.openings.single.id, oid);
    expect(
        edit(s, 'UpdateDrawnWall', {
          'wallId': wall.id,
          'x0': 2000,
          'y0': 3500,
          'x1': 3000,
          'y1': 3500
        }),
        isA<Rejected>());
    expect(edit(s, 'DeleteDrawnWall', {'wallId': wall.id}), isA<Rejected>());
    final deleted = (edit(s, 'DeleteDrawnWall',
            {'wallId': wall.id, 'deleteHostedObjects': true}) as Applied)
        .newState;
    expect(deleted.floors.first.openings, isEmpty);
    expect(deleted.floors.first.wallOverrides, isEmpty);
    expect(deleted.floors.first.explicitWalls, true);
  });
  test('new branches cannot cross an existing door opening', () {
    var s = add(initial(), 2000, 3000, 6000, 3000);
    final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'AddOpening', {
      'anchor': wall.anchor,
      'kind': OpeningKind.door,
      'tapT': 4000,
      'centerAtTap': true
    }) as Applied)
        .newState;
    final opening = deriveHouse(doc(s)).floors.first.openings.single;
    expect(opening.status, 'ok');
    final x = ((opening.start + opening.end) / 2).round();
    expect(edit(s, 'AddDrawnWall', {'x0': x, 'y0': 3000, 'x1': x, 'y1': 6000}),
        isA<Rejected>());
    expect(s.floors.first.wallOverrides.whereType<SolidWall>().length, 1);
  });
  test('room tools preserve unfinished walls and merge only actual boundaries',
      () {
    var s = add(initial(), 2000, 2000, 4000, 2000);
    final freeId =
        s.floors.first.wallOverrides.whereType<SolidWall>().single.id;
    s = (edit(s, 'CarveRoom', {
      'left': 0,
      'bottom': 0,
      'right': 3000,
      'top': 4000,
      'roomType': RoomType.bathroom
    }) as Applied)
        .newState;
    expect(s.floors.first.rooms.length, 2);
    expect(s.floors.first.wallOverrides.any((w) => w.id == freeId), true);
    expect(
        deriveFloorBase(doc(s), s.floors.first.id)
            .wallSegments
            .any((w) => w.axis.dir == AxisDir.V && w.axis.pos == 3000),
        true);
    final a = s.floors.first.rooms[0].id, b = s.floors.first.rooms[1].id;
    s = (edit(s, 'MergeRooms', {'roomIdA': a, 'roomIdB': b}) as Applied)
        .newState;
    expect(s.floors.first.rooms.length, 1);
    expect(
        s.floors.first.wallOverrides.whereType<SolidWall>().single.id, freeId);
  });
  test(
      'moving a dividing wall retains both named room identities across large changes',
      () {
    var s = add(initial(), 4000, 0, 4000, 10000);
    final left = s.floors.first.rooms
        .firstWhere((r) => r.regions.any((r) => r.x0 == '@left'))
        .id;
    final right = s.floors.first.rooms.firstWhere((r) => r.id != left).id;
    s = (edit(s, 'SetRoomType', {'roomId': left, 'value': RoomType.living})
            as Applied)
        .newState;
    s = (edit(s, 'SetRoomType', {'roomId': right, 'value': RoomType.bedroom})
            as Applied)
        .newState;
    final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'UpdateDrawnWall', {
      'wallId': wall.id,
      'x0': 9000,
      'y0': 0,
      'x1': 9000,
      'y1': 10000
    }) as Applied)
        .newState;
    expect(
        s.floors.first.rooms
            .firstWhere((r) => r.regions.any((r) => r.x0 == '@left'))
            .id,
        left);
    expect(s.floors.first.rooms.firstWhere((r) => r.id == right).type,
        RoomType.bedroom);
  });
  test('unchanged wall update keeps the original state without migration', () {
    final s = initial();
    final split = (edit(s, 'SplitSpace',
            {'dir': AxisDir.V, 'pos': 6000, 'x': 3000, 'y': 5000}) as Applied)
        .newState;
    final wall = deriveFloorBase(doc(split), split.floors.first.id)
        .wallSegments
        .firstWhere((w) => w.axis.kind != 'boundary');
    final r = edit(split, 'UpdateDrawnWall', {
      'anchor': wall.ref.anchor,
      'x0': 6000,
      'y0': 0,
      'x1': 6000,
      'y1': 10000
    });
    expect(r, isA<Applied>());
    expect((r as Applied).newState, split);
    expect(r.newState.floors.first.explicitWalls, false);
  });
  test('repeated movement prunes obsolete local coordinates', () {
    var s = add(initial(), 2000, 3000, 6000, 3000);
    final wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    for (var i = 1; i <= 20; i++) {
      s = (edit(s, 'UpdateDrawnWall', {
        'wallId': wall.id,
        'x0': 2000,
        'y0': 3000 + i * 50,
        'x1': 6000,
        'y1': 3000 + i * 50
      }) as Applied)
          .newState;
    }
    expect(s.axes.floor.length, 3);
    expect(validateDesignState(s), isEmpty);
  });
  test('copying an explicit floor remaps wall identities and anchors', () {
    final s = add(initial(), 2000, 3000, 6000, 3000);
    final copied = (edit(s, 'CopyFloor', {}) as Applied).newState;
    expect(copied.floors.length, 2);
    expect(copied.floors.last.explicitWalls, true);
    expect(copied.floors.first.wallOverrides.single.id,
        isNot(copied.floors.last.wallOverrides.single.id));
    final result = loadHouse(utf8.encode(encodeHouse(doc(copied))));
    expect(result.document, doc(copied));
    expect(
        deriveHouse(doc(copied))
            .floors
            .last
            .base
            .wallSegments
            .any((w) => w.axis.pos == 3000),
        true);
  });
  test('wall thickness, default and opening retain explicit layout semantics',
      () {
    var s = add(initial(), 6000, 0, 6000, 10000);
    var wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'SetWallOverride', {
      'anchor': wall.anchor,
      'type': 'thickness',
      'value': 180
    }) as Applied)
        .newState;
    expect(
        s.floors.first.wallOverrides.whereType<SolidWall>().single.value, 180);
    wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'SetWallOverride', {'anchor': wall.anchor, 'type': 'default'})
            as Applied)
        .newState;
    expect(s.floors.first.wallOverrides.whereType<SolidWall>().single.value,
        s.defaults.innerWallThickness);
    wall = s.floors.first.wallOverrides.whereType<SolidWall>().single;
    s = (edit(s, 'SetWallOverride', {'anchor': wall.anchor, 'type': 'open'})
            as Applied)
        .newState;
    expect(s.floors.first.rooms.length, 1);
    expect(validateDesignState(s), isEmpty);
  });
  test('a new wall cannot cross a staircase and other floors stay unchanged',
      () {
    var s = (edit(initial(), 'AddFloor', {}) as Applied).newState;
    s = (edit(s, 'CarveRoom', {
      'left': 2000,
      'bottom': 0,
      'right': 4000,
      'top': 4000,
      'roomType': RoomType.custom
    }) as Applied)
        .newState;
    final d = doc(s), axes = resolveFloorAxes(d, s.floors.first.id)!;
    String id(AxisDir dir, int pos) =>
        axes.all.firstWhere((a) => a.dir == dir && a.pos == pos).id;
    s = (edit(s, 'AddStair', {
      'type': StairType.straight,
      'region': AxisRectangle(
          x0: id(AxisDir.V, 2000),
          x1: id(AxisDir.V, 4000),
          y0: '@bottom',
          y1: id(AxisDir.H, 4000))
    }) as Applied)
        .newState;
    expect(
        edit(s, 'AddDrawnWall',
            {'x0': 1000, 'y0': 2000, 'x1': 5000, 'y1': 2000}),
        isA<Rejected>());
    final other = s.floors.last;
    final changed = add(s, 8000, 2000, 10000, 2000);
    expect(changed.floors.last, other);
    expect(validateDesignState(changed), isEmpty);
  });
  test(
      'version 1 cannot disguise explicit walls and future versions are rejected',
      () {
    final s = add(initial(), 2000, 3000, 6000, 3000);
    final raw = jsonDecode(encodeHouse(doc(s))) as Map<String, dynamic>;
    raw['schemaVersion'] = 1;
    expect(loadHouse(utf8.encode(jsonEncode(raw))).isSuccess, false);
    raw['schemaVersion'] = 3;
    expect(loadHouse(utf8.encode(jsonEncode(raw))).failure!.errors.single.code,
        'UNSUPPORTED_NEWER_VERSION');
  });
}
