// A room's area measured three ways: between the finished wall faces, to
// the middle of the walls, and to the outer face of outside walls.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/session/engine_session.dart';

void main() {
  var ids = 0;
  final ctx = CommandContext(
      newId: () => 'ar_${ids++}', now: () => '2026-11-23T00:00:00Z');
  UndoableDesignState initial() => extractDesignState(createHouse(
      name: '面积',
      width: 12000,
      depth: 10000,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: ctx.now(),
      newId: ctx.newId));
  HouseDocument doc(UndoableDesignState s) => composeDocument(
      Meta(name: '面积', createdAt: ctx.now(), updatedAt: ctx.now()), s);
  UndoableDesignState ok(CommandResult r) {
    expect(r, isA<Applied>(), reason: r is Rejected ? r.message : null);
    return (r as Applied).newState;
  }

  test('one room in the whole house', () {
    final d = doc(initial());
    final t = d.defaults.outerWallThickness;
    final g = deriveHouse(d).floors.first.base.roomGeometry.single;
    expect(g.clearArea, (12000.0 - 2 * t) * (10000 - 2 * t));
    expect(g.centreArea, (12000.0 - t) * (10000 - t));
    expect(g.nominalArea, 12000.0 * 10000);
    expect(g.area(AreaBasis.clear), g.clearArea);
    expect(g.area(AreaBasis.centre), g.centreArea);
    expect(g.area(AreaBasis.outer), g.nominalArea);
  });

  test('two rooms share the wall between them at its middle', () {
    final s0 = initial();
    final s = ok(executeCommand(
        s0,
        DesignCommand('AddDrawnWall', {
          'floorId': s0.floors.first.id,
          'x0': 6000,
          'y0': 0,
          'x1': 6000,
          'y1': 10000
        }),
        ctx));
    final d = doc(s);
    final t = d.defaults.outerWallThickness;
    final rooms = deriveHouse(d).floors.first.base.roomGeometry;
    expect(rooms, hasLength(2));
    for (final g in rooms) {
      expect(g.centreArea, (6000.0 - t / 2) * (10000 - t));
      expect(g.nominalArea, 6000.0 * 10000);
      expect(g.clearArea, lessThan(g.centreArea));
    }
    // Centre-line areas and the outer halves of the outside walls make
    // up the footprint exactly.
    final centre = rooms.fold(0.0, (a, g) => a + g.centreArea);
    expect(centre, (12000.0 - t) * (10000 - t));
  });

  test('the project remembers which way to show, and saves it', () {
    var s = initial();
    expect(s.extras.areaBasis, AreaBasis.clear);
    expect(encodeHouse(doc(s)).contains('areaBasis'), isFalse);
    s = ok(executeCommand(
        s, DesignCommand('SetAreaBasis', {'basis': AreaBasis.centre}), ctx));
    expect(s.extras.areaBasis, AreaBasis.centre);
    final text = encodeHouse(doc(s));
    expect(text, contains('"areaBasis": "centre"'));
    final back = loadHouse(utf8.encode(text));
    expect(back.failure, isNull, reason: '${back.failure?.errors}');
    expect(back.document!.extras.areaBasis, AreaBasis.centre);
    expect(
        executeCommand(s, DesignCommand('SetAreaBasis', {'basis': 'x'}), ctx),
        isA<Rejected>());
  });

  test('describe gives all three figures', () {
    final session = EngineSession(doc(initial()));
    final room =
        ((session.describe()['floors']! as List).first as Map)['rooms'] as List;
    final r = room.single as Map;
    expect(r['areaToOuterFace'], 120.0);
    expect((r['areaToWallCentres'] as num) < 120, isTrue);
    expect((r['area'] as num) < (r['areaToWallCentres'] as num), isTrue);
  });
}
