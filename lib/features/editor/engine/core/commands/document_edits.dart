import 'package:yusal/features/editor/engine/core/axis/axis_resolver.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';

/// The commands [editDocumentObjects] carries out.
const objectEditKinds = {
  'SetFootprintSize',
  'SetNorthAngle',
  'AddAxis',
  'MoveAxis',
  'SetFloorHeight',
  'RenameFloor',
  'RenameRoom',
  'SetRoomType',
  'ResizeOpening',
  'FlipDoor',
  'MoveOpening',
  'DeleteOpening',
  'SetMainEntrance',
};

/// [doc] after command [kind], made by copying only the objects the command
/// changes: every other floor, room and opening is the same object as
/// before, so what is derived from them can be kept.
///
/// Answers null when the command is not one of [objectEditKinds], or when
/// anything about it is out of the ordinary: an argument of an unexpected
/// type, a missing object, a rule the command breaks. The caller then runs
/// the command the long way, which is what words every refusal. The
/// document returned has not been validated.
HouseDocument? editDocumentObjects(
    HouseDocument doc, String kind, Map<String, dynamic> args,
    [String Function()? newId]) {
  switch (kind) {
    case 'AddAxis':
      final dir = args['dir'];
      final pos = _int(args['pos']);
      final floorId = args['floorId'];
      if (newId == null || dir is! AxisDir || pos == null) return null;
      if (floorId != null &&
          (floorId is! String || !doc.floors.any((f) => f.id == floorId))) {
        return null;
      }
      // A line too close to another is refused the long way, which words
      // it; checked here first so that no id is drawn for it.
      for (final f in doc.floors) {
        if (floorId != null && f.id != floorId) continue;
        final axes = resolveFloorAxes(doc, f.id);
        if (axes == null) return null;
        for (final a in dir == AxisDir.V ? axes.v : axes.h) {
          if ((a.pos - pos).abs() < 300) return null;
        }
      }
      final id = newId();
      return _document(doc,
          axes: AxisSystem(global: [
            ...doc.axes.global,
            if (floorId == null) GlobalAxis(id: id, dir: dir, pos: pos)
          ], floor: [
            ...doc.axes.floor,
            if (floorId is String)
              FloorAxis(id: id, floorId: floorId, dir: dir, pos: pos)
          ]));
    case 'SetFootprintSize':
      var width = doc.footprint.width;
      var depth = doc.footprint.depth;
      if (args.containsKey('width')) {
        final v = _int(args['width']);
        if (v == null) return null;
        width = v;
      }
      if (args.containsKey('depth')) {
        final v = _int(args['depth']);
        if (v == null) return null;
        depth = v;
      }
      return _document(doc,
          footprint: BuildingFootprint(
              width: width,
              depth: depth,
              northAngleDeg: doc.footprint.northAngleDeg));
    case 'SetNorthAngle':
      final value = args['value'];
      if (value is! int || !const [0, 90, 180, 270].contains(value)) {
        return null;
      }
      return _document(doc,
          footprint: BuildingFootprint(
              width: doc.footprint.width,
              depth: doc.footprint.depth,
              northAngleDeg: value));
    case 'MoveAxis':
      final id = args['axisId'];
      final value = _int(args['pos']);
      if (id is! String || value == null) return null;
      for (final f in doc.floors) {
        final axes = resolveFloorAxes(doc, f.id);
        if (axes == null) return null;
        final lookup = lookupAxis(axes, id).axis;
        if (lookup == null) continue;
        if (lookup.kind == 'boundary') return null;
        final list = lookup.dir == AxisDir.V ? axes.v : axes.h;
        if (value < list[lookup.index - 1].pos + 300 ||
            value > list[lookup.index + 1].pos - 300) {
          return null;
        }
      }
      return _document(doc,
          axes: AxisSystem(global: [
            for (final a in doc.axes.global)
              a.id == id ? GlobalAxis(id: a.id, dir: a.dir, pos: value) : a
          ], floor: [
            for (final a in doc.axes.floor)
              a.id == id
                  ? FloorAxis(
                      id: a.id, floorId: a.floorId, dir: a.dir, pos: value)
                  : a
          ]));
    case 'SetFloorHeight':
      final value = _int(args['value']);
      if (value == null) return null;
      return _editFloor(doc, args['floorId'], (f) => _floor(f, height: value));
    case 'RenameFloor':
      final value = args['value'];
      if (value is! String) return null;
      return _editFloor(doc, args['floorId'], (f) => _floor(f, name: value));
    case 'RenameRoom':
      final value = args['value'];
      if (value is! String) return null;
      return _editRoom(doc, args['roomId'],
          (r) => Room(id: r.id, type: r.type, name: value, regions: r.regions));
    case 'SetRoomType':
      final next = args['value'];
      if (next is! RoomType) return null;
      return _editRoom(
          doc,
          args['roomId'],
          (r) => Room(
              id: r.id,
              type: next,
              // A room still carrying its type's stock name takes the new
              // type's; a name the user gave stays.
              name: r.name == roomNames[r.type] ? roomNames[next]! : r.name,
              regions: r.regions));
    case 'ResizeOpening':
      final fields = <String, int>{};
      for (final field in const ['width', 'height', 'sill']) {
        if (!args.containsKey(field)) continue;
        final v = _int(args[field]);
        if (v == null) return null;
        fields[field] = v;
      }
      return _editOpening(
          doc,
          args['openingId'],
          (o) => _opening(o,
              width: fields['width'],
              height: fields['height'],
              sill: fields['sill']));
    case 'FlipDoor':
      Hinge? hinge;
      OpeningSide? opensTo;
      if (args.containsKey('hinge')) {
        hinge = _named(Hinge.values, args['hinge']);
        if (hinge == null) return null;
      }
      if (args.containsKey('opensTo')) {
        opensTo = _named(OpeningSide.values, args['opensTo']);
        if (opensTo == null) return null;
      }
      return _editOpening(
          doc,
          args['openingId'],
          (o) => o is DoorOpening
              ? _opening(o, hinge: hinge, opensTo: opensTo)
              : null);
    case 'MoveOpening':
      final anchor = args['anchor'];
      if (anchor != null && anchor is! BoundaryAnchor) return null;
      final position = _position(args['position']);
      if (position == null) return null;
      return _editOpening(doc, args['openingId'], (o) {
        if (anchor is! BoundaryAnchor) return _opening(o, position: position);
        if (o is! DoorOpening) {
          return _opening(o, anchor: anchor, position: position);
        }
        // A door moved to another wall opens into the larger room there.
        final floor =
            doc.floors.firstWhere((f) => f.openings.any((p) => p.id == o.id));
        final base = deriveFloorBase(doc, floor.id);
        final chain = resolveAnchor(base.axes, anchor).chain;
        if (chain == null) return null;
        final center = switch (position) {
          FromStartPosition(:final d) => d.toDouble() + o.width / 2,
          FromEndPosition(:final d) => chain.nominalLength - d - o.width / 2,
          CenterPosition() => chain.nominalLength / 2,
        };
        final segment =
            chain.locate(center.round().clamp(0, chain.nominalLength));
        if (segment == null) return null;
        double score(Cell? cell) => cell == null
            ? -1
            : base.roomGeometry
                    .where((g) => g.id == base.owners[cell])
                    .firstOrNull
                    ?.clearArea ??
                0;
        return _opening(o,
            anchor: anchor,
            position: position,
            opensTo: score(segment.positiveSide) >= score(segment.negativeSide)
                ? OpeningSide.positiveSide
                : OpeningSide.negativeSide);
      });
    case 'DeleteOpening':
      final id = args['openingId'];
      if (id is! String) return null;
      return _document(doc,
          floors: [
            for (final f in doc.floors)
              f.openings.any((o) => o.id == id)
                  ? _floor(f, openings: [
                      for (final o in f.openings)
                        if (o.id != id) o
                    ])
                  : f
          ],
          mainEntrance:
              doc.mainEntranceOpeningId == id ? const _Entrance(null) : null);
    case 'SetMainEntrance':
      final id = args['openingId'];
      if (id == null) {
        return _document(doc, mainEntrance: const _Entrance(null));
      }
      if (id is! String) return null;
      final opening = doc.floors
          .expand((f) => f.openings)
          .where((o) => o.id == id)
          .firstOrNull;
      if (opening is! DoorOpening) return null;
      return _document(doc, mainEntrance: _Entrance(id));
  }
  return null;
}

/// A whole number a house file can hold, or null.
int? _int(Object? v) => v is int && v.abs() <= 2147483647 ? v : null;

T? _named<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;

/// The position a command gives as a file would write it, or null when it
/// is not exactly that.
OpeningPosition? _position(Object? raw) {
  if (raw is! Map) return null;
  final d = _int(raw['d']);
  return switch (raw['type']) {
    'center' when raw.length == 1 => const CenterPosition(),
    'fromStart' when raw.length == 2 && d != null => FromStartPosition(d),
    'fromEnd' when raw.length == 2 && d != null => FromEndPosition(d),
    _ => null,
  };
}

/// What to set the main entrance to; a null [id] takes it away.
class _Entrance {
  const _Entrance(this.id);
  final String? id;
}

HouseDocument _document(HouseDocument d,
        {BuildingFootprint? footprint,
        AxisSystem? axes,
        List<Floor>? floors,
        _Entrance? mainEntrance}) =>
    HouseDocument(
        schemaVersion: d.schemaVersion,
        meta: d.meta,
        mainEntranceOpeningId:
            mainEntrance == null ? d.mainEntranceOpeningId : mainEntrance.id,
        defaults: d.defaults,
        footprint: footprint ?? d.footprint,
        axes: axes ?? d.axes,
        floors: floors ?? d.floors,
        roof: d.roof,
        extras: d.extras);

Floor _floor(Floor f,
        {String? name,
        int? height,
        List<Room>? rooms,
        List<Opening>? openings}) =>
    Floor(
        explicitWalls: f.explicitWalls,
        id: f.id,
        name: name ?? f.name,
        height: height ?? f.height,
        rooms: rooms ?? f.rooms,
        wallOverrides: f.wallOverrides,
        openings: openings ?? f.openings,
        stairs: f.stairs,
        outside: f.outside);

Opening _opening(Opening o,
    {BoundaryAnchor? anchor,
    OpeningPosition? position,
    int? width,
    int? height,
    int? sill,
    Hinge? hinge,
    OpeningSide? opensTo}) {
  final a = anchor ?? o.anchor;
  final p = position ?? o.position;
  final w = width ?? o.width;
  final h = height ?? o.height;
  final s = sill ?? o.sill;
  return switch (o) {
    DoorOpening() => DoorOpening(
        id: o.id,
        anchor: a,
        position: p,
        width: w,
        height: h,
        sill: s,
        hinge: hinge ?? o.hinge,
        opensTo: opensTo ?? o.opensTo),
    WindowOpening() => WindowOpening(
        id: o.id, anchor: a, position: p, width: w, height: h, sill: s),
    SlidingOpening() => SlidingOpening(
        id: o.id, anchor: a, position: p, width: w, height: h, sill: s),
  };
}

/// [doc] with the floor [id] replaced by what [edit] makes of it.
HouseDocument? _editFloor(
    HouseDocument doc, Object? id, Floor Function(Floor) edit) {
  final index = doc.floors.indexWhere((f) => f.id == id);
  if (index < 0) return null;
  return _document(doc,
      floors: [...doc.floors]..[index] = edit(doc.floors[index]));
}

/// [doc] with the room [id] replaced by what [edit] makes of it.
HouseDocument? _editRoom(
    HouseDocument doc, Object? id, Room Function(Room) edit) {
  for (final f in doc.floors) {
    final index = f.rooms.indexWhere((r) => r.id == id);
    if (index < 0) continue;
    return _editFloor(doc, f.id,
        (f) => _floor(f, rooms: [...f.rooms]..[index] = edit(f.rooms[index])));
  }
  return null;
}

/// [doc] with the opening [id] replaced by what [edit] makes of it; null
/// when there is none or [edit] declines.
HouseDocument? _editOpening(
    HouseDocument doc, Object? id, Opening? Function(Opening) edit) {
  for (final f in doc.floors) {
    final index = f.openings.indexWhere((o) => o.id == id);
    if (index < 0) continue;
    final next = edit(f.openings[index]);
    if (next == null) return null;
    return _editFloor(
        doc, f.id, (f) => _floor(f, openings: [...f.openings]..[index] = next));
  }
  return null;
}
