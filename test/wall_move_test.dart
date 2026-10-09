import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/geometry/opening_constraints.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'move_test_${ids++}', now: () => '2026-10-08T00:00:00Z');
  UndoableDesignState initial() => extractDesignState(createHouse(
      name: '移墙',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: ctx.newId));
  HouseDocument doc(UndoableDesignState s) => composeDocument(
      Meta(name: '移墙', createdAt: ctx.now(), updatedAt: ctx.now()), s);
  CommandResult edit(
          UndoableDesignState s, String kind, Map<String, dynamic> args) =>
      executeCommand(
          s, DesignCommand(kind, {'floorId': s.floors.first.id, ...args}), ctx);
  UndoableDesignState ok(CommandResult r) {
    expect(r, isA<Applied>(), reason: r is Rejected ? r.message : null);
    return (r as Applied).newState;
  }

  UndoableDesignState add(
          UndoableDesignState s, int x0, int y0, int x1, int y1) =>
      ok(edit(s, 'AddDrawnWall', {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1}));
  ({int carrier, int lo, int hi}) span(SolidWall w, UndoableDesignState s) {
    final c = resolveAnchor(
            resolveFloorAxes(doc(s), s.floors.first.id)!, w.anchor)
        .chain!;
    return (carrier: c.carrier.pos, lo: c.startPos, hi: c.endPos);
  }

  SolidWall wallAt(UndoableDesignState s, AxisDir dir, int carrier) =>
      s.floors.first.wallOverrides.whereType<SolidWall>().singleWhere((w) {
        final c = resolveAnchor(
                resolveFloorAxes(doc(s), s.floors.first.id)!, w.anchor)
            .chain!;
        return c.carrier.dir == dir && c.carrier.pos == carrier;
      });

  // A full-height partition at x=6 m with one wall ending on each side.
  UndoableDesignState layout() {
    var s = initial();
    s = add(s, 6000, 0, 6000, 10000);
    s = add(s, 6000, 5000, 12000, 5000);
    s = add(s, 0, 3000, 6000, 3000);
    var n = 0;
    for (final room in s.floors.first.rooms)
      s = ok(executeCommand(
          s,
          DesignCommand('RenameRoom', {'roomId': room.id, 'value': '房${n++}'}),
          ctx));
    return s;
  }

  test('moving a partition keeps walls that end on it attached', () {
    final before = layout();
    expect(before.floors.first.rooms.length, 4);
    final names = {for (final r in before.floors.first.rooms) r.id: r.name};
    final partition = wallAt(before, AxisDir.V, 6000);
    final after = ok(edit(before, 'MoveDrawnWall',
        {'wallId': partition.id, 'pos': 7000}));
    expect(span(wallAt(after, AxisDir.V, 7000), after),
        (carrier: 7000, lo: 0, hi: 10000));
    expect(span(wallAt(after, AxisDir.H, 5000), after),
        (carrier: 5000, lo: 7000, hi: 12000));
    expect(span(wallAt(after, AxisDir.H, 3000), after),
        (carrier: 3000, lo: 0, hi: 7000));
    expect({for (final r in after.floors.first.rooms) r.id: r.name}, names,
        reason: 'room identities survive one atomic move');
    expect(validateDesignState(after), isEmpty);
    expect(loadHouse(utf8.encode(encodeHouse(doc(after)))).document,
        doc(after));
    // Moving back the other way shrinks the left wall and grows the right one.
    final back =
        ok(edit(after, 'MoveDrawnWall', {'wallId': partition.id, 'pos': 5000}));
    expect(span(wallAt(back, AxisDir.H, 5000), back).lo, 5000);
    expect(span(wallAt(back, AxisDir.H, 3000), back).hi, 5000);
    expect({for (final r in back.floors.first.rooms) r.id: r.name}, names);
  });

  test('a move that would crush an attached wall is refused with a reason', () {
    final s = layout();
    final r = edit(s, 'MoveDrawnWall',
        {'wallId': wallAt(s, AxisDir.V, 6000).id, 'pos': 11800});
    expect(r, isA<Rejected>());
    expect((r as Rejected).message, contains('0.30'));
  });

  test('doors on an attached wall keep their place while it stretches', () {
    var s = layout();
    final base = deriveFloorBase(doc(s), s.floors.first.id);
    final branch = base.wallSegments.singleWhere((w) =>
        w.axis.dir == AxisDir.H && w.axis.pos == 5000 && w.start.pos == 6000);
    s = ok(edit(s, 'AddOpening', {
      'anchor': branch.ref.anchor,
      'kind': OpeningKind.door,
      'centerAtTap': true,
      'tapT': 3500
    }));
    double doorStart(UndoableDesignState s) =>
        documentOpenings(doc(s)).single.start;
    final start = doorStart(s);
    s = ok(edit(s, 'MoveDrawnWall',
        {'wallId': wallAt(s, AxisDir.V, 6000).id, 'pos': 6500}));
    expect(doorStart(s), start);
    expect(documentOpenings(doc(s)).single.status, 'ok');
  });

  test('an L corner follows but a through wall at the end stays put', () {
    var s = initial();
    // L corner: horizontal 0–6 m at y=4 m meets vertical y=4–10 m at x=6 m.
    s = add(s, 0, 4000, 6000, 4000);
    s = add(s, 6000, 4000, 6000, 10000);
    s = ok(edit(s, 'MoveDrawnWall',
        {'wallId': wallAt(s, AxisDir.V, 6000).id, 'pos': 7000}));
    expect(span(wallAt(s, AxisDir.H, 4000), s),
        (carrier: 4000, lo: 0, hi: 7000));
    // Through wall: continue the horizontal line to the right edge first.
    var t = initial();
    t = add(t, 0, 4000, 6000, 4000);
    t = add(t, 6000, 4000, 12000, 4000);
    t = add(t, 6000, 4000, 6000, 10000);
    t = ok(edit(t, 'MoveDrawnWall',
        {'wallId': wallAt(t, AxisDir.V, 6000).id, 'pos': 7000}));
    final pieces = t.floors.first.wallOverrides
        .whereType<SolidWall>()
        .map((w) => span(w, t))
        .where((c) => c.carrier == 4000)
        .toSet();
    expect(pieces, {
      (carrier: 4000, lo: 0, hi: 6000),
      (carrier: 4000, lo: 6000, hi: 12000)
    });
  });

  test('walls that cross the moved wall are not dragged along', () {
    var s = initial();
    s = add(s, 6000, 0, 6000, 10000);
    s = add(s, 3000, 5000, 9000, 5000);
    final crossing = wallAt(s, AxisDir.H, 5000);
    s = ok(edit(s, 'MoveDrawnWall',
        {'wallId': wallAt(s, AxisDir.V, 6000).id, 'pos': 7000}));
    expect(span(wallAt(s, AxisDir.H, 5000), s),
        (carrier: 5000, lo: 3000, hi: 9000));
    expect(wallAt(s, AxisDir.H, 5000).id, crossing.id);
  });

  test('an old v1 file can move a room-derived wall and stays readable', () {
    final v1 = loadHouse(
            File('test/fixtures/full_two_floor_gable.house').readAsBytesSync())
        .document!;
    expect(v1.schemaVersion, 1);
    final first = v1.floors.first, second = v1.floors[1];
    final base = deriveFloorBase(v1, first.id);
    final wall = base.wallSegments.firstWhere((w) =>
        w.axis.kind != 'boundary' &&
        !deriveOpenings(v1, base, first.id)
            .any((o) => o.host?.ref == w.ref));
    final names = {for (final r in first.rooms) r.id: r.name};
    final healthy = documentOpenings(v1)
        .where((o) => o.status == 'ok')
        .map((o) => o.opening.id)
        .toSet();
    final r = executeCommand(
        extractDesignState(v1),
        DesignCommand('MoveDrawnWall', {
          'floorId': first.id,
          'anchor': wall.ref.anchor,
          'pos': wall.axis.pos + 500
        }),
        ctx);
    final s = ok(r);
    final moved = composeDocument(v1.meta, s);
    expect(moved.schemaVersion, 2);
    expect(s.floors.first.explicitWalls, isTrue);
    expect(s.floors[1], second, reason: 'other floor untouched');
    expect({for (final r in s.floors.first.rooms) r.id: r.name}, names);
    for (final o in documentOpenings(moved))
      if (healthy.contains(o.opening.id)) expect(o.status, 'ok');
    expect(validateHouse(moved), isEmpty);
    expect(loadHouse(utf8.encode(encodeHouse(moved))).document, moved);
  });
}
