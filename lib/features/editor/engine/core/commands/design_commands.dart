import 'package:yusal/features/editor/engine/core/axis/axis_resolver.dart';
import 'package:yusal/features/editor/engine/core/canonicalization/room_canonicalizer.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/geometry/opening_constraints.dart';
import 'package:yusal/features/editor/engine/core/validation/document_validator.dart';

class EditResult {
  const EditResult(this.document, this.error, [this.code = 'INVALID_VALUE']);
  final HouseDocument? document;
  final String? error;

  /// Why the edit was refused, as a word that does not change with the
  /// wording of [error]; only meaningful when [error] is set.
  final String code;
  bool get accepted => document != null;

  /// The refusal for a document that breaks [errors]' first rule.
  factory EditResult.invalid(List<ValidationError> errors) {
    final first = errors.first;
    return EditResult(
        null,
        '操作无法完成：${first.message}',
        switch (first.code) {
          // Lines too close together.
          'INV05' => 'SPACING',
          // Two wall pieces, or two rooms or stairs, in the same place.
          'INV14' => 'OVERLAP',
          // A room outside the house and two rooms in one place share a
          // number; only the words tell them apart.
          'INV11' => first.message.contains('重叠') ? 'OVERLAP' : 'OUTSIDE',
          _ => 'INVALID_VALUE',
        });
  }
}

/// Thrown inside a command to refuse it with [message].
class _Refusal implements Exception {
  const _Refusal(this.message, [this.code = 'INVALID_VALUE']);
  final String message;
  final String code;
}

/// New floors follow the first floor's naming: 一楼, 二楼 … 十楼, then digits.
String _floorName(int number) =>
    number <= 10 ? '${'一二三四五六七八九十'[number - 1]}楼' : '$number楼';

/// Carries out the document command [kind] on [original].
///
/// Every command copies only the objects it changes: the other floors,
/// rooms and openings stay the same objects, so what is derived from them
/// is kept. The result is validated before it is returned.
EditResult executeDocumentCommand(HouseDocument original, String kind,
    Map<String, dynamic> args, String Function() newId) {
  try {
    final next = _edit(original, kind, args, newId);
    if (identical(next, original)) return EditResult(original, null);
    final errors = validateHouse(next);
    if (errors.isNotEmpty) return EditResult.invalid(errors);
    final refusal = _openingsStayHealthy(original, next, kind, args);
    if (refusal != null) return refusal;
    return EditResult(next, null);
  } on _Refusal catch (r) {
    return EditResult(null, r.message, r.code);
  } catch (_) {
    return const EditResult(null, '操作参数无效，原设计已保留');
  }
}

/// Refuses a size change that breaks a door or window, and an opening edit
/// that leaves the opening off its wall or over another one.
EditResult? _openingsStayHealthy(HouseDocument before, HouseDocument after,
    String kind, Map<String, dynamic> args) {
  if (kind == 'SetFootprintSize' || kind == 'MoveAxis') {
    final healthy = documentOpenings(before)
        .where((p) => p.status == 'ok')
        .map((p) => p.opening.id)
        .toSet();
    if (documentOpenings(after)
        .any((p) => healthy.contains(p.opening.id) && p.status != 'ok')) {
      return const EditResult(null, '此尺寸会影响已有门窗，请先调整门窗或保留更多空间');
    }
  }
  if (const {'AddOpening', 'MoveOpening', 'ResizeOpening', 'SetOpeningKind'}
      .contains(kind)) {
    final existing =
        before.floors.expand((f) => f.openings).map((o) => o.id).toSet();
    final placements = documentOpenings(after);
    for (final candidate in placements) {
      final changed = kind == 'AddOpening'
          ? !existing.contains(candidate.opening.id)
          : candidate.opening.id == args['openingId'];
      if (!changed) continue;
      if (candidate.status != 'ok') {
        return const EditResult(null, '门窗超出有效墙面，请换一个位置或调整尺寸');
      }
      for (final other in placements) {
        if (candidate.opening.id == other.opening.id || other.status != 'ok') {
          continue;
        }
        if (candidate.host?.ref == other.host?.ref &&
            candidate.start < other.end &&
            other.start < candidate.end &&
            candidate.opening.sill <
                other.opening.sill + other.opening.height &&
            other.opening.sill <
                candidate.opening.sill + candidate.opening.height) {
          return const EditResult(null, '与已有门窗重叠，请挪开一些', 'OVERLAP');
        }
      }
    }
  }
  return null;
}

HouseDocument _edit(HouseDocument doc, String kind, Map<String, dynamic> args,
    String Function() newId) {
  switch (kind) {
    case 'SetFootprintSize':
      return _document(doc,
          footprint: BuildingFootprint(
              width: (args['width'] as int?) ?? doc.footprint.width,
              depth: (args['depth'] as int?) ?? doc.footprint.depth,
              northAngleDeg: doc.footprint.northAngleDeg));
    case 'SetNorthAngle':
      final value = args['value'] as int;
      if (!const [0, 90, 180, 270].contains(value)) {
        throw const _Refusal('请选择四个正北方向之一');
      }
      return _document(doc,
          footprint: BuildingFootprint(
              width: doc.footprint.width,
              depth: doc.footprint.depth,
              northAngleDeg: value));
    case 'SetRoof':
      return _document(doc, roof: roofFromJson(args['roof'] as Map));
    case 'SetDefault':
      return _document(doc,
          defaults: _setDefault(
              doc.defaults, args['field'] as String, args['value'] as int));
    case 'AddAxis':
      final floorId = args['floorId'] as String?;
      if (floorId != null && !doc.floors.any((f) => f.id == floorId)) {
        throw const _Refusal('找不到这一层', 'NOT_FOUND');
      }
      final dir = args['dir'] as AxisDir;
      final pos = args['pos'] as int;
      final id = newId();
      return _document(doc,
          axes: AxisSystem(global: [
            ...doc.axes.global,
            if (floorId == null) GlobalAxis(id: id, dir: dir, pos: pos)
          ], floor: [
            ...doc.axes.floor,
            if (floorId != null)
              FloorAxis(id: id, floorId: floorId, dir: dir, pos: pos)
          ]));
    case 'PromoteFloorAxis':
      final id = args['axisId'] as String;
      final local = doc.axes.floor.firstWhere((a) => a.id == id,
          orElse: () => throw const _Refusal('找不到这条线', 'NOT_FOUND'));
      return _document(doc,
          axes: AxisSystem(global: [
            ...doc.axes.global,
            GlobalAxis(id: local.id, dir: local.dir, pos: local.pos)
          ], floor: [
            for (final a in doc.axes.floor)
              if (a.id != id) a
          ]));
    case 'MoveAxis':
      final id = args['axisId'] as String;
      final value = args['pos'] as int;
      for (final f in doc.floors) {
        final axes = resolveFloorAxes(doc, f.id)!;
        final lookup = lookupAxis(axes, id).axis;
        if (lookup == null) continue;
        if (lookup.kind == 'boundary') {
          throw const _Refusal('边界尺寸请通过房屋宽深修改');
        }
        final list = lookup.dir == AxisDir.V ? axes.v : axes.h;
        if (value < list[lookup.index - 1].pos + 300 ||
            value > list[lookup.index + 1].pos - 300) {
          throw const _Refusal('分隔线不能越过相邻线，间距至少 0.30 米', 'SPACING');
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
    case 'AddFloor':
      final index = _floorIndex(doc, args['floorId']);
      return _document(doc,
          floors: [...doc.floors]..insert(
              index + 1,
              Floor(
                  id: newId(),
                  name: _floorName(doc.floors.length + 1),
                  height: doc.defaults.floorHeight,
                  rooms: const [],
                  wallOverrides: const [],
                  openings: const [],
                  stairs: const [])));
    case 'CopyFloor':
      return _copyFloor(doc, _floorIndex(doc, args['floorId']), newId);
    case 'DeleteFloor':
      if (doc.floors.length == 1) throw const _Refusal('至少保留一层');
      final index = _floorIndex(doc, args['floorId']);
      final removed = doc.floors[index];
      final floors = [...doc.floors]..removeAt(index);
      if (index == doc.floors.length - 1 &&
          index > 0 &&
          floors[index - 1].stairs.isNotEmpty) {
        if (args['deleteStairs'] != true) {
          throw const _Refusal('删除顶层后，下层楼梯没有上层。请确认同时删除这些楼梯');
        }
        floors[index - 1] = floors[index - 1].copyWith(stairs: const []);
      }
      final entrance = doc.mainEntranceOpeningId;
      return _document(doc,
          floors: floors,
          axes: AxisSystem(global: doc.axes.global, floor: [
            for (final a in doc.axes.floor)
              if (a.floorId != removed.id) a
          ]),
          mainEntrance: removed.openings.any((o) => o.id == entrance)
              ? const _Entrance(null)
              : null);
    case 'SetFloorHeight':
      return _editFloor(doc, args['floorId'],
          (f) => f.copyWith(height: args['value'] as int));
    case 'RenameFloor':
      return _editFloor(doc, args['floorId'],
          (f) => f.copyWith(name: args['value'] as String));
    case 'MergeRooms':
      return _mergeRooms(
          doc, args['roomIdA'] as String, args['roomIdB'] as String);
    case 'RenameRoom':
      final value = args['value'] as String;
      return _editRoom(doc, args['roomId'],
          (r) => Room(id: r.id, type: r.type, name: value, regions: r.regions));
    case 'SetRoomType':
      final next = args['value'] as RoomType;
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
    case 'AddOpening':
      return _addOpening(doc, args, newId);
    case 'SetOpeningKind':
      return _setOpeningKind(
          doc, args['openingId'], args['kind'] as OpeningKind);
    case 'ResizeOpening':
      return _editOpening(
          doc,
          args['openingId'],
          (o) => _opening(o,
              width: args['width'] as int?,
              height: args['height'] as int?,
              sill: args['sill'] as int?));
    case 'FlipDoor':
      return _editOpening(doc, args['openingId'], (o) {
        if (o is! DoorOpening) throw const _Refusal('只有门可以调整开向', 'NOT_A_DOOR');
        return _opening(o,
            hinge: _named(Hinge.values, args['hinge']),
            opensTo: _named(OpeningSide.values, args['opensTo']));
      });
    case 'MoveOpening':
      return _moveOpening(doc, args);
    case 'DeleteOpening':
      final id = args['openingId'] as String;
      _findOpening(doc, id);
      return _document(doc,
          floors: [
            for (final f in doc.floors)
              f.openings.any((o) => o.id == id)
                  ? f.copyWith(openings: [
                      for (final o in f.openings)
                        if (o.id != id) o
                    ])
                  : f
          ],
          mainEntrance:
              doc.mainEntranceOpeningId == id ? const _Entrance(null) : null);
    case 'SetMainEntrance':
      final id = args['openingId'] as String?;
      if (id == null) {
        return _document(doc, mainEntrance: const _Entrance(null));
      }
      if (_findOpening(doc, id) is! DoorOpening) {
        throw const _Refusal('主入口需要是一扇门', 'NOT_A_DOOR');
      }
      return _document(doc, mainEntrance: _Entrance(id));
    case 'AddStair':
      return _addStair(doc, args, newId);
    case 'UpdateStair':
      return _updateStair(doc, args, newId);
    case 'DeleteStair':
      final id = args['stairId'] as String;
      if (!doc.floors.any((f) => f.stairs.any((s) => s.id == id))) {
        throw const _Refusal('找不到这个楼梯', 'NOT_FOUND');
      }
      return _document(doc, floors: [
        for (final f in doc.floors)
          f.stairs.any((s) => s.id == id)
              ? f.copyWith(stairs: [
                  for (final s in f.stairs)
                    if (s.id != id) s
                ])
              : f
      ]);
    case 'SetWallOverride':
      return _setWallOverride(doc, args, newId);
  }
  throw _Refusal('尚未支持的命令 $kind');
}

/// A roof from its file form, as the command catalog has already checked
/// it.
Roof roofFromJson(Map<dynamic, dynamic> m) => switch (m['type']) {
      'flat' => Roof.flat(m['parapetHeight'] as int),
      'gable' => Roof.gable(
          ridgeDir: AxisDir.values.byName(m['ridgeDir'] as String),
          pitchDeg: m['pitchDeg'] as int,
          overhang: m['overhang'] as int),
      'hip' => Roof.hip(
          pitchDeg: m['pitchDeg'] as int, overhang: m['overhang'] as int),
      _ => throw const _Refusal('未知屋顶类型'),
    };

Defaults _setDefault(Defaults d, String field, int v) => Defaults(
    outerWallThickness:
        field == 'outerWallThickness' ? v : d.outerWallThickness,
    innerWallThickness:
        field == 'innerWallThickness' ? v : d.innerWallThickness,
    slabThickness: field == 'slabThickness' ? v : d.slabThickness,
    stairRiserMax: field == 'stairRiserMax' ? v : d.stairRiserMax,
    stairTread: field == 'stairTread' ? v : d.stairTread,
    stairWidthMin: field == 'stairWidthMin' ? v : d.stairWidthMin,
    floorHeight: field == 'floorHeight' ? v : d.floorHeight,
    doorWidth: field == 'doorWidth' ? v : d.doorWidth,
    doorHeight: field == 'doorHeight' ? v : d.doorHeight,
    windowWidth: field == 'windowWidth' ? v : d.windowWidth,
    windowHeight: field == 'windowHeight' ? v : d.windowHeight,
    windowSill: field == 'windowSill' ? v : d.windowSill);

int _floorIndex(HouseDocument doc, Object? id) {
  final index = doc.floors.indexWhere((f) => f.id == id);
  if (index < 0) throw const _Refusal('找不到这一层', 'NOT_FOUND');
  return index;
}

/// A copy of the floor at [index] above it: new ids for the floor, its
/// local lines, rooms, walls and openings; no stairs, which need a floor
/// above.
HouseDocument _copyFloor(
    HouseDocument doc, int index, String Function() newId) {
  final source = doc.floors[index];
  final ids = <String, String>{source.id: newId()};
  final locals = doc.axes.floor.where((a) => a.floorId == source.id).toList();
  for (final a in locals) {
    ids[a.id] = newId();
  }
  for (final o in [
    ...source.rooms.map((r) => r.id),
    ...source.wallOverrides.map((w) => w.id),
    ...source.openings.map((o) => o.id),
  ]) {
    ids[o] = newId();
  }
  String id(String v) => ids[v] ?? v;
  AxisRectangle rect(AxisRectangle r) =>
      AxisRectangle(x0: id(r.x0), x1: id(r.x1), y0: id(r.y0), y1: id(r.y1));
  BoundaryAnchor anchor(BoundaryAnchor a) => BoundaryAnchor(
      axisId: id(a.axisId),
      startAxisId: id(a.startAxisId),
      endAxisId: id(a.endAxisId));
  final copy = Floor(
      id: ids[source.id]!,
      name: '${source.name} 副本',
      height: source.height,
      explicitWalls: source.explicitWalls,
      rooms: [
        for (final r in source.rooms)
          Room(
              id: id(r.id),
              type: r.type,
              name: r.name,
              regions: [for (final g in r.regions) rect(g)])
      ],
      wallOverrides: [
        for (final w in source.wallOverrides)
          switch (w) {
            OpenWall() => OpenWall(id: id(w.id), anchor: anchor(w.anchor)),
            ThicknessWall() => ThicknessWall(
                id: id(w.id), anchor: anchor(w.anchor), value: w.value),
            SolidWall() => SolidWall(
                id: id(w.id),
                anchor: anchor(w.anchor),
                value: w.value,
                height: w.height),
          }
      ],
      openings: [
        for (final o in source.openings)
          _opening(o, id: id(o.id), anchor: anchor(o.anchor))
      ],
      stairs: const [],
      outside: [
        for (final r in source.outside) rect(r)
      ]);
  return _document(doc,
      floors: [...doc.floors]..insert(index + 1, copy),
      axes: AxisSystem(global: doc.axes.global, floor: [
        ...doc.axes.floor,
        for (final a in locals)
          FloorAxis(id: id(a.id), floorId: copy.id, dir: a.dir, pos: a.pos)
      ]));
}

HouseDocument _mergeRooms(HouseDocument doc, String a, String b) {
  if (a == b) return doc;
  final f = doc.floors.firstWhere((f) => f.rooms.any((r) => r.id == a),
      orElse: () => throw const _Refusal('找不到这个房间', 'NOT_FOUND'));
  final ra = f.rooms.firstWhere((r) => r.id == a);
  final rb = f.rooms.where((r) => r.id == b).firstOrNull;
  if (rb == null) throw const _Refusal('只能合并同一楼层的房间');
  final axes = resolveFloorAxes(doc, f.id)!;
  final ca = regionCells(axes, ra.regions).cells;
  final cb = regionCells(axes, rb.regions).cells;
  final cells = {...ca, ...cb};
  if (!isConnected(cells)) throw const _Refusal('只能合并相邻房间', 'NOT_ADJACENT');
  final keep = compareComponentPriority(axes, ca, cb) <= 0 ? ra : rb;
  final gone = keep.id == a ? b : a;
  final merged = Room(
      id: keep.id,
      type: keep.type,
      name: keep.name,
      regions: canonicalizeCells(axes, cells).regions);
  return _editFloor(
      doc,
      f.id,
      (f) => f.copyWith(rooms: [
            for (final r in f.rooms)
              if (r.id == keep.id) merged else if (r.id != gone) r
          ]));
}

/// Which side of [chain] at [along] the door opens to: the larger room.
OpeningSide _opensToLarger(FloorBase base, ResolvedChain chain, int along) {
  final segment = chain.locate(along.clamp(0, chain.nominalLength))!;
  double score(Cell? c) =>
      c == null ? -1 : base.roomsById[base.owners[c]]?.clearArea ?? 0;
  return score(segment.positiveSide) >= score(segment.negativeSide)
      ? OpeningSide.positiveSide
      : OpeningSide.negativeSide;
}

HouseDocument _addOpening(
    HouseDocument doc, Map<String, dynamic> args, String Function() newId) {
  final floorId = args['floorId'] as String;
  _floorIndex(doc, floorId);
  final anchor = args['anchor'] as BoundaryAnchor;
  final base = deriveFloorBase(doc, floorId);
  final chain = resolveAnchor(base.axes, anchor).chain!;
  final tap = (args['tapT'] as num).toDouble();
  final kind = args['kind'] as OpeningKind;
  if (tap < 0 || tap > chain.nominalLength) {
    throw const _Refusal('点击位置不在墙段内');
  }
  final window = kind == OpeningKind.window;
  final width = window ? doc.defaults.windowWidth : doc.defaults.doorWidth;
  final height = window ? doc.defaults.windowHeight : doc.defaults.doorHeight;
  final sill = window ? doc.defaults.windowSill : 0;
  final nearStart = tap <= chain.nominalLength / 2;
  OpeningPosition position = kind == OpeningKind.door
      ? (nearStart ? const FromStartPosition(200) : const FromEndPosition(200))
      : const CenterPosition();
  if (args['centerAtTap'] == true) {
    if (width > chain.nominalLength) throw const _Refusal('墙面太短，放不下这个门窗');
    position = FromStartPosition(
        (tap - width / 2).round().clamp(0, chain.nominalLength - width));
  }
  final id = newId();
  final Opening opening = switch (kind) {
    OpeningKind.door => DoorOpening(
        id: id,
        anchor: anchor,
        position: position,
        width: width,
        height: height,
        sill: sill,
        hinge: nearStart ? Hinge.start : Hinge.end,
        opensTo: _opensToLarger(base, chain, tap.round())),
    OpeningKind.window => WindowOpening(
        id: id,
        anchor: anchor,
        position: position,
        width: width,
        height: height,
        sill: sill),
    OpeningKind.sliding => SlidingOpening(
        id: id,
        anchor: anchor,
        position: position,
        width: width,
        height: height,
        sill: sill),
  };
  return _editFloor(
      doc, floorId, (f) => f.copyWith(openings: [...f.openings, opening]));
}

HouseDocument _setOpeningKind(HouseDocument doc, Object? id, OpeningKind kind) {
  final floor = doc.floors.firstWhere((f) => f.openings.any((o) => o.id == id),
      orElse: () => throw const _Refusal('找不到这个门窗', 'NOT_FOUND'));
  final o = floor.openings.firstWhere((o) => o.id == id);
  final Opening next;
  switch (kind) {
    case OpeningKind.door:
      final placed =
          deriveOpenings(doc, deriveFloorBase(doc, floor.id), floor.id)
              .firstWhere((p) => p.opening.id == id);
      final base = deriveFloorBase(doc, floor.id);
      final chain = resolveAnchor(base.axes, o.anchor).chain!;
      next = DoorOpening(
          id: o.id,
          anchor: o.anchor,
          position: o.position,
          width: o.width,
          height: o.height,
          sill: 0,
          hinge: o.position is FromEndPosition ? Hinge.end : Hinge.start,
          opensTo: _opensToLarger(base, chain,
              ((placed.start + placed.end) / 2 - chain.start.pos).round()));
    case OpeningKind.window:
      next = WindowOpening(
          id: o.id,
          anchor: o.anchor,
          position: o.position,
          width: o.width,
          height: doc.defaults.windowHeight,
          sill: doc.defaults.windowSill);
    case OpeningKind.sliding:
      next = SlidingOpening(
          id: o.id,
          anchor: o.anchor,
          position: o.position,
          width: o.width,
          height: o.height,
          sill: 0);
  }
  return _document(_editOpening(doc, id, (_) => next),
      mainEntrance: kind != OpeningKind.door && doc.mainEntranceOpeningId == id
          ? const _Entrance(null)
          : null);
}

OpeningPosition _position(Map<dynamic, dynamic> m) => switch (m['type']) {
      'center' => const CenterPosition(),
      'fromStart' => FromStartPosition(m['d'] as int),
      'fromEnd' => FromEndPosition(m['d'] as int),
      _ => throw const _Refusal('门窗位置无效'),
    };

HouseDocument _moveOpening(HouseDocument doc, Map<String, dynamic> args) {
  final anchor = args['anchor'] as BoundaryAnchor?;
  final position = _position(args['position'] as Map);
  return _editOpening(doc, args['openingId'], (o) {
    if (anchor == null) return _opening(o, position: position);
    if (o is! DoorOpening) {
      return _opening(o, anchor: anchor, position: position);
    }
    // A door moved to another wall opens into the larger room there.
    final floor =
        doc.floors.firstWhere((f) => f.openings.any((p) => p.id == o.id));
    final base = deriveFloorBase(doc, floor.id);
    final chain = resolveAnchor(base.axes, anchor).chain!;
    final center = switch (position) {
      FromStartPosition(:final d) => d + o.width / 2,
      FromEndPosition(:final d) => chain.nominalLength - d - o.width / 2,
      CenterPosition() => chain.nominalLength / 2,
    };
    return _opening(o,
        anchor: anchor,
        position: position,
        opensTo: _opensToLarger(base, chain, center.round()));
  });
}

/// Clears the cells under a stair's [region] on [floorId] so no room
/// overlaps it; with drawn walls, refuses a stair across a wall.
HouseDocument _clearUnderStair(HouseDocument doc, String floorId,
    AxisRectangle region, String Function() newId) {
  final index = _floorIndex(doc, floorId);
  if (index == doc.floors.length - 1) {
    throw const _Refusal('楼梯需要上方还有楼层', 'TOP_FLOOR');
  }
  final axes = resolveFloorAxes(doc, floorId)!;
  final r = resolveRect(axes, region).rect!;
  if (doc.floors[index].explicitWalls &&
      deriveFloorBase(doc, floorId).wallSegments.any((w) =>
          w.axis.kind != 'boundary' &&
          (w.axis.dir == AxisDir.V
              ? w.axis.pos > r.left &&
                  w.axis.pos < r.right &&
                  w.start.pos < r.top &&
                  w.end.pos > r.bottom
              : w.axis.pos > r.bottom &&
                  w.axis.pos < r.top &&
                  w.start.pos < r.right &&
                  w.end.pos > r.left))) {
    throw const _Refusal('楼梯不能穿过已有墙体，请先移动或删除这段墙');
  }
  return paintCells(doc, floorId, cellsOfRect(r), RoomType.custom, newId,
      erase: true);
}

Stair _stair(String id, AxisRectangle region, StairType type, StairEdge edge,
        StairTurn turn) =>
    type == StairType.straight
        ? StraightStair(id: id, region: region, startEdge: edge)
        : TurnStair(
            id: id, region: region, startEdge: edge, turn: turn, type: type);

HouseDocument _addStair(
    HouseDocument doc, Map<String, dynamic> args, String Function() newId) {
  final floorId = args['floorId'] as String;
  final region = args['region'] as AxisRectangle;
  final cleared = _clearUnderStair(doc, floorId, region, newId);
  final stair = _stair(newId(), region, args['type'] as StairType,
      StairEdge.bottom, StairTurn.left);
  return _editFloor(
      cleared, floorId, (f) => f.copyWith(stairs: [...f.stairs, stair]));
}

HouseDocument _updateStair(
    HouseDocument doc, Map<String, dynamic> args, String Function() newId) {
  final id = args['stairId'] as String;
  final floor = doc.floors.firstWhere((f) => f.stairs.any((s) => s.id == id),
      orElse: () => throw const _Refusal('找不到这个楼梯', 'NOT_FOUND'));
  final old = floor.stairs.firstWhere((s) => s.id == id);
  final region = args['region'] as AxisRectangle?;
  final base =
      region == null ? doc : _clearUnderStair(doc, floor.id, region, newId);
  final stair = _stair(
      id,
      region ?? old.region,
      _named(StairType.values, args['type']) ?? old.type,
      _named(StairEdge.values, args['startEdge']) ?? old.startEdge,
      _named(StairTurn.values, args['turn']) ??
          (old is TurnStair ? old.turn : StairTurn.left));
  return _editFloor(
      base,
      floor.id,
      (f) => f.copyWith(
          stairs: [for (final s in f.stairs) s.id == id ? stair : s]));
}

HouseDocument _setWallOverride(
    HouseDocument doc, Map<String, dynamic> args, String Function() newId) {
  final floorId = args['floorId'] as String;
  final index = _floorIndex(doc, floorId);
  final floor = doc.floors[index];
  final a = args['anchor'] as BoundaryAnchor;
  final type = args['type'] as String;
  final axes = resolveFloorAxes(doc, floorId)!;
  final chain = resolveAnchor(axes, a).chain!;
  final overrides = <WallOverride>[];
  WallOverride between(WallOverride w, String id, String start, String end) {
    final anchor = BoundaryAnchor(
        axisId: w.anchor.axisId, startAxisId: start, endAxisId: end);
    return switch (w) {
      OpenWall() => OpenWall(id: id, anchor: anchor),
      ThicknessWall() => ThicknessWall(id: id, anchor: anchor, value: w.value),
      SolidWall() =>
        SolidWall(id: id, anchor: anchor, value: w.value, height: w.height),
    };
  }

  // What the new stretch covers is cut out of the overrides already there.
  for (final w in floor.wallOverrides) {
    final c = resolveAnchor(axes, w.anchor).chain!;
    if (c.carrier.id != chain.carrier.id ||
        c.startPos >= chain.endPos ||
        chain.startPos >= c.endPos) {
      overrides.add(w);
      continue;
    }
    final left = c.startPos < chain.startPos;
    final right = c.endPos > chain.endPos;
    if (left) {
      overrides.add(between(w, w.id, w.anchor.startAxisId, a.startAxisId));
    }
    if (right) {
      overrides.add(
          between(w, left ? newId() : w.id, a.endAxisId, w.anchor.endAxisId));
    }
  }
  final explicit = floor.explicitWalls && chain.carrier.kind != 'boundary';
  if (type != 'default' || explicit) {
    final id = newId();
    overrides.add(switch (type) {
      'open' => OpenWall(id: id, anchor: a),
      _ when explicit => SolidWall(
          id: id,
          anchor: a,
          value: type == 'thickness'
              ? args['value'] as int
              : doc.defaults.innerWallThickness),
      'thickness' =>
        ThicknessWall(id: id, anchor: a, value: args['value'] as int),
      _ => throw const _Refusal('墙体类型无效'),
    });
  }
  return _editFloor(doc, floorId, (f) => f.copyWith(wallOverrides: overrides));
}

T? _named<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;

/// What to set the main entrance to; a null [id] takes it away.
class _Entrance {
  const _Entrance(this.id);
  final String? id;
}

HouseDocument _document(HouseDocument d,
        {Defaults? defaults,
        BuildingFootprint? footprint,
        AxisSystem? axes,
        List<Floor>? floors,
        Roof? roof,
        _Entrance? mainEntrance}) =>
    HouseDocument(
        meta: d.meta,
        mainEntranceOpeningId:
            mainEntrance == null ? d.mainEntranceOpeningId : mainEntrance.id,
        defaults: defaults ?? d.defaults,
        footprint: footprint ?? d.footprint,
        axes: axes ?? d.axes,
        floors: floors ?? d.floors,
        roof: roof ?? d.roof,
        extras: d.extras);

Opening _opening(Opening o,
    {String? id,
    BoundaryAnchor? anchor,
    OpeningPosition? position,
    int? width,
    int? height,
    int? sill,
    Hinge? hinge,
    OpeningSide? opensTo}) {
  final i = id ?? o.id;
  final a = anchor ?? o.anchor;
  final p = position ?? o.position;
  final w = width ?? o.width;
  final h = height ?? o.height;
  final s = sill ?? o.sill;
  return switch (o) {
    DoorOpening() => DoorOpening(
        id: i,
        anchor: a,
        position: p,
        width: w,
        height: h,
        sill: s,
        hinge: hinge ?? o.hinge,
        opensTo: opensTo ?? o.opensTo),
    WindowOpening() => WindowOpening(
        id: i, anchor: a, position: p, width: w, height: h, sill: s),
    SlidingOpening() => SlidingOpening(
        id: i, anchor: a, position: p, width: w, height: h, sill: s),
  };
}

Opening _findOpening(HouseDocument doc, String id) =>
    doc.floors.expand((f) => f.openings).firstWhere((o) => o.id == id,
        orElse: () => throw const _Refusal('找不到这个门窗', 'NOT_FOUND'));

/// [doc] with the floor [id] replaced by what [edit] makes of it.
HouseDocument _editFloor(
    HouseDocument doc, Object? id, Floor Function(Floor) edit) {
  final index = _floorIndex(doc, id);
  return _document(doc,
      floors: [...doc.floors]..[index] = edit(doc.floors[index]));
}

/// [doc] with the room [id] replaced by what [edit] makes of it.
HouseDocument _editRoom(
    HouseDocument doc, Object? id, Room Function(Room) edit) {
  for (final f in doc.floors) {
    final index = f.rooms.indexWhere((r) => r.id == id);
    if (index < 0) continue;
    return _editFloor(doc, f.id,
        (f) => f.copyWith(rooms: [...f.rooms]..[index] = edit(f.rooms[index])));
  }
  throw const _Refusal('找不到这个房间', 'NOT_FOUND');
}

/// [doc] with the opening [id] replaced by what [edit] makes of it.
HouseDocument _editOpening(
    HouseDocument doc, Object? id, Opening Function(Opening) edit) {
  for (final f in doc.floors) {
    final index = f.openings.indexWhere((o) => o.id == id);
    if (index < 0) continue;
    final next = edit(f.openings[index]);
    return _editFloor(doc, f.id,
        (f) => f.copyWith(openings: [...f.openings]..[index] = next));
  }
  throw const _Refusal('找不到这个门窗', 'NOT_FOUND');
}
