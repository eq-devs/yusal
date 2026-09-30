import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';
import '../validation/document_validator.dart';

HouseDocument paintCells(HouseDocument doc, String floorId, List<Cell> stroke,
    RoomType type, String Function() newId,
    {bool erase = false}) {
  if (stroke.isEmpty) return doc;
  final floor = doc.floors.firstWhere((f) => f.id == floorId),
      axes = resolveFloorAxes(doc, floorId)!;
  if (stroke.any((c) => c.i < 0 || c.j < 0 || c.i >= axes.nx || c.j >= axes.ny))
    return doc;
  final stairCells = {
    for (final s in floor.stairs)
      ...cellsOfRect(resolveRect(axes, s.region).rect!)
  };
  final sets = {
    for (final r in floor.rooms) r.id: {...regionCells(axes, r.regions).cells}
  };
  final start =
      floor.rooms.where((r) => sets[r.id]!.contains(stroke.first)).firstOrNull;
  final selected = stroke.where((c) => !stairCells.contains(c)).toSet();
  if (selected.isEmpty || (!erase && stairCells.contains(stroke.first)))
    return doc;
  final target = erase ? '' : start?.id ?? newId();
  for (final entry in sets.entries) {
    if (erase || entry.key != target) entry.value.removeAll(selected);
  }
  if (!erase) (sets[target] ??= <Cell>{}).addAll(selected);
  final rooms = <Room>[];
  void append(Room room, Set<Cell> cells) {
    final parts = components(axes, cells).cells;
    for (var i = 0; i < parts.length; i++)
      rooms.add(Room(
          id: i == 0 ? room.id : newId(),
          type: room.type,
          name: room.name,
          regions: canonicalizeCells(axes, parts[i]).regions));
  }

  if (start == null && !erase)
    append(Room(id: target, type: type, name: roomNames[type]!, regions: []),
        sets[target]!);
  for (final room in floor.rooms) append(room, sets[room.id]!);
  final replacement = Floor(
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
      mainEntranceOpeningId: doc.mainEntranceOpeningId,
      defaults: doc.defaults,
      footprint: doc.footprint,
      axes: doc.axes,
      floors: [for (final f in doc.floors) f.id == floorId ? replacement : f],
      roof: doc.roof);
  return validateHouse(result).isEmpty ? result : doc;
}

const roomNames = {
  RoomType.living: '客厅',
  RoomType.bedroom: '卧室',
  RoomType.kitchen: '厨房',
  RoomType.bathroom: '卫生间',
  RoomType.dining: '餐厅',
  RoomType.custom: '房间'
};

HouseDocument createHouse(
    {required String name,
    required int width,
    required int depth,
    required int columns,
    required int rows,
    required String timestamp,
    required String Function() newId}) {
  final floorId = newId();
  return HouseDocument(
      schemaVersion: 1,
      meta: Meta(name: name, createdAt: timestamp, updatedAt: timestamp),
      defaults: const Defaults(
          outerWallThickness: 240,
          innerWallThickness: 120,
          slabThickness: 120,
          stairRiserMax: 175,
          stairTread: 260,
          stairWidthMin: 900,
          floorHeight: 3000,
          doorWidth: 900,
          doorHeight: 2100,
          windowWidth: 1500,
          windowHeight: 1500,
          windowSill: 900),
      footprint:
          BuildingFootprint(width: width, depth: depth, northAngleDeg: 0),
      axes: AxisSystem(global: [
        for (var i = 1; i < columns; i++)
          GlobalAxis(
              id: newId(), dir: AxisDir.V, pos: (width * i / columns).round()),
        for (var j = 1; j < rows; j++)
          GlobalAxis(
              id: newId(), dir: AxisDir.H, pos: (depth * j / rows).round())
      ], floor: []),
      floors: [
        Floor(
            id: floorId,
            name: '一楼',
            height: 3000,
            rooms: [],
            wallOverrides: [],
            openings: [],
            stairs: [])
      ],
      roof: const Roof.gable(ridgeDir: AxisDir.V, pitchDeg: 30, overhang: 500));
}
