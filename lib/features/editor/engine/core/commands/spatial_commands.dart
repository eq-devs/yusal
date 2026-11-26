import 'package:yusal/features/editor/engine/core/axis/axis_resolver.dart';
import 'package:yusal/features/editor/engine/core/canonicalization/room_canonicalizer.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/geometry/opening_constraints.dart';
import 'package:yusal/features/editor/engine/core/validation/document_validator.dart';
import 'package:yusal/features/editor/engine/core/commands/design_commands.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';

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
        stairs: original.stairs,
        outside: original.outside);
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
      ...cellsOfRect(resolveRect(axes, stair.region).rect!),
    // Cut-out corners are outdoors, not undivided space.
    for (final r in floor.outside) ...cellsOfRect(resolveRect(axes, r).rect!)
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
  if (lower.isEmpty || upper.isEmpty) {
    return const EditResult(null, '分隔线需要穿过这个空间');
  }
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
      stairs: floor.stairs,
      outside: floor.outside);
  final result = HouseDocument(
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

HouseDocument _with(HouseDocument doc,
        {AxisSystem? axes, List<Floor>? floors}) =>
    HouseDocument(
        meta: doc.meta,
        mainEntranceOpeningId: doc.mainEntranceOpeningId,
        defaults: doc.defaults,
        footprint: doc.footprint,
        axes: axes ?? doc.axes,
        floors: floors ?? doc.floors,
        roof: doc.roof);

/// Takes a stair out and gives its place back to the room it stood in, so
/// no walled-off hole is left behind. Axes only the stair used go with it.
EditResult removeStair(
    HouseDocument doc, String stairId, String Function() newId) {
  final floor =
      doc.floors.where((f) => f.stairs.any((s) => s.id == stairId)).firstOrNull;
  if (floor == null) return const EditResult(null, '找不到这部楼梯');
  final stair = floor.stairs.firstWhere((s) => s.id == stairId);
  final axes = resolveFloorAxes(doc, floor.id)!;
  final rect = resolveRect(axes, stair.region).rect!;
  final cells = cellsOfRect(rect).toSet();
  final roomOf = <Cell, String>{
    for (final room in floor.rooms)
      for (final c in regionCells(axes, room.regions).cells) c: room.id
  };
  // The room that shares the most of the stair's edge takes the space.
  final shared = <String, int>{};
  Cell? hostCell;
  for (final c in cells) {
    for (final n in [
      Cell(c.i - 1, c.j),
      Cell(c.i + 1, c.j),
      Cell(c.i, c.j - 1),
      Cell(c.i, c.j + 1)
    ]) {
      final room = roomOf[n];
      if (room != null) shared[room] = (shared[room] ?? 0) + 1;
    }
  }
  if (shared.isNotEmpty) {
    final host =
        (shared.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
    hostCell = roomOf.entries.firstWhere((e) => e.value == host).key;
  }
  final removed =
      executeDocumentCommand(doc, 'DeleteStair', {'stairId': stairId}, newId);
  if (!removed.accepted) return removed;
  var next = removed.document!;
  // Openings in the walls around the stair were made for it.
  bool around(WallOverride w) {
    if (w is! OpenWall) return false;
    final chain = resolveAnchor(axes, w.anchor).chain;
    if (chain == null) return false;
    final p = chain.carrier.pos;
    return chain.carrier.dir == AxisDir.V
        ? (p == rect.left || p == rect.right) &&
            chain.startPos >= rect.bottom &&
            chain.endPos <= rect.top
        : (p == rect.bottom || p == rect.top) &&
            chain.startPos >= rect.left &&
            chain.endPos <= rect.right;
  }

  Floor copy(Floor f, {List<WallOverride>? wallOverrides}) => Floor(
      explicitWalls: f.explicitWalls,
      id: f.id,
      name: f.name,
      height: f.height,
      rooms: f.rooms,
      wallOverrides: wallOverrides ?? f.wallOverrides,
      openings: f.openings,
      stairs: f.stairs,
      outside: f.outside);
  next = _with(next, floors: [
    for (final f in next.floors)
      f.id == floor.id
          ? copy(f, wallOverrides: [
              for (final w in f.wallOverrides)
                if (!around(w)) w
            ])
          : f
  ]);
  if (hostCell != null) {
    next = paintCells(
        next, floor.id, [hostCell, ...cells], RoomType.custom, newId);
  }
  final refs = <String>{};
  void use(AxisRectangle r) => refs.addAll([r.x0, r.x1, r.y0, r.y1]);
  for (final f in next.floors) {
    for (final r in f.rooms) {
      r.regions.forEach(use);
    }
    for (final s in f.stairs) {
      use(s.region);
    }
    for (final r in f.outside) {
      use(r);
    }
    for (final w in f.wallOverrides) {
      refs.addAll([w.anchor.axisId, w.anchor.startAxisId, w.anchor.endAxisId]);
    }
    for (final o in f.openings) {
      refs.addAll([o.anchor.axisId, o.anchor.startAxisId, o.anchor.endAxisId]);
    }
  }
  final own = {
    stair.region.x0,
    stair.region.x1,
    stair.region.y0,
    stair.region.y1
  };
  final pruned = _with(next,
      axes: AxisSystem(global: next.axes.global, floor: [
        for (final a in next.axes.floor)
          if (!own.contains(a.id) || refs.contains(a.id)) a
      ]));
  return EditResult(validateHouse(pruned).isEmpty ? pruned : next, null);
}

/// A stair as a thing put down in a room: a rectangle in millimetres, in
/// the first shape that fits it (straight, L, then U) unless [type] says
/// which. Its sides are open to the room. With [stairId] an existing stair
/// moves there instead and keeps its shape where that still fits.
EditResult placeStair(HouseDocument input, String floorId, int left, int bottom,
    int right, int top, String Function() newId,
    {StairType? type, String? stairId}) {
  var doc = input;
  final index = doc.floors.indexWhere((f) => f.id == floorId);
  if (index < 0) return const EditResult(null, '找不到这一层');
  if (index == doc.floors.length - 1) {
    return const EditResult(null, '楼梯需要上方还有楼层');
  }
  if (left < 0 ||
      bottom < 0 ||
      right > doc.footprint.width ||
      top > doc.footprint.depth ||
      right - left < 300 ||
      top - bottom < 300) {
    return const EditResult(null, '楼梯需在房屋内');
  }
  Stair? previous;
  if (stairId != null) {
    previous =
        doc.floors[index].stairs.where((s) => s.id == stairId).firstOrNull;
    if (previous == null) return const EditResult(null, '找不到这部楼梯');
    final lifted = removeStair(doc, stairId, newId);
    if (!lifted.accepted) return lifted;
    doc = lifted.document!;
  }
  final original = doc.floors[index];
  final oldAxes = resolveFloorAxes(doc, floorId)!;
  final additions = <FloorAxis>[];
  String boundary(AxisDir dir, int position) {
    for (final axis in dir == AxisDir.V ? oldAxes.v : oldAxes.h) {
      if (axis.pos == position) return axis.id;
      if ((axis.pos - position).abs() < 300) {
        throw const FormatException('离已有墙线太近，请贴齐或留出至少 0.30 米');
      }
    }
    final id = newId();
    additions.add(FloorAxis(id: id, floorId: floorId, dir: dir, pos: position));
    return id;
  }

  try {
    final region = AxisRectangle(
        x0: boundary(AxisDir.V, left),
        x1: boundary(AxisDir.V, right),
        y0: boundary(AxisDir.H, bottom),
        y1: boundary(AxisDir.H, top));
    final staged = _with(doc,
        axes: AxisSystem(
            global: doc.axes.global, floor: [...doc.axes.floor, ...additions]));
    final axes = resolveFloorAxes(staged, floorId)!;
    final cells = cellsOfRect(resolveRect(axes, region).rect!).toSet();
    final roomOf = <Cell, String>{
      for (final room in original.rooms)
        for (final c in regionCells(axes, room.regions).cells) c: room.id
    };
    final owners = {for (final c in cells) roomOf[c]};
    if (owners.length != 1 || owners.first == null) {
      return const EditResult(null, '楼梯要整个放在同一个房间里');
    }
    final host = owners.first!;
    if (original.stairs.any((s) =>
        cellsOfRect(resolveRect(axes, s.region).rect!).any(cells.contains))) {
      return const EditResult(null, '这里已经有楼梯了');
    }
    // The first step is on a side the room can be walked to from.
    bool reached(int di, int dj) => cells.any((c) =>
        roomOf[Cell(c.i + di, c.j + dj)] == host &&
        !cells.contains(Cell(c.i + di, c.j + dj)));
    final edge = previous?.startEdge ??
        (top - bottom >= right - left
            ? (reached(0, -1) || !reached(0, 1)
                ? StairEdge.bottom
                : StairEdge.top)
            : (reached(-1, 0) || !reached(1, 0)
                ? StairEdge.left
                : StairEdge.right));
    final shapes = type != null
        ? [type]
        : [
            if (previous != null) previous.type,
            for (final t in StairType.values)
              if (t != previous?.type) t
          ];
    ({double a, double b})? need;
    String? refusal;
    for (final shape in shapes) {
      final added = executeDocumentCommand(staged, 'AddStair',
          {'floorId': floorId, 'type': shape, 'region': region}, newId);
      if (!added.accepted) {
        refusal = added.error;
        break;
      }
      var next = added.document!;
      final id = next.floors[index].stairs
          .firstWhere((s) => original.stairs.every((o) => o.id != s.id))
          .id;
      final turn = previous is TurnStair ? previous.turn : null;
      if (edge != StairEdge.bottom || turn == StairTurn.right) {
        final turned = executeDocumentCommand(
            next,
            'UpdateStair',
            {
              'stairId': id,
              'startEdge': edge.name,
              if (shape != StairType.straight && turn != null) 'turn': turn.name
            },
            newId);
        if (turned.accepted) next = turned.document!;
      }
      // Open every side that faces the room the stair stands in.
      final hostCells = {
        for (final e in roomOf.entries)
          if (e.value == host && !cells.contains(e.key)) e.key
      };
      // Edges rather than walls: where walls are drawn by hand there is
      // none yet, and an opening keeps one from being built.
      final runs = <List<UnitEdge>>[];
      for (final e in deriveFloorBase(next, floorId).edges) {
        if (!((cells.contains(e.negative) && hostCells.contains(e.positive)) ||
            (cells.contains(e.positive) && hostCells.contains(e.negative)))) {
          continue;
        }
        final run = runs
            .where((r) =>
                r.last.axis.id == e.axis.id && r.last.end.id == e.start.id)
            .firstOrNull;
        run == null ? runs.add([e]) : run.add(e);
      }
      for (final run in runs) {
        final opened = executeDocumentCommand(
            next,
            'SetWallOverride',
            {
              'floorId': floorId,
              'anchor': BoundaryAnchor(
                  axisId: run.first.axis.id,
                  startAxisId: run.first.start.id,
                  endAxisId: run.last.end.id),
              'type': 'open'
            },
            newId);
        if (opened.accepted) next = opened.document!;
      }
      final errors = validateHouse(next);
      if (errors.isNotEmpty) {
        refusal = errors.first.message;
        break;
      }
      final geometry = deriveHouse(next)
          .floors[index]
          .stairs
          .firstWhere((s) => s.stairId == id);
      if (geometry.fits) return EditResult(next, null);
      if (need == null ||
          geometry.requiredA * geometry.requiredB < need.a * need.b) {
        need = (a: geometry.requiredA, b: geometry.requiredB);
      }
    }
    if (refusal != null) return EditResult(null, refusal);
    String m(double v) => (v / 1000).toStringAsFixed(1);
    return EditResult(null, '这里放不下楼梯，净空至少要 ${m(need!.a)} × ${m(need.b)} 米');
  } on FormatException catch (error) {
    return EditResult(null, error.message);
  }
}
