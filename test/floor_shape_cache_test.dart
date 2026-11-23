import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/design_commands.dart';
import 'package:yusal/features/editor/engine/core/commands/house_templates.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/perf/engine_perf.dart';

import 'document_edits_test.dart' show commandsFor;
import 'perf/engine_bench.dart';

/// Everything in a floor's geometry, as text, so two can be compared.
String describe(FloorBase b) {
  String cell(Cell? c) => c == null ? '-' : '${c.i},${c.j}';
  String rect(PlanRect r) => '${r.left},${r.bottom},${r.right},${r.top}';
  String space(SpaceGeometry g) => '${g.id} ${g.nominalArea} ${g.clearArea} '
      '${g.minClearSpan} ${g.labelAnchor} ${g.clearRects.map(rect).join(';')} '
      '${g.cells.map(cell).join(';')} ${g.collapsedCells.map(cell).join(';')}';
  return [
    'axes v ${b.axes.v.map((a) => '${a.id}@${a.pos}').join(' ')}',
    'axes h ${b.axes.h.map((a) => '${a.id}@${a.pos}').join(' ')}',
    'owners ${b.owners.entries.map((e) => '${cell(e.key)}=${e.value}').join(' ')}',
    for (final e in b.edges)
      [
        'edge',
        e.axis.id,
        e.start.id,
        e.end.id,
        cell(e.negative),
        cell(e.positive),
        e.kind,
        e.thickness
      ].join(' '),
    for (final w in b.wallSegments)
      [
        'wall',
        w.ref.floorId,
        w.ref.carrierId,
        w.ref.startAxisId,
        w.ref.endAxisId,
        w.kind,
        w.thickness,
        w.edges.length
      ].join(' '),
    'rects ${b.wallRects.map(rect).join(' ')}',
    for (final g in b.roomGeometry) 'room ${space(g)}',
    for (final g in b.stairGeometryBase) 'stair ${space(g)}',
    'free ${b.unassignedCells.map(cell).join(' ')} ${b.unassignedNominalArea}',
    'outside ${b.outside.map(cell).join(' ')}',
  ].join('\n');
}

void main() {
  var n = 0;
  String id() => 'id${n++}';
  final houses = <String, HouseDocument>{
    'kz': createKazakhTemplate('2026-10-14T00:00:00Z', id),
    'five': createTemplate('five', '2026-10-14T00:00:00Z', id),
    'typical': composeDocument(benchMeta, typicalPlan()),
    'large': composeDocument(benchMeta, largePlan()),
  };

  for (final house in houses.entries) {
    test('${house.key}: geometry found again equals geometry derived afresh',
        () {
      final doc = house.value;
      var checked = 0;
      for (final (kind, args) in commandsFor(doc)) {
        final result = executeDocumentCommand(doc, kind, args, id);
        if (!result.accepted) continue;
        final next = result.document!;
        // With what the original and earlier results left behind.
        for (final f in doc.floors) {
          deriveFloorBase(doc, f.id);
        }
        final found = [
          for (final f in next.floors) describe(deriveFloorBase(next, f.id))
        ];
        clearDerived();
        final fresh = [
          for (final f in next.floors) describe(deriveFloorBase(next, f.id))
        ];
        expect(found, fresh, reason: '$kind $args');
        checked++;
      }
      expect(checked, greaterThan(20));
    });
  }

  test('an edit that leaves the shape of a floor alone derives nothing', () {
    final doc = houses['typical']!;
    final floor = doc.floors.first;
    final opening = floor.openings.first;
    clearDerived();
    final before = [for (final f in doc.floors) deriveFloorBase(doc, f.id)];
    EnginePerf.enabled = true;
    EnginePerf.instance.reset();
    addTearDown(() {
      EnginePerf.enabled = perfBuild;
      EnginePerf.instance.reset();
    });
    for (final (kind, args) in <(String, Map<String, dynamic>)>[
      ('RenameRoom', {'roomId': floor.rooms.first.id, 'value': 'Study'}),
      ('SetFloorHeight', {'floorId': floor.id, 'value': floor.height + 100}),
      ('ResizeOpening', {'openingId': opening.id, 'width': opening.width - 50}),
      (
        'MoveOpening',
        {
          'openingId': opening.id,
          'position': {'type': 'fromStart', 'd': 120}
        }
      ),
      ('DeleteOpening', {'openingId': opening.id}),
    ]) {
      final next = executeDocumentCommand(doc, kind, args, id).document!;
      for (var i = 0; i < next.floors.length; i++) {
        expect(identical(deriveFloorBase(next, next.floors[i].id), before[i]),
            isTrue,
            reason: kind);
      }
    }
    expect(EnginePerf.instance.timing('derive.floorBase'), isNull);
  });

  test('moving an axis or resizing the house derives the floors again', () {
    final doc = houses['typical']!;
    final floor = doc.floors.first;
    final before = deriveFloorBase(doc, floor.id);
    final wider = executeDocumentCommand(
            doc, 'SetFootprintSize', {'width': doc.footprint.width + 500}, id)
        .document!;
    final after = deriveFloorBase(wider, floor.id);
    expect(identical(after, before), isFalse);
    expect(after.axes.v.last.pos, doc.footprint.width + 500);

    final axis = doc.axes.global.first;
    final moved = executeDocumentCommand(
            doc, 'MoveAxis', {'axisId': axis.id, 'pos': axis.pos + 100}, id)
        .document!;
    final shifted = deriveFloorBase(moved, floor.id);
    expect(identical(shifted, before), isFalse);
    expect(describe(shifted), isNot(describe(before)));
  });

  test('a document read from a file finds the geometry of its equal', () {
    final doc = houses['typical']!;
    clearDerived();
    final before = deriveFloorBase(doc, doc.floors.first.id);
    final again = loadHouse(utf8.encode(encodeHouse(doc))).document!;
    expect(identical(again.floors.first, doc.floors.first), isFalse);
    expect(identical(deriveFloorBase(again, again.floors.first.id), before),
        isTrue);
  });

  test('a change to a default wall thickness is not answered from before', () {
    final doc = houses['typical']!;
    final before = deriveFloorBase(doc, doc.floors.first.id);
    final thicker = executeDocumentCommand(
            doc,
            'SetDefault',
            {
              'field': 'innerWallThickness',
              'value': doc.defaults.innerWallThickness + 40
            },
            id)
        .document!;
    final after = deriveFloorBase(thicker, doc.floors.first.id);
    expect(identical(after, before), isFalse);
    expect(describe(after), isNot(describe(before)));
  });
}
