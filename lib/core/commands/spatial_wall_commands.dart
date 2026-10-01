import 'dart:convert';
import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';
import '../geometry/derived_house.dart';
import '../geometry/opening_constraints.dart';
import '../geometry/floor_base.dart';
import '../serialization/house_codec.dart';
import 'design_commands.dart';

/// Transfers only the strip swept by the selected wall. All other room edges
/// and all other floors retain their physical coordinates.
EditResult moveLocalWall(HouseDocument doc, String floorId,
    BoundaryAnchor anchor, int position, String Function() newId) {
  final base = deriveFloorBase(doc, floorId), axes = base.axes;
  final oldOpenings = deriveOpenings(doc, base, floorId);
  final wall = base.wallSegments
      .where((w) =>
          w.ref.anchor.axisId == anchor.axisId &&
          w.ref.anchor.startAxisId == anchor.startAxisId &&
          w.ref.anchor.endAxisId == anchor.endAxisId)
      .firstOrNull;
  if (wall == null) return const EditResult(null, '这段墙已经变化，请重新选择');
  if (wall.axis.kind == 'boundary')
    return const EditResult(null, '外墙请通过房屋长宽调整');
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  final list = wall.axis.dir == AxisDir.V ? axes.v : axes.h;
  final index = wall.axis.index;
  if (position < list[index - 1].pos + 300 ||
      position > list[index + 1].pos - 300) {
    return const EditResult(null, '不能越过相邻墙线，请保留至少 0.30 米');
  }
  if (position == wall.axis.pos) return EditResult(doc, null);
  // A single local wall can reuse its axis, allowing fine adjustments without
  // adding a redundant coordinate. Never move a global axis for a local edit.
  if (wall.axis.kind == 'floor' &&
      base.wallSegments.where((w) => w.axis.id == wall.axis.id).length == 1 &&
      !floor.stairs.any((s) => [
            s.region.x0,
            s.region.x1,
            s.region.y0,
            s.region.y1
          ].contains(wall.axis.id))) {
    return executeDocumentCommand(
        doc, 'MoveAxis', {'axisId': wall.axis.id, 'pos': position}, newId);
  }
  if ((position - wall.axis.pos).abs() < 300) {
    return const EditResult(null, '这段墙与其他墙共用位置，请移动至少 0.30 米');
  }
  final insertedId = newId();
  final system = AxisSystem(global: doc.axes.global, floor: [
    ...doc.axes.floor,
    FloorAxis(
        id: insertedId, floorId: floorId, dir: wall.axis.dir, pos: position)
  ]);
  HouseDocument rebuild(List<Floor> floors) => HouseDocument(
      schemaVersion: doc.schemaVersion,
      meta: doc.meta,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: system,
      floors: floors,
      roof: doc.roof,
      mainEntranceOpeningId: doc.mainEntranceOpeningId);
  final staged = rebuild(doc.floors);
  final expanded = resolveFloorAxes(staged, floorId)!;
  if (expanded.issues.isNotEmpty) return const EditResult(null, '此处与已有墙线过近');
  String? ownerAt(double x, double y) {
    final i = axes.v.indexWhere((a) => a.pos > x) - 1;
    final j = axes.h.indexWhere((a) => a.pos > y) - 1;
    return base.owners[Cell(i, j)];
  }

  final sets = {for (final room in floor.rooms) room.id: <Cell>{}};
  final stairIds = floor.stairs.map((s) => s.id).toSet();
  final low = position < wall.axis.pos ? position : wall.axis.pos;
  final high = position > wall.axis.pos ? position : wall.axis.pos;
  for (var j = 0; j < expanded.ny; j++) {
    for (var i = 0; i < expanded.nx; i++) {
      final x = (expanded.v[i].pos + expanded.v[i + 1].pos) / 2;
      final y = (expanded.h[j].pos + expanded.h[j + 1].pos) / 2;
      final cross = wall.axis.dir == AxisDir.V ? x : y;
      final along = wall.axis.dir == AxisDir.V ? y : x;
      var owner = ownerAt(x, y);
      if (cross > low &&
          cross < high &&
          along > wall.start.pos &&
          along < wall.end.pos) {
        final sourceCross =
            wall.axis.pos + (position > wall.axis.pos ? -0.5 : 0.5);
        final replacement = wall.axis.dir == AxisDir.V
            ? ownerAt(sourceCross, y)
            : ownerAt(x, sourceCross);
        if (stairIds.contains(owner) || stairIds.contains(replacement)) {
          return const EditResult(null, '此调整会影响楼梯，请先调整楼梯');
        }
        owner = replacement;
      }
      if (owner != null && sets.containsKey(owner))
        sets[owner]!.add(Cell(i, j));
    }
  }
  final rooms = <Room>[];
  for (final room in floor.rooms) {
    final parts = components(expanded, sets[room.id]!).cells;
    if (parts.length != 1) return const EditResult(null, '此调整会切断或移除房间，请换一个位置');
    rooms.add(Room(
        id: room.id,
        name: room.name,
        type: room.type,
        regions: canonicalizeCells(expanded, parts.single).regions));
  }
  final changed = Floor(
      explicitWalls: floor.explicitWalls,
      id: floor.id,
      name: floor.name,
      height: floor.height,
      rooms: rooms,
      wallOverrides: floor.wallOverrides,
      openings: floor.openings,
      stairs: floor.stairs);
  final raw = jsonDecode(encodeHouse(rebuild([
    for (final item in doc.floors) item.id == floorId ? changed : item
  ]))) as Map<String, dynamic>;
  final target = (raw['floors'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((f) => f['id'] == floorId);
  final hostedIds = oldOpenings
      .where((p) => p.host?.ref == wall.ref)
      .map((p) => p.opening.id)
      .toSet();
  for (final opening in target['openings'] as List) {
    final a = opening['anchor'] as Map<String, dynamic>;
    if (hostedIds.contains(opening['id'])) a['axisId'] = insertedId;
  }
  for (final override in target['wallOverrides'] as List) {
    final a = override['anchor'] as Map<String, dynamic>;
    if (a['axisId'] != wall.axis.id) continue;
    final resolved = resolveAnchor(
            axes,
            BoundaryAnchor(
                axisId: a['axisId'] as String,
                startAxisId: a['startAxisId'] as String,
                endAxisId: a['endAxisId'] as String))
        .chain!;
    if (resolved.startPos >= wall.start.pos &&
        resolved.endPos <= wall.end.pos) {
      a['axisId'] = insertedId;
    } else if (resolved.startPos < wall.end.pos &&
        resolved.endPos > wall.start.pos) {
      return const EditResult(null, '此处有跨越多段墙的设置，请先恢复默认墙厚');
    }
  }
  final loaded = loadHouse(utf8.encode(jsonEncode(raw)));
  if (!loaded.isSuccess)
    return EditResult(null, loaded.failure!.errors.first.message);
  final result = loaded.document!;
  final healthy = oldOpenings
      .where((p) => p.status == 'ok')
      .map((p) => p.opening.id)
      .toSet();
  if (documentOpenings(result, floorId: floorId)
      .any((p) => healthy.contains(p.opening.id) && p.status != 'ok')) {
    return const EditResult(null, '此调整影响已有门窗，请先挪开门窗');
  }
  return EditResult(result, null);
}
