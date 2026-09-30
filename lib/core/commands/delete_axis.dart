import '../document/house_document.dart';
import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../validation/document_validator.dart';

class AxisDeletion {
  const AxisDeletion(this.document, this.message,
      {this.needsResolution = false,
      this.hasStairs = false,
      this.hasHosted = false});
  final HouseDocument? document;
  final String? message;
  final bool needsResolution, hasStairs, hasHosted;
}

AxisDeletion deleteAxis(HouseDocument doc, String id, String Function() newId,
    {String? resolution,
    bool deleteHostedObjects = false,
    bool deleteStairs = false}) {
  if (id.startsWith('@')) return const AxisDeletion(null, '外轮廓边界不能删除');
  final affected = <String, ResolvedAxes>{};
  for (final floor in doc.floors) {
    final axes = resolveFloorAxes(doc, floor.id)!;
    if (lookupAxis(axes, id).axis != null) affected[floor.id] = axes;
  }
  if (affected.isEmpty) return const AxisDeletion(null, '没有找到这条分隔线');
  final roomCells = <String, Set<Cell>>{},
      ownerMaps = <String, Map<Cell, String?>>{};
  final stairIds = {
    for (final f in doc.floors)
      for (final s in f.stairs) s.id
  };
  final removeStairs = <String>{};
  var conflict = false, hosted = false;
  for (final floor in doc.floors.where((f) => affected.containsKey(f.id))) {
    final axes = affected[floor.id]!, a = lookupAxis(axes, id).axis!;
    final owners = <Cell, String?>{};
    for (final r in floor.rooms) {
      final cells = regionCells(axes, r.regions).cells;
      roomCells[r.id] = cells;
      for (final c in cells) owners[c] = r.id;
    }
    for (final s in floor.stairs)
      for (final c in cellsOfRect(resolveRect(axes, s.region).rect!))
        owners[c] = s.id;
    ownerMaps[floor.id] = owners;
    final count = a.dir == AxisDir.V ? axes.ny : axes.nx;
    for (var n = 0; n < count; n++) {
      final low =
              a.dir == AxisDir.V ? Cell(a.index - 1, n) : Cell(n, a.index - 1),
          high = a.dir == AxisDir.V ? Cell(a.index, n) : Cell(n, a.index);
      final l = owners[low], h = owners[high];
      if (l != h) {
        conflict = true;
        if (stairIds.contains(l)) removeStairs.add(l!);
        if (stairIds.contains(h)) removeStairs.add(h!);
      }
    }
    if (floor.openings.any((o) => o.anchor.axisId == id) ||
        floor.wallOverrides.any((w) => w.anchor.axisId == id)) hosted = true;
  }
  if ((conflict && resolution == null) ||
      (hosted && !deleteHostedObjects) ||
      (removeStairs.isNotEmpty && !deleteStairs))
    return AxisDeletion(null, '删除分隔线将合并相邻格子，并影响房间、楼梯或门窗。',
        needsResolution: true,
        hasStairs: removeStairs.isNotEmpty,
        hasHosted: hosted);
  if (resolution != null &&
      !['mergeRooms', 'keepLowSide', 'keepHighSide'].contains(resolution))
    return const AxisDeletion(null, '冲突处理选项无效');
  final axesSystem = AxisSystem(
      global: doc.axes.global.where((a) => a.id != id).toList(),
      floor: doc.axes.floor.where((a) => a.id != id).toList());
  final provisional = HouseDocument(
      schemaVersion: doc.schemaVersion,
      meta: doc.meta,
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: axesSystem,
      floors: doc.floors,
      roof: doc.roof);
  final floors = <Floor>[];
  final deletedOpenings = <String>{};
  for (final floor in doc.floors) {
    final oldAxes = affected[floor.id];
    if (oldAxes == null) {
      floors.add(floor);
      continue;
    }
    final a = lookupAxis(oldAxes, id).axis!,
        line = a.dir == AxisDir.V ? oldAxes.v : oldAxes.h,
        lowId = line[a.index - 1].id,
        highId = line[a.index + 1].id;
    final axes = resolveFloorAxes(provisional, floor.id)!;
    AxisRectangle rect(AxisRectangle r) => AxisRectangle(
        x0: r.x0 == id ? lowId : r.x0,
        x1: r.x1 == id ? highId : r.x1,
        y0: r.y0 == id ? lowId : r.y0,
        y1: r.y1 == id ? highId : r.y1);
    BoundaryAnchor anchor(BoundaryAnchor b) => BoundaryAnchor(
        axisId: b.axisId,
        startAxisId: b.startAxisId == id ? lowId : b.startAxisId,
        endAxisId: b.endAxisId == id ? highId : b.endAxisId);
    final oldOwners = ownerMaps[floor.id]!;
    final representatives = <String, String>{
      for (final r in floor.rooms) r.id: r.id
    };
    String root(String id) {
      var value = id;
      while (representatives[value] != value) value = representatives[value]!;
      return value;
    }

    if (resolution == 'mergeRooms') {
      final count = a.dir == AxisDir.V ? oldAxes.ny : oldAxes.nx;
      for (var n = 0; n < count; n++) {
        final l = oldOwners[a.dir == AxisDir.V
                ? Cell(a.index - 1, n)
                : Cell(n, a.index - 1)],
            h = oldOwners[
                a.dir == AxisDir.V ? Cell(a.index, n) : Cell(n, a.index)];
        if (l == null ||
            h == null ||
            !representatives.containsKey(l) ||
            !representatives.containsKey(h)) continue;
        final rl = root(l), rh = root(h);
        if (rl == rh) continue;
        final keep =
            compareComponentPriority(oldAxes, roomCells[rl]!, roomCells[rh]!) <=
                    0
                ? rl
                : rh;
        representatives[keep == rl ? rh : rl] = keep;
      }
    }
    final newOwner = <Cell, String?>{};
    for (var j = 0; j < axes.ny; j++)
      for (var i = 0; i < axes.nx; i++) {
        final collapsed =
            a.dir == AxisDir.V ? i == a.index - 1 : j == a.index - 1;
        Cell oldCell(bool high) => a.dir == AxisDir.V
            ? Cell(
                i +
                    (i >= a.index
                        ? 1
                        : collapsed && high
                            ? 1
                            : 0),
                j)
            : Cell(
                i,
                j +
                    (j >= a.index
                        ? 1
                        : collapsed && high
                            ? 1
                            : 0));
        String? clean(String? value) => removeStairs.contains(value)
            ? null
            : value != null && representatives.containsKey(value)
                ? root(value)
                : value;
        final low = clean(oldOwners[oldCell(false)]),
            high = clean(oldOwners[oldCell(true)]);
        newOwner[Cell(i, j)] = !collapsed
            ? low
            : resolution == 'keepHighSide'
                ? high
                : resolution == 'mergeRooms'
                    ? (low ?? high)
                    : low;
      }
    final rooms = <Room>[];
    for (final room in floor.rooms) {
      if (root(room.id) != room.id) continue;
      final cells = newOwner.entries
          .where((e) => e.value == room.id)
          .map((e) => e.key)
          .toSet();
      final parts = components(axes, cells).cells;
      for (var k = 0; k < parts.length; k++)
        rooms.add(Room(
            id: k == 0 ? room.id : newId(),
            type: room.type,
            name: room.name,
            regions: canonicalizeCells(axes, parts[k]).regions));
    }
    final openings = <Opening>[];
    for (final o in floor.openings) {
      if (o.anchor.axisId == id) {
        deletedOpenings.add(o.id);
        continue;
      }
      final b = anchor(o.anchor);
      openings.add(switch (o) {
        DoorOpening() => DoorOpening(
            id: o.id,
            anchor: b,
            position: o.position,
            width: o.width,
            height: o.height,
            sill: o.sill,
            hinge: o.hinge,
            opensTo: o.opensTo),
        WindowOpening() => WindowOpening(
            id: o.id,
            anchor: b,
            position: o.position,
            width: o.width,
            height: o.height,
            sill: o.sill),
        SlidingOpening() => SlidingOpening(
            id: o.id,
            anchor: b,
            position: o.position,
            width: o.width,
            height: o.height,
            sill: o.sill)
      });
    }
    final overrides = <WallOverride>[];
    for (final w in floor.wallOverrides) {
      if (w.anchor.axisId == id) continue;
      overrides.add(switch (w) {
        OpenWall() => OpenWall(id: w.id, anchor: anchor(w.anchor)),
        ThicknessWall() =>
          ThicknessWall(id: w.id, anchor: anchor(w.anchor), value: w.value)
      });
    }
    final stairs = <Stair>[];
    for (final stair in floor.stairs) {
      if (removeStairs.contains(stair.id)) continue;
      stairs.add(switch (stair) {
        StraightStair() => StraightStair(
            id: stair.id,
            region: rect(stair.region),
            startEdge: stair.startEdge),
        TurnStair() => TurnStair(
            id: stair.id,
            region: rect(stair.region),
            startEdge: stair.startEdge,
            turn: stair.turn,
            type: stair.type)
      });
    }
    floors.add(Floor(
        id: floor.id,
        name: floor.name,
        height: floor.height,
        rooms: rooms,
        wallOverrides: overrides,
        openings: openings,
        stairs: stairs));
  }
  final result = HouseDocument(
      schemaVersion: doc.schemaVersion,
      meta: doc.meta,
      mainEntranceOpeningId: deletedOpenings.contains(doc.mainEntranceOpeningId)
          ? null
          : doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: axesSystem,
      floors: floors,
      roof: doc.roof);
  final errors = validateHouse(result);
  if (errors.isNotEmpty)
    return AxisDeletion(null, '删除后有冲突：${errors.first.message}');
  return AxisDeletion(result, null);
}
