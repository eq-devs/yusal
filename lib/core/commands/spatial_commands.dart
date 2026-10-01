import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';
import '../geometry/opening_constraints.dart';
import '../validation/document_validator.dart';
import 'design_commands.dart';
import 'room_commands.dart';

/// A rectangle carves one space in a single transaction. New axes are local to
/// this floor; sharing a coordinate never creates a wall in unrelated rooms.
EditResult carveRoom(HouseDocument doc, String floorId, int left, int bottom,
    int right, int top, RoomType type, String Function() newId) {
  if (left < 0 ||
      bottom < 0 ||
      right > doc.footprint.width ||
      top > doc.footprint.depth ||
      right - left < 300 ||
      top - bottom < 300) {
    return const EditResult(null, '房间需在房屋内，长宽至少 0.30 米');
  }
  final original = doc.floors.firstWhere((f) => f.id == floorId);
  final oldAxes = resolveFloorAxes(doc, floorId)!;
  final additions = <FloorAxis>[];
  String boundary(AxisDir dir, int position) {
    final candidates = dir == AxisDir.V ? oldAxes.v : oldAxes.h;
    for (final axis in candidates) {
      if (axis.pos == position) return axis.id;
      if ((axis.pos - position).abs() < 300) {
        throw const FormatException('与已有墙线过近，请对齐或留出至少 0.30 米');
      }
    }
    final id = newId();
    additions.add(FloorAxis(id: id, floorId: floorId, dir: dir, pos: position));
    return id;
  }

  HouseDocument rebuild(AxisSystem axes, List<Floor> floors) => HouseDocument(
      schemaVersion: doc.schemaVersion,
      meta: doc.meta,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: axes,
      floors: floors,
      roof: doc.roof);
  try {
    final rect = AxisRectangle(
        x0: boundary(AxisDir.V, left),
        x1: boundary(AxisDir.V, right),
        y0: boundary(AxisDir.H, bottom),
        y1: boundary(AxisDir.H, top));
    final axisSystem = AxisSystem(
        global: doc.axes.global, floor: [...doc.axes.floor, ...additions]);
    final staged = rebuild(axisSystem, doc.floors);
    final axes = resolveFloorAxes(staged, floorId)!;
    final selected = cellsOfRect(resolveRect(axes, rect).rect!).toSet();
    final sets = {
      for (final room in original.rooms)
        room.id: regionCells(axes, room.regions).cells.toSet()
    };
    final owners = <String?>{};
    for (final cell in selected) {
      owners.add(original.rooms
          .where((r) => sets[r.id]!.contains(cell))
          .firstOrNull
          ?.id);
    }
    if (owners.length != 1) {
      return const EditResult(null, '请在同一个空间内划分房间');
    }
    final reserved = {
      for (final stair in original.stairs)
        ...cellsOfRect(resolveRect(axes, stair.region).rect!)
    };
    if (selected.any(reserved.contains)) {
      return const EditResult(null, '房间不能覆盖楼梯');
    }
    final rooms = <Room>[];
    for (final room in original.rooms) {
      final remaining = sets[room.id]!..removeAll(selected);
      final parts = components(axes, remaining).cells;
      for (var i = 0; i < parts.length; i++) {
        rooms.add(Room(
            id: i == 0 ? room.id : newId(),
            type: room.type,
            name: room.name,
            regions: canonicalizeCells(axes, parts[i]).regions));
      }
    }
    rooms.add(Room(
        id: newId(),
        type: type,
        name: roomNames[type]!,
        regions: canonicalizeCells(axes, selected).regions));
    final replacement = Floor(
        explicitWalls: original.explicitWalls,
        id: original.id,
        name: original.name,
        height: original.height,
        rooms: rooms,
        wallOverrides: original.wallOverrides,
        openings: original.openings,
        stairs: original.stairs);
    final result = rebuild(axisSystem, [
      for (final floor in doc.floors) floor.id == floorId ? replacement : floor
    ]);
    final errors = validateHouse(result);
    if (errors.isNotEmpty) {
      return EditResult(null, '此调整影响已有对象：${errors.first.message}');
    }
    final healthyOpenings = documentOpenings(doc)
        .where((p) => p.status == 'ok')
        .map((p) => p.opening.id)
        .toSet();
    if (documentOpenings(result).any(
        (p) => healthyOpenings.contains(p.opening.id) && p.status != 'ok')) {
      return const EditResult(null, '分房会影响已有门窗，请避开门窗位置');
    }
    return EditResult(result, null);
  } on FormatException catch (error) {
    return EditResult(null, error.message);
  }
}

/// Splits the connected space under the pointer. It does not split neighbours
/// that happen to share the same axis coordinate.
EditResult splitSpace(HouseDocument doc, String floorId, AxisDir dir, int pos,
    int x, int y, String Function() newId) {
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  final initialAxes = resolveFloorAxes(doc, floorId)!;
  final maximum = dir == AxisDir.V ? doc.footprint.width : doc.footprint.depth;
  if (pos < 300 ||
      pos > maximum - 300 ||
      x < 0 ||
      y < 0 ||
      x >= doc.footprint.width ||
      y >= doc.footprint.depth) {
    return const EditResult(null, '请在空间内部画分隔线');
  }
  final existing = (dir == AxisDir.V ? initialAxes.v : initialAxes.h)
      .where((a) => a.pos == pos)
      .firstOrNull;
  var staged = doc;
  if (existing == null) {
    final add = executeDocumentCommand(
        doc, 'AddAxis', {'floorId': floorId, 'dir': dir, 'pos': pos}, newId);
    if (!add.accepted) return add;
    staged = add.document!;
  }
  final axes = resolveFloorAxes(staged, floorId)!;
  final i = axes.v.indexWhere((a) => a.pos > x) - 1;
  final j = axes.h.indexWhere((a) => a.pos > y) - 1;
  final seed = Cell(i, j);
  final sets = {
    for (final room in floor.rooms)
      room.id: regionCells(axes, room.regions).cells.toSet()
  };
  final source =
      floor.rooms.where((r) => sets[r.id]!.contains(seed)).firstOrNull;
  final reserved = {
    for (final stair in floor.stairs)
      ...cellsOfRect(resolveRect(axes, stair.region).rect!)
  };
  final occupied = sets.values.expand((s) => s).toSet();
  final candidates = source == null
      ? <Cell>{
          for (var row = 0; row < axes.ny; row++)
            for (var column = 0; column < axes.nx; column++)
              if (!occupied.contains(Cell(column, row)) &&
                  !reserved.contains(Cell(column, row)))
                Cell(column, row)
        }
      : sets[source.id]!;
  final space = components(axes, candidates)
      .cells
      .where((part) => part.contains(seed))
      .firstOrNull;
  if (space == null) return const EditResult(null, '请避开楼梯');
  final lower = space
      .where((cell) =>
          (dir == AxisDir.V
              ? axes.v[cell.i + 1].pos
              : axes.h[cell.j + 1].pos) <=
          pos)
      .toSet();
  final upper = space.difference(lower);
  if (lower.isEmpty || upper.isEmpty)
    return const EditResult(null, '分隔线需要穿过这个空间');
  final rooms = [
    for (final room in floor.rooms)
      if (room.id != source?.id) room
  ];
  var retained = false;
  for (final half in [lower, upper]) {
    for (final part in components(axes, half).cells) {
      rooms.add(Room(
          id: source != null && !retained ? source.id : newId(),
          type: source?.type ?? RoomType.custom,
          name: source?.name ?? '房间',
          regions: canonicalizeCells(axes, part).regions));
      retained = true;
    }
  }
  final replacement = Floor(
      explicitWalls: floor.explicitWalls,
      id: floor.id,
      name: floor.name,
      height: floor.height,
      rooms: rooms,
      wallOverrides: floor.wallOverrides,
      openings: floor.openings,
      stairs: floor.stairs);
  final result = HouseDocument(
      schemaVersion: doc.schemaVersion,
      meta: doc.meta,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: staged.axes,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      roof: doc.roof,
      floors: [
        for (final item in doc.floors) item.id == floorId ? replacement : item
      ]);
  final errors = validateHouse(result);
  if (errors.isNotEmpty) return EditResult(null, errors.first.message);
  final healthy = documentOpenings(doc)
      .where((p) => p.status == 'ok')
      .map((p) => p.opening.id)
      .toSet();
  if (documentOpenings(result)
      .any((p) => healthy.contains(p.opening.id) && p.status != 'ok')) {
    return const EditResult(null, '分隔线影响已有门窗，请换一个位置');
  }
  return EditResult(result, null);
}
