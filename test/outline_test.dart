import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/analysis/cost_estimate.dart';
import 'package:yusal/core/analysis/heat_loss.dart';
import 'package:yusal/core/analysis/house_analysis.dart';
import 'package:yusal/core/checks/check_engine.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/core/house_core.dart';
import 'package:yusal/render3d/scene_model.dart';

void main() {
  var n = 0;
  String next() => 'ol${n++}';
  const stamp = '2026-10-19T00:00:00Z';
  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(extractDesignState(doc),
        DesignCommand(kind, args), CommandContext(newId: next, now: () => stamp));
    expect(result, isA<Applied>(),
        reason: result is Rejected ? result.message : kind);
    return composeDocument(doc.meta, (result as Applied).newState);
  }

  HouseDocument box({int floors = 1}) {
    var doc = createHouse(
        name: 'L',
        width: 10000,
        depth: 8000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: stamp,
        newId: next);
    for (var i = 1; i < floors; i++)
      doc = run(doc, 'AddFloor', {'floorId': doc.floors.last.id});
    return doc;
  }

  String? reject(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(extractDesignState(doc),
        DesignCommand(kind, args), CommandContext(newId: next, now: () => stamp));
    return result is Rejected ? result.message : null;
  }

  HouseDocument roundTrip(HouseDocument doc) {
    expect(validateHouse(doc), isEmpty);
    final loaded = loadHouse(utf8.encode(encodeHouse(doc)));
    expect(loaded.isSuccess, true,
        reason: loaded.failure?.errors.map((e) => '${e.path} ${e.message}').join('; '));
    expect(loaded.document, doc);
    return loaded.document!;
  }

  test('cutting a corner makes an L-shaped house with walls along the cut', () {
    var doc = run(box(), 'CutOutline',
        {'corner': 'tr', 'width': 4000, 'depth': 3000});
    expect(doc.schemaVersion, 4);
    roundTrip(doc);
    final base = deriveHouse(doc).floors.first.base;
    expect(footprintArea(base), 10000 * 8000 - 4000 * 3000);
    // An L has the same perimeter as its bounding rectangle.
    expect(outlineLength(base), 2 * (10000 + 8000));
    expect(base.unassignedCells, isEmpty);
    final room = base.roomGeometry.single;
    expect(room.nominalArea, 68e6);
    // Outside walls along both cut lines, on the building's side.
    final cutWalls = [
      for (var k = 0; k < base.wallSegments.length; k++)
        if (base.wallSegments[k].kind == 'exterior' &&
            base.wallSegments[k].axis.kind != 'boundary')
          (base.wallSegments[k], base.wallRects[k])
    ];
    expect(cutWalls, hasLength(2));
    for (final (seg, rect) in cutWalls) {
      if (seg.axis.dir == AxisDir.V) {
        expect(seg.axis.pos, 6000);
        expect((rect.left, rect.right), (5760.0, 6000.0));
      } else {
        expect(seg.axis.pos, 5000);
        expect((rect.bottom, rect.top), (4760.0, 5000.0));
      }
    }
    // No wall along the cut-away part of the top and right edges.
    expect(
        base.wallSegments.where((s) =>
            s.axis.id == '@top' && s.kind == 'exterior' && s.end.pos > 6000),
        isEmpty);
    expect(runChecks(doc, deriveHouse(doc)).where((r) => r.ruleId == 'R09'),
        isEmpty);
  });

  test('quantities, heat, cost and 3D follow the outline', () {
    final full = box();
    final cut = run(full, 'CutOutline', {'corner': 'bl', 'width': 3000, 'depth': 4000});
    final df = deriveHouse(full), dc = deriveHouse(cut);
    expect(wallTakeoff(cut, dc).exteriorGross,
        closeTo(wallTakeoff(full, df).exteriorGross, 1));
    expect(estimateCost(cut, dc).buildingArea, 68);
    expect(heatLoss(cut, dc).floorArea, closeTo(68, 1e-9));
    expect(heatLoss(cut, dc).total, lessThan(heatLoss(full, df).total));
    // Ground slab pieces stay inside the L.
    for (final e in dc.scene3d.where((e) => e.kind == 'Slab')) {
      final xs = e.vertices.map((v) => v.x), ys = e.vertices.map((v) => v.y);
      final cx = (xs.reduce((a, b) => a < b ? a : b) + xs.reduce((a, b) => a > b ? a : b)) / 2,
          cy = (ys.reduce((a, b) => a < b ? a : b) + ys.reduce((a, b) => a > b ? a : b)) / 2;
      expect(cx < 3000 && cy < 4000, false, reason: 'slab at $cx, $cy');
    }
    final flat = run(cut, 'SetRoof', {
      'roof': {'type': 'flat', 'parapetHeight': 900}
    });
    final parapets = deriveHouse(flat).scene3d.where((e) => e.kind == 'Parapet');
    expect(parapets, hasLength(6));
    expect(() => buildScene(flat, deriveHouse(flat), const SceneOptions(),
        (r) => r.name), returnsNormally);
    expect(foundationTakeoff(cut, dc).mainLength, closeTo(36000 - 4 * 240, 2000));
  });

  test('windows can go on the new outside wall and face outdoors', () {
    var doc = run(box(), 'CutOutline', {'corner': 'tr', 'width': 4000, 'depth': 3000});
    final base = deriveHouse(doc).floors.first.base;
    final wall = base.wallSegments.firstWhere(
        (s) => s.kind == 'exterior' && s.axis.dir == AxisDir.H && s.axis.kind != 'boundary');
    doc = run(doc, 'AddOpening', {
      'floorId': doc.floors.first.id,
      'kind': OpeningKind.window,
      'anchor': wall.ref.anchor,
      'tapT': 2000,
      'centerAtTap': true,
    });
    final p = deriveHouse(doc).floors.first.openings.single;
    expect(p.status, 'ok');
    expect(p.host!.kind, 'exterior');
    expect(facingOf(p, deriveHouse(doc).floors.first.base, 0), Facing.north);
    expect(heatLoss(doc, deriveHouse(doc)).windowArea, closeTo(2.25, 1e-9));
  });

  test('cuts that would strand doors, windows or stairs are refused', () {
    var doc = box();
    doc = run(doc, 'AddOpening', {
      'floorId': doc.floors.first.id,
      'kind': OpeningKind.window,
      'anchor': const BoundaryAnchor(
          axisId: '@top', startAxisId: '@left', endAxisId: '@right'),
      'tapT': 8500,
      'centerAtTap': true,
    });
    expect(reject(doc, 'CutOutline', {'corner': 'tr', 'width': 4000, 'depth': 3000}),
        contains('门窗'));
    // The other corner is fine.
    run(doc, 'CutOutline', {'corner': 'bl', 'width': 4000, 'depth': 3000});
    expect(reject(doc, 'CutOutline', {'corner': 'tr', 'width': 9000, 'depth': 3000}),
        isNotNull);
    expect(reject(doc, 'CutOutline', {'corner': 'xx', 'width': 2000, 'depth': 2000}),
        isNotNull);
  });

  test('rooms cannot be drawn in the cut-out and its edge cannot be deleted', () {
    final doc = run(box(), 'CutOutline', {'corner': 'tr', 'width': 4000, 'depth': 3000});
    final floorId = doc.floors.first.id;
    expect(
        reject(doc, 'CarveRoom', {
          'floorId': floorId,
          'left': 7000,
          'bottom': 6000,
          'right': 9000,
          'top': 7500,
          'roomType': RoomType.bedroom
        }),
        isNotNull);
    final edge = doc.axes.floor.firstWhere((a) => a.pos == 6000);
    expect(reject(doc, 'DeleteAxis', {'axisId': edge.id}), contains('缺角'));
  });

  test('painting and splitting stay out of the cut-out', () {
    var doc = run(box(), 'CutOutline', {'corner': 'tr', 'width': 4000, 'depth': 3000});
    final floorId = doc.floors.first.id;
    final base = deriveHouse(doc).floors.first.base;
    expect(
        reject(doc, 'PaintCells', {
          'floorId': floorId,
          'cells': [base.outside.first],
          'roomType': RoomType.kitchen
        }),
        contains('缺角'));
    // Free the left part, then split that undivided space next to the cut.
    doc = run(doc, 'EraseCells', {
      'floorId': floorId,
      'cells': base.roomGeometry.single.cells.toList()
    });
    expect(doc.floors.first.rooms, isEmpty);
    doc = run(doc, 'SplitSpace', {
      'floorId': floorId,
      'dir': AxisDir.V,
      'pos': 3000,
      'x': 1000,
      'y': 1000
    });
    final after = deriveHouse(doc).floors.first.base;
    expect(after.roomGeometry, hasLength(2));
    for (final r in after.roomGeometry)
      expect(r.cells.any(after.outside.contains), false);
  });

  test('one floor only gives a terrace; restoring brings the rectangle back', () {
    var doc = box(floors: 2);
    final upper = doc.floors.last.id;
    doc = run(doc, 'CutOutline',
        {'corner': 'br', 'width': 4000, 'depth': 3000, 'floorIds': [upper]});
    final d = deriveHouse(doc);
    expect(d.floors.first.base.outside, isEmpty);
    expect(d.floors.last.base.outside, isNotEmpty);
    // The ground floor keeps its full roof slab under the terrace.
    expect(footprintArea(d.floors.first.base), 80e6);
    roundTrip(doc);
    doc = run(doc, 'RestoreOutline', {'floorIds': [upper]});
    expect(doc.floors.last.outside, isEmpty);
    expect(doc.schemaVersion, lessThan(4));
    expect(deriveHouse(doc).floors.last.base.unassignedCells, isNotEmpty);
    expect(reject(doc, 'RestoreOutline', {}), isNotNull);
  });

  test('independent walls keep working beside a cut-out', () {
    var doc = run(box(), 'CutOutline', {'corner': 'tr', 'width': 4000, 'depth': 3000});
    final floorId = doc.floors.first.id;
    doc = run(doc, 'AddDrawnWall',
        {'floorId': floorId, 'x0': 3000, 'y0': 0, 'x1': 3000, 'y1': 8000});
    final base = deriveHouse(doc).floors.first.base;
    expect(base.roomGeometry, hasLength(2));
    for (final r in base.roomGeometry)
      expect(r.cells.any(base.outside.contains), false);
    roundTrip(doc);
  });

  test('a hip roof does not stop independent walls', () {
    var doc = run(box(), 'SetRoof', {
      'roof': {'type': 'hip', 'pitchDeg': 30, 'overhang': 500}
    });
    doc = run(doc, 'AddDrawnWall', {
      'floorId': doc.floors.first.id,
      'x0': 4000,
      'y0': 0,
      'x1': 4000,
      'y1': 8000
    });
    expect(doc.schemaVersion, 4);
    roundTrip(doc);
  });

  test('the village template takes an L cut and still checks out', () {
    final doc = createKazakhTemplate(stamp, next);
    final result = executeCommand(
        extractDesignState(doc),
        DesignCommand('CutOutline', {'corner': 'tl', 'width': 2000, 'depth': 2000}),
        CommandContext(newId: next, now: () => stamp));
    // Windows sit on that corner of the template: the cut is refused, the
    // design stays as it was.
    expect(result, isA<Rejected>());
  });
}
