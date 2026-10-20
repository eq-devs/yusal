import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';
import '../geometry/opening_constraints.dart';
import '../validation/document_validator.dart';
import 'design_commands.dart';

/// Non-rectangular outlines: a corner of the footprint rectangle cut away
/// on some floors (an L-shaped house, or a terrace on the floor below).
/// The cut lines become local axes; rooms lose the cut cells; doors and
/// windows that would hang in the air are not moved but refused.

/// Corners: tl, tr, bl, br (top = the far side of the plan).
const outlineCorners = ['tl', 'tr', 'bl', 'br'];

/// Smallest piece of house kept beside a cut, mm.
const outlineMinKeep = 1500;

EditResult cutCorner(HouseDocument doc, List<String> floorIds, String corner,
    int width, int depth, String Function() newId) {
  final w = doc.footprint.width, d = doc.footprint.depth;
  if (!outlineCorners.contains(corner) || floorIds.isEmpty)
    return const EditResult(null, '操作参数无效');
  if (width < 600 ||
      depth < 600 ||
      width > w - outlineMinKeep ||
      depth > d - outlineMinKeep)
    return const EditResult(null, '缺角长宽至少 0.60 米，并给房子留出至少 1.50 米');
  if (floorIds.any((id) => !doc.floors.any((f) => f.id == id)))
    return const EditResult(null, '找不到要编辑的对象');
  try {
    return _cut(doc, floorIds, corner, width, depth, newId);
  } on FormatException catch (error) {
    return EditResult(null, error.message);
  }
}

EditResult _cut(HouseDocument doc, List<String> floorIds, String corner,
    int width, int depth, String Function() newId) {
  final w = doc.footprint.width, d = doc.footprint.depth;
  final right = corner.endsWith('r'), top = corner.startsWith('t');
  final cutX = right ? w - width : width, cutY = top ? d - depth : depth;
  var axes = doc.axes;
  final floors = <Floor>[];
  for (final floor in doc.floors) {
    if (!floorIds.contains(floor.id)) {
      floors.add(floor);
      continue;
    }
    final resolved = resolveFloorAxes(doc, floor.id)!;
    final additions = <FloorAxis>[];
    String line(AxisDir dir, int pos) {
      for (final a in dir == AxisDir.V ? resolved.v : resolved.h) {
        if (a.pos == pos) return a.id;
        if ((a.pos - pos).abs() < 300)
          throw const FormatException('缺角的边与已有墙线过近，请对齐或留出至少 0.30 米');
      }
      final id = newId();
      additions.add(FloorAxis(id: id, floorId: floor.id, dir: dir, pos: pos));
      return id;
    }

    final x = line(AxisDir.V, cutX), y = line(AxisDir.H, cutY);
    final rect = AxisRectangle(
        x0: right ? x : '@left',
        x1: right ? '@right' : x,
        y0: top ? y : '@bottom',
        y1: top ? '@top' : y);
    axes = AxisSystem(global: axes.global, floor: [...axes.floor, ...additions]);
    floors.add(Floor(
        explicitWalls: floor.explicitWalls,
        id: floor.id,
        name: floor.name,
        height: floor.height,
        rooms: floor.rooms,
        wallOverrides: floor.wallOverrides,
        openings: floor.openings,
        stairs: floor.stairs,
        outside: [...floor.outside, rect]));
  }
  HouseDocument rebuild(List<Floor> list) => HouseDocument(
      schemaVersion: 4,
      meta: doc.meta,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: axes,
      floors: list,
      roof: doc.roof);
  final staged = rebuild(floors);
  // Trim the rooms: cut cells leave, what remains splits into pieces.
  final trimmed = <Floor>[];
  for (final floor in staged.floors) {
    if (!floorIds.contains(floor.id)) {
      trimmed.add(floor);
      continue;
    }
    final grid = resolveFloorAxes(staged, floor.id)!;
    final cut = <Cell>{
      for (final r in floor.outside) ...cellsOfRect(resolveRect(grid, r).rect!)
    };
    for (final stair in floor.stairs)
      if (cellsOfRect(resolveRect(grid, stair.region).rect!).any(cut.contains))
        return const EditResult(null, '缺角处有楼梯，请先移动楼梯');
    final rooms = <Room>[];
    for (final room in floor.rooms) {
      final cells = regionCells(grid, room.regions).cells.toSet()
        ..removeAll(cut);
      final parts = components(grid, cells).cells;
      for (var i = 0; i < parts.length; i++)
        rooms.add(Room(
            id: i == 0 ? room.id : newId(),
            type: room.type,
            name: room.name,
            regions: canonicalizeCells(grid, parts[i]).regions));
    }
    trimmed.add(Floor(
        explicitWalls: floor.explicitWalls,
        id: floor.id,
        name: floor.name,
        height: floor.height,
        rooms: rooms,
        wallOverrides: floor.wallOverrides,
        openings: floor.openings,
        stairs: floor.stairs,
        outside: floor.outside));
  }
  final result = rebuild(trimmed);
  final healthy = documentOpenings(doc)
      .where((p) => p.status == 'ok')
      .map((p) => p.opening.id)
      .toSet();
  final broken = documentOpenings(result)
      .where((p) => healthy.contains(p.opening.id) && p.status != 'ok')
      .length;
  if (broken > 0)
    return EditResult(null, '缺角处有 $broken 个门窗，请先移走或删除');
  final errors = validateHouse(result);
  if (errors.isNotEmpty) return EditResult(null, errors.first.message);
  return EditResult(result, null);
}

/// The full rectangle back on [floorIds]; the cells that come back are
/// left undivided so the user decides which room they join.
EditResult restoreOutline(HouseDocument doc, List<String> floorIds) {
  if (!doc.floors.any((f) => floorIds.contains(f.id) && f.outside.isNotEmpty))
    return const EditResult(null, '这层已经是完整的矩形');
  final result = HouseDocument(
      schemaVersion: 4,
      meta: doc.meta,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: doc.axes,
      floors: [
        for (final f in doc.floors)
          floorIds.contains(f.id)
              ? Floor(
                  explicitWalls: f.explicitWalls,
                  id: f.id,
                  name: f.name,
                  height: f.height,
                  rooms: f.rooms,
                  wallOverrides: f.wallOverrides,
                  openings: f.openings,
                  stairs: f.stairs)
              : f
      ],
      roof: doc.roof);
  final errors = validateHouse(result);
  if (errors.isNotEmpty) return EditResult(null, errors.first.message);
  return EditResult(result, null);
}
