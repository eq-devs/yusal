import 'dart:convert';
import 'dart:math' as math;
import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';
import '../geometry/floor_base.dart';
import '../geometry/opening_constraints.dart';
import '../serialization/house_codec.dart';
import '../validation/document_validator.dart';
import 'design_commands.dart';
import 'room_commands.dart';

HouseDocument _replaceFloor(HouseDocument doc, Floor floor,
        {AxisSystem? axes}) =>
    HouseDocument(
        schemaVersion: 2,
        meta: doc.meta,
        defaults: doc.defaults,
        footprint: doc.footprint,
        axes: axes ?? doc.axes,
        floors: [for (final f in doc.floors) f.id == floor.id ? floor : f],
        roof: doc.roof,
        mainEntranceOpeningId: doc.mainEntranceOpeningId);

/// Materialize the existing layout once. Legacy room boundaries, opening
/// anchors and physical coordinates remain unchanged during conversion.
HouseDocument enableWallDrawing(
    HouseDocument doc, String floorId, String Function() newId) {
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  if (floor.explicitWalls) return doc;
  final base = deriveFloorBase(doc, floorId);
  return _replaceFloor(
      doc,
      Floor(
          id: floor.id,
          name: floor.name,
          height: floor.height,
          explicitWalls: true,
          rooms: floor.rooms,
          openings: floor.openings,
          stairs: floor.stairs,
          wallOverrides: [
            for (final w in floor.wallOverrides)
              if (w is OpenWall ||
                  base.axes.all
                          .firstWhere((a) => a.id == w.anchor.axisId)
                          .kind ==
                      'boundary')
                w,
            for (final wall in base.wallSegments)
              if (wall.axis.kind != 'boundary')
                SolidWall(
                    id: newId(),
                    anchor: wall.ref.anchor,
                    value: wall.thickness.round())
          ]));
}

/// Flood-fill the planar cells through all edges without a physical wall.
/// Closed chains become spaces; unfinished short partitions do not create
/// spurious rooms. Largest surviving overlaps retain names, types and IDs.
HouseDocument recognizeWallRooms(
    HouseDocument doc, String floorId, String Function() newId,
    {Map<String, List<({double x, double y})>> preferred = const {},
    bool keepUnassigned = false,
    bool preserveOpenZones = true}) {
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  if (!floor.explicitWalls) return doc;
  final base = deriveFloorBase(doc, floorId), axes = base.axes;
  final stairs = floor.stairs.map((s) => s.id).toSet();
  if (axes.v.length > maxExplicitAxesPerDirection + 2 ||
      axes.h.length > maxExplicitAxesPerDirection + 2)
    throw const FormatException('墙体坐标过多，请整理布局后再继续');
  final remaining = <Cell>{
    for (var j = 0; j < axes.ny; j++)
      for (var i = 0; i < axes.nx; i++)
        if (!stairs.contains(base.owners[Cell(i, j)])) Cell(i, j)
  };
  final adjacency = <Cell, Set<Cell>>{};
  for (final e in base.edges) {
    if (e.hasWall || e.negative == null || e.positive == null) continue;
    // Legacy open-plan zones retain their distinct room metadata.
    if (preserveOpenZones &&
        e.kind == 'open' &&
        base.owners[e.negative] != null &&
        base.owners[e.positive] != null &&
        base.owners[e.negative] != base.owners[e.positive]) continue;
    (adjacency[e.negative!] ??= {}).add(e.positive!);
    (adjacency[e.positive!] ??= {}).add(e.negative!);
  }
  final groups = <Set<Cell>>[];
  while (remaining.isNotEmpty) {
    final pending = <Cell>[remaining.first], group = <Cell>{};
    remaining.remove(pending.first);
    while (pending.isNotEmpty) {
      final c = pending.removeLast();
      group.add(c);
      for (final n in adjacency[c] ?? <Cell>{})
        if (remaining.remove(n)) pending.add(n);
    }
    groups.add(group);
  }
  groups.sort((a, b) {
    double area(Set<Cell> cells) => cells.fold(
        0,
        (sum, c) =>
            sum +
            (axes.v[c.i + 1].pos - axes.v[c.i].pos) *
                (axes.h[c.j + 1].pos - axes.h[c.j].pos));
    return area(b).compareTo(area(a));
  });
  final used = <String>{}, rooms = <Room>[];
  for (final group in groups) {
    Room? prior;
    var best = 0.0;
    var bestSeeds = -1;
    for (final room in floor.rooms) {
      if (used.contains(room.id)) continue;
      final cells = regionCells(axes, room.regions).cells;
      var overlap = 0.0;
      for (final c in group.intersection(cells))
        overlap += (axes.v[c.i + 1].pos - axes.v[c.i].pos) *
            (axes.h[c.j + 1].pos - axes.h[c.j].pos);
      final seeds = (preferred[room.id] ?? []).where((p) {
        final i = axes.v.indexWhere((a) => a.pos > p.x) - 1,
            j = axes.h.indexWhere((a) => a.pos > p.y) - 1;
        return group.contains(Cell(i, j));
      }).length;
      if ((seeds > bestSeeds || seeds == bestSeeds && overlap > best) &&
          (seeds > 0 || overlap > 0)) {
        best = overlap;
        bestSeeds = seeds;
        prior = room;
      }
    }
    if (prior == null && keepUnassigned) continue;
    final id = prior?.id ?? newId();
    used.add(id);
    rooms.add(Room(
        id: id,
        name: prior?.name ?? roomNames[RoomType.custom]!,
        type: prior?.type ?? RoomType.custom,
        regions: canonicalizeCells(axes, group).regions));
  }
  return _replaceFloor(
      doc,
      Floor(
          id: floor.id,
          name: floor.name,
          height: floor.height,
          explicitWalls: true,
          rooms: rooms,
          wallOverrides: floor.wallOverrides,
          openings: floor.openings,
          stairs: floor.stairs));
}

/// Keep room-based tools usable after upgrading to physical wall segments.
/// Preserve unfinished partitions; materialize new boundaries and remove only
/// the boundaries that a room edit actually merged.
HouseDocument syncRoomWalls(HouseDocument before, HouseDocument after,
    String floorId, String Function() newId) {
  final floor = after.floors.firstWhere((f) => f.id == floorId);
  if (!floor.explicitWalls) return after;
  final old = deriveFloorBase(before, floorId),
      current = deriveFloorBase(after, floorId);
  final natural = _replaceFloor(
      after,
      Floor(
          id: floor.id,
          name: floor.name,
          height: floor.height,
          rooms: floor.rooms,
          wallOverrides: [
            for (final w in floor.wallOverrides)
              if (w is! SolidWall) w
          ],
          openings: floor.openings,
          stairs: floor.stairs));
  final wanted = deriveFloorBase(natural, floorId);
  String? oldOwner(Cell? c) {
    if (c == null) return null;
    final x = (current.axes.v[c.i].pos + current.axes.v[c.i + 1].pos) / 2;
    final y = (current.axes.h[c.j].pos + current.axes.h[c.j + 1].pos) / 2;
    final i = old.axes.v.indexWhere((a) => a.pos > x) - 1,
        j = old.axes.h.indexWhere((a) => a.pos > y) - 1;
    return old.owners[Cell(i, j)];
  }

  final edges = <UnitEdge>[];
  for (var i = 0; i < current.edges.length; i++) {
    final e = current.edges[i],
        n = current.owners[e.negative],
        p = current.owners[e.positive];
    if (e.axis.kind == 'boundary') continue;
    final wasBoundary = oldOwner(e.negative) != oldOwner(e.positive);
    if (e.hasWall && !(wasBoundary && n == p))
      edges.add(e);
    else if (wanted.edges[i].hasWall && n != p) edges.add(wanted.edges[i]);
  }
  final originals = floor.wallOverrides.whereType<SolidWall>().toList(),
      used = <String>{};
  final walls = <WallOverride>[
    for (final w in floor.wallOverrides)
      if (w is OpenWall ||
          (w is! SolidWall &&
              current.axes.all
                      .firstWhere((a) => a.id == w.anchor.axisId)
                      .kind ==
                  'boundary'))
        w
  ];
  var group = <UnitEdge>[];
  void flush() {
    if (group.isEmpty) return;
    final first = group.first, last = group.last;
    final prior = originals.where((w) {
      final c = resolveAnchor(current.axes, w.anchor).chain!;
      return c.carrier.id == first.axis.id &&
          c.startPos <= first.start.pos &&
          c.endPos >= last.end.pos &&
          !used.contains(w.id);
    }).firstOrNull;
    final id = prior?.id ?? newId();
    used.add(id);
    walls.add(SolidWall(
        id: id,
        anchor: BoundaryAnchor(
            axisId: first.axis.id,
            startAxisId: first.start.id,
            endAxisId: last.end.id),
        value: first.thickness.round()));
    group = [];
  }

  for (final e in edges) {
    String? originalId(UnitEdge edge) => originals
        .where((w) {
          final c = resolveAnchor(current.axes, w.anchor).chain!;
          return c.carrier.id == edge.axis.id &&
              c.startPos <= edge.start.pos &&
              c.endPos >= edge.end.pos;
        })
        .firstOrNull
        ?.id;
    if (group.isNotEmpty &&
        (group.last.axis.id != e.axis.id ||
            group.last.end.pos != e.start.pos ||
            group.last.thickness != e.thickness ||
            originalId(group.last) != originalId(e))) flush();
    group.add(e);
  }
  flush();
  return recognizeWallRooms(
      _replaceFloor(
          after,
          Floor(
              id: floor.id,
              name: floor.name,
              height: floor.height,
              explicitWalls: true,
              rooms: floor.rooms,
              wallOverrides: walls,
              openings: floor.openings,
              stairs: floor.stairs)),
      floorId,
      newId,
      keepUnassigned: true);
}

/// Insert or alter one physical wall as a single transaction. Endpoints share
/// existing axes when exact; new coordinates are local to this floor.
EditResult editDrawnWall(HouseDocument original, String kind,
    Map<String, dynamic> args, String Function() newId) {
  try {
    final floorId = args['floorId'] as String;
    var doc = enableWallDrawing(original, floorId, newId);
    final floor = doc.floors.firstWhere((f) => f.id == floorId);
    final oldAxes = resolveFloorAxes(doc, floorId)!;
    final walls = [...floor.wallOverrides];
    final wallId = args['wallId'] as String?;
    final targetAnchor = args['anchor'] as BoundaryAnchor?;
    final prior = walls
        .whereType<SolidWall>()
        .where((w) => wallId != null
            ? w.id == wallId
            : targetAnchor != null && w.anchor == targetAnchor)
        .firstOrNull;
    if (kind != 'AddDrawnWall' && prior == null)
      return const EditResult(null, '找不到这段墙，请重新选择');
    final oldChain =
        prior == null ? null : resolveAnchor(oldAxes, prior.anchor).chain!;
    if (kind == 'UpdateDrawnWall' && oldChain != null) {
      final x0 = args['x0'] as int,
          y0 = args['y0'] as int,
          x1 = args['x1'] as int,
          y1 = args['y1'] as int;
      final vertical = oldChain.carrier.dir == AxisDir.V;
      if ((vertical
              ? x0 == x1 && x0 == oldChain.carrier.pos
              : y0 == y1 && y0 == oldChain.carrier.pos) &&
          math.min(vertical ? y0 : x0, vertical ? y1 : x1) ==
              oldChain.startPos &&
          math.max(vertical ? y0 : x0, vertical ? y1 : x1) == oldChain.endPos)
        return EditResult(original, null);
    }
    if (prior != null) walls.remove(prior);
    final localAxes = [...doc.axes.floor];
    final coords = <String, String>{
      for (final a in oldAxes.all) '${a.dir.name}:${a.pos}': a.id
    };
    String coordinate(AxisDir dir, int value) {
      final limit =
          dir == AxisDir.V ? doc.footprint.width : doc.footprint.depth;
      if (value < 0 || value > limit) throw const FormatException('墙体必须在房屋范围内');
      final key = '${dir.name}:$value';
      if (coords.containsKey(key)) return coords[key]!;
      final id = newId();
      coords[key] = id;
      localAxes.add(FloorAxis(id: id, floorId: floorId, dir: dir, pos: value));
      return id;
    }

    BoundaryAnchor? anchor;
    int? lo, hi, carrier;
    AxisDir? direction;
    if (kind != 'DeleteDrawnWall') {
      final x0 = args['x0'] as int,
          y0 = args['y0'] as int,
          x1 = args['x1'] as int,
          y1 = args['y1'] as int;
      if ((x0 == x1) == (y0 == y1)) return const EditResult(null, '请拉出一段横墙或竖墙');
      direction = x0 == x1 ? AxisDir.V : AxisDir.H;
      lo = math.min(
          direction == AxisDir.V ? y0 : x0, direction == AxisDir.V ? y1 : x1);
      hi = math.max(
          direction == AxisDir.V ? y0 : x0, direction == AxisDir.V ? y1 : x1);
      carrier = direction == AxisDir.V ? x0 : y0;
      if (hi - lo < 300) return const EditResult(null, '墙长至少 0.30 米');
      anchor = BoundaryAnchor(
          axisId: coordinate(direction, carrier),
          startAxisId:
              coordinate(direction == AxisDir.V ? AxisDir.H : AxisDir.V, lo),
          endAxisId:
              coordinate(direction == AxisDir.V ? AxisDir.H : AxisDir.V, hi));
      if (anchor.axisId.startsWith('@'))
        return const EditResult(null, '外墙请通过房屋长宽调整');
      for (final w in [...walls]) {
        final c = resolveAnchor(oldAxes, w.anchor).chain!;
        if (c.carrier.dir == direction &&
            c.carrier.pos == carrier &&
            c.startPos < hi &&
            lo < c.endPos) {
          if (w is! OpenWall)
            return const EditResult(null, '这段位置已有墙体，请拖动端点延长已有墙');
          walls.remove(w);
          if (c.startPos < lo)
            walls.add(OpenWall(
                id: w.id,
                anchor: BoundaryAnchor(
                    axisId: w.anchor.axisId,
                    startAxisId: w.anchor.startAxisId,
                    endAxisId: anchor.startAxisId)));
          if (hi < c.endPos)
            walls.add(OpenWall(
                id: c.startPos < lo ? newId() : w.id,
                anchor: BoundaryAnchor(
                    axisId: w.anchor.axisId,
                    startAxisId: anchor.endAxisId,
                    endAxisId: w.anchor.endAxisId)));
        }
      }
      for (final stair in floor.stairs) {
        final r = resolveRect(oldAxes, stair.region).rect!;
        if (direction == AxisDir.V
            ? carrier > r.left &&
                carrier < r.right &&
                lo < r.top &&
                hi > r.bottom
            : carrier > r.bottom &&
                carrier < r.top &&
                lo < r.right &&
                hi > r.left) return const EditResult(null, '墙体不能穿过楼梯');
      }
      walls.add(SolidWall(
          id: prior?.id ?? newId(),
          anchor: anchor,
          value: prior?.value ?? doc.defaults.innerWallThickness));
    }
    final opens = <Opening>[];
    final removed = <String>{};
    for (final o in floor.openings) {
      final c = resolveAnchor(oldAxes, o.anchor).chain!;
      final start = switch (o.position) {
        CenterPosition() => (c.startPos + c.endPos - o.width) / 2,
        FromStartPosition(:final d) => c.startPos + d.toDouble(),
        FromEndPosition(:final d) => c.endPos - d - o.width.toDouble()
      };
      final hosted = oldChain != null &&
          c.carrier.id == oldChain.carrier.id &&
          start < oldChain.endPos &&
          start + o.width > oldChain.startPos;
      if (!hosted) {
        opens.add(o);
        continue;
      }
      if (kind == 'DeleteDrawnWall') {
        if (args['deleteHostedObjects'] != true)
          return const EditResult(null, '删除墙体会移除其门窗，请确认后再删除');
        removed.add(o.id);
        continue;
      }
      final shift = lo! - oldChain.startPos;
      final translated = hi! - oldChain.endPos == shift ? shift : 0;
      final offset = (start + translated - lo).round();
      if (offset < 0 || offset + o.width > hi - lo)
        return const EditResult(null, '墙体调整后无法容纳已有门窗');
      final p = FromStartPosition(offset);
      opens.add(switch (o) {
        DoorOpening() => DoorOpening(
            id: o.id,
            anchor: anchor!,
            position: p,
            width: o.width,
            height: o.height,
            sill: o.sill,
            hinge: o.hinge,
            opensTo: o.opensTo),
        WindowOpening() => WindowOpening(
            id: o.id,
            anchor: anchor!,
            position: p,
            width: o.width,
            height: o.height,
            sill: o.sill),
        SlidingOpening() => SlidingOpening(
            id: o.id,
            anchor: anchor!,
            position: p,
            width: o.width,
            height: o.height,
            sill: o.sill)
      });
    }
    doc = _replaceFloor(
        doc,
        Floor(
            id: floor.id,
            name: floor.name,
            height: floor.height,
            explicitWalls: true,
            rooms: floor.rooms,
            wallOverrides: walls,
            openings: opens,
            stairs: floor.stairs),
        axes: AxisSystem(global: doc.axes.global, floor: localAxes));
    if (removed.contains(doc.mainEntranceOpeningId)) {
      final raw = jsonDecode(encodeHouse(doc)) as Map<String, dynamic>;
      raw.remove('mainEntranceOpeningId');
      doc = decodeV1(raw).document!;
    }
    final preferred = <String, List<({double x, double y})>>{};
    if (oldChain != null &&
        kind == 'UpdateDrawnWall' &&
        direction == oldChain.carrier.dir) {
      final oldBase = deriveFloorBase(original, floorId);
      final alongShift = lo! - oldChain.startPos;
      for (final e in oldBase.edges.where((e) =>
          e.axis.id == oldChain.carrier.id &&
          e.start.pos >= oldChain.startPos &&
          e.end.pos <= oldChain.endPos)) {
        final along = (e.start.pos + e.end.pos) / 2 + alongShift;
        for (final side in [(-1, e.negative), (1, e.positive)]) {
          final id = oldBase.owners[side.$2];
          if (id == null) continue;
          final cross = carrier! + side.$1.toDouble();
          (preferred[id] ??= []).add(direction == AxisDir.V
              ? (x: cross, y: along)
              : (x: along, y: cross));
        }
      }
    }
    doc = recognizeWallRooms(doc, floorId, newId, preferred: preferred);
    if (oldChain != null) {
      final candidates = {
        oldChain.carrier.id,
        prior!.anchor.startAxisId,
        prior.anchor.endAxisId
      };
      final refs = <String>{};
      void rect(AxisRectangle r) => refs.addAll([r.x0, r.x1, r.y0, r.y1]);
      void wallAnchor(BoundaryAnchor a) =>
          refs.addAll([a.axisId, a.startAxisId, a.endAxisId]);
      for (final f in doc.floors) {
        for (final r in f.rooms) {
          for (final region in r.regions) rect(region);
        }
        for (final s in f.stairs) rect(s.region);
        for (final w in f.wallOverrides) wallAnchor(w.anchor);
        for (final o in f.openings) wallAnchor(o.anchor);
      }
      doc = _replaceFloor(doc, doc.floors.firstWhere((f) => f.id == floorId),
          axes: AxisSystem(global: doc.axes.global, floor: [
            for (final a in doc.axes.floor)
              if (a.floorId != floorId ||
                  !candidates.contains(a.id) ||
                  refs.contains(a.id))
                a
          ]));
    }
    final errors = validateHouse(doc);
    if (errors.isNotEmpty) return EditResult(null, errors.first.message);
    final healthy = documentOpenings(original)
        .where((o) => o.status == 'ok')
        .map((o) => o.opening.id)
        .toSet();
    if (documentOpenings(doc)
        .any((o) => healthy.contains(o.opening.id) && o.status != 'ok'))
      return const EditResult(null, '此调整会影响已有门窗，请避开门窗位置');
    return EditResult(doc, null);
  } on FormatException catch (e) {
    return EditResult(null, e.message);
  }
}
