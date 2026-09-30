import '../document/house_document.dart';
import '../axis/axis_resolver.dart';
import '../geometry/floor_base.dart';
import 'room_commands.dart';
import 'design_commands.dart';

const houseTemplates = {
  'blank': '空白设计',
  'three': '一层三间 · 12 × 10 米',
  'five': '一层五间 · 15 × 10 米',
  'two': '两层住宅 · 12 × 10 米',
};

HouseDocument createTemplate(
    String kind, String timestamp, String Function() newId) {
  var doc = createHouse(
      name: houseTemplates[kind]!.split(' · ').first,
      width: kind == 'five' ? 15000 : 12000,
      depth: 10000,
      columns: 3,
      rows: kind == 'three' ? 1 : 2,
      timestamp: timestamp,
      newId: newId);
  if (kind == 'blank') return doc;
  final floor = doc.floors.first.id;
  if (kind == 'three') {
    for (var i = 0; i < 3; i++) {
      doc = paintCells(doc, floor, [Cell(i, 0)],
          [RoomType.bedroom, RoomType.living, RoomType.bedroom][i], newId);
    }
  } else {
    doc = paintCells(doc, floor, [const Cell(0, 0), const Cell(1, 0)],
        RoomType.living, newId);
    for (final entry in {
      const Cell(2, 0): RoomType.kitchen,
      const Cell(0, 1): RoomType.bedroom,
      const Cell(1, 1): RoomType.bedroom,
      const Cell(2, 1): RoomType.bathroom,
    }.entries) {
      doc = paintCells(doc, floor, [entry.key], entry.value, newId);
    }
  }
  if (kind == 'two') {
    doc = executeDocumentCommand(doc, 'CopyFloor', {'floorId': floor}, newId)
        .document!;
    final axes = resolveFloorAxes(doc, floor)!;
    doc = executeDocumentCommand(
            doc,
            'AddStair',
            {
              'floorId': floor,
              'type': StairType.L,
              'region': AxisRectangle(
                  x0: axes.v[2].id, x1: '@right', y0: axes.h[1].id, y1: '@top')
            },
            newId)
        .document!;
  }
  for (final f in doc.floors) {
    final base = deriveFloorBase(doc, f.id);
    for (final room in f.rooms) {
      final exterior = base.edges
          .where((e) =>
              e.kind == 'exterior' &&
              (base.owners[e.negative] == room.id ||
                  base.owners[e.positive] == room.id))
          .firstOrNull;
      if (exterior == null) continue;
      final anchor = BoundaryAnchor(
          axisId: exterior.axis.id,
          startAxisId: exterior.start.id,
          endAxisId: exterior.end.id);
      doc = executeDocumentCommand(
              doc,
              'AddOpening',
              {
                'floorId': f.id,
                'anchor': anchor,
                'tapT': 0,
                'kind': OpeningKind.door
              },
              newId)
          .document!;
      final doorId =
          doc.floors.firstWhere((v) => v.id == f.id).openings.last.id;
      if (room.type == RoomType.living && f.id == floor) {
        doc = executeDocumentCommand(
                doc, 'SetMainEntrance', {'openingId': doorId}, newId)
            .document!;
      }
      final length = exterior.end.pos - exterior.start.pos;
      doc = executeDocumentCommand(
              doc,
              'AddOpening',
              {
                'floorId': f.id,
                'anchor': anchor,
                'tapT': length / 2,
                'kind': OpeningKind.window
              },
              newId)
          .document!;
      final windowId =
          doc.floors.firstWhere((v) => v.id == f.id).openings.last.id;
      doc = executeDocumentCommand(
              doc,
              'MoveOpening',
              {
                'openingId': windowId,
                'position': {'type': 'fromEnd', 'd': 200}
              },
              newId)
          .document!;
    }
  }
  return doc;
}
