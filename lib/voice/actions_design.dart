import 'dart:math' as math;

import '../core/analysis/house_analysis.dart';
import '../core/commands/extras_commands.dart';
import '../core/geometry/floor_base.dart';
import '../core/house_core.dart';
import 'action.dart';
import 'screen.dart';

/// Implemented by the design editor so design actions can reach it.
abstract interface class DesignHost {
  /// The floor being edited.
  String get currentFloorId;

  HouseDocument get document;

  /// Geometry of the floor being edited.
  FloorBase get floorBase;

  /// Runs a design command without showing its failure: the caller
  /// reports it.
  CommandResult runDesign(String kind, Map<String, dynamic> args);

  /// False when there is nothing to undo.
  bool undoDesign();
}

/// Failure code of a command that needs the user to choose how to go on.
const needsResolution = 'needs_resolution';

DesignHost? get _host {
  final Object? screen = VoiceScreens.current;
  return screen is DesignHost ? screen : null;
}

bool _inEditor(ActionContext ctx) => _host != null;

Future<ActionResult> _design(String kind, Map<String, dynamic> args,
    {List<String> changed = const []}) async {
  final host = _host;
  if (host == null) return const ActionResult.fail(ActionCodes.notAvailable);
  return switch (host.runDesign(kind, args)) {
    Applied() => ActionResult.ok(changed: changed),
    Rejected(:final reason, :final message) =>
      ActionResult.fail(reason, say: {'message': message}),
    NeedsResolution(:final conflict) => ActionResult.fail(needsResolution,
        say: {'message': conflict.message, 'choices': conflict.choices}),
  };
}

String _floor(Args args) =>
    args.has('floor') ? args.id('floor') : _host!.currentFloorId;

/// Where a new opening goes: the wall of [roomId] that faces [side], and
/// the middle of the room's stretch of it. Null when the room has no wall
/// on that side.
({WallSegment wall, double tapT})? roomWall(
    FloorBase base, String roomId, Facing side, int northAngleDeg) {
  final a = northAngleDeg * math.pi / 180;
  ({WallSegment wall, double from, double to})? best;
  for (final wall in base.wallSegments) {
    double? from, to;
    for (final e in wall.edges) {
      final inNegative =
              e.negative != null && base.owners[e.negative] == roomId,
          inPositive = e.positive != null && base.owners[e.positive] == roomId;
      if (inNegative == inPositive) continue;
      // Out of the room, in plan coordinates; north is (sin a, cos a).
      final sign = inNegative ? 1.0 : -1.0;
      final (dx, dy) = e.axis.dir == AxisDir.V ? (sign, 0.0) : (0.0, sign);
      final dn = dx * math.sin(a) + dy * math.cos(a),
          de = dx * math.cos(a) - dy * math.sin(a);
      final facing = dn.abs() >= de.abs()
          ? (dn >= 0 ? Facing.north : Facing.south)
          : (de >= 0 ? Facing.east : Facing.west);
      if (facing != side) continue;
      from = math.min(from ?? e.start.pos.toDouble(), e.start.pos.toDouble());
      to = math.max(to ?? e.end.pos.toDouble(), e.end.pos.toDouble());
    }
    if (from == null || to == null) continue;
    if (best == null || to - from > best.to - best.from) {
      best = (wall: wall, from: from, to: to);
    }
  }
  if (best == null) return null;
  return (
    wall: best.wall,
    tapT: (best.from + best.to) / 2 - best.wall.start.pos
  );
}

/// Failure code when a room has no wall on the side asked for.
const noWallThere = 'no_wall_on_that_side';

/// Design commands that map one to one onto a spoken request. Lengths
/// are millimetres, as in the document.
final designActions = [
  AppAction(
    id: 'design.add_floor',
    title: const L3('加一层楼', 'Қабат қосу', 'Добавить этаж'),
    examples: const L3('加一层楼', 'Бір қабат қос', 'Добавь этаж'),
    params: const {'floor': Param.entity('floor', optional: true)},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design('AddFloor', {'floorId': _floor(args)}),
  ),
  AppAction(
    id: 'design.set_floor_height',
    title: const L3('改层高', 'Қабат биіктігін өзгерту', 'Изменить высоту этажа'),
    examples: const L3('层高改成三米', 'Қабат биіктігін үш метр қыл',
        'Сделай высоту этажа три метра'),
    params: const {
      'floor': Param.entity('floor', optional: true),
      'height_mm': Param.integer(),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) {
      final floor = _floor(args);
      return _design('SetFloorHeight',
          {'floorId': floor, 'value': args.integer('height_mm')},
          changed: [floor]);
    },
  ),
  AppAction(
    id: 'design.set_size',
    title: const L3('改房屋尺寸', 'Үй өлшемін өзгерту', 'Изменить размер дома'),
    examples: const L3('房子改成十米乘十二米', 'Үйді он да он екі метр қыл',
        'Сделай дом десять на двенадцать метров'),
    params: const {
      'width_mm': Param.integer(optional: true),
      'depth_mm': Param.integer(optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design('SetFootprintSize', {
      if (args.has('width_mm')) 'width': args.integer('width_mm'),
      if (args.has('depth_mm')) 'depth': args.integer('depth_mm'),
    }),
  ),
  AppAction(
    id: 'design.rename_room',
    title: const L3('给房间改名', 'Бөлме атауын өзгерту', 'Переименовать комнату'),
    examples: const L3(
        '这间叫书房', 'Бұл бөлмені кабинет деп ата', 'Назови эту комнату кабинетом'),
    params: const {'room': Param.entity('room'), 'name': Param.text()},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design(
        'RenameRoom', {'roomId': args.id('room'), 'value': args.text('name')},
        changed: [args.id('room')]),
  ),
  AppAction(
    id: 'design.set_room_type',
    title: const L3('改房间用途', 'Бөлме түрін өзгерту', 'Изменить тип комнаты'),
    examples: const L3(
        '这间改成卧室', 'Бұл бөлмені жатын бөлме қыл', 'Сделай эту комнату спальней'),
    params: {
      'room': const Param.entity('room'),
      'type': Param.choice([for (final t in RoomType.values) t.name]),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design('SetRoomType', {
      'roomId': args.id('room'),
      'value': RoomType.values.byName(args.choice('type'))
    }, changed: [
      args.id('room')
    ]),
  ),
  AppAction(
    id: 'design.merge_rooms',
    title:
        const L3('合并两个房间', 'Екі бөлмені біріктіру', 'Объединить две комнаты'),
    examples: const L3('把客厅和餐厅合并', 'Қонақ бөлме мен асхананы біріктір',
        'Объедини гостиную и столовую'),
    params: const {'a': Param.entity('room'), 'b': Param.entity('room')},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design(
        'MergeRooms', {'roomIdA': args.id('a'), 'roomIdB': args.id('b')},
        changed: [args.id('a'), args.id('b')]),
  ),
  AppAction(
    id: 'design.add_opening',
    title: const L3('加门或窗', 'Есік не терезе қосу', 'Добавить дверь или окно'),
    examples: const L3(
        '客厅北墙加一扇窗',
        'Қонақ бөлменің солтүстік қабырғасына терезе қой',
        'Добавь окно на северную стену гостиной'),
    params: {
      'room': const Param.entity('room'),
      'side': Param.choice([for (final f in Facing.values) f.name]),
      'kind': Param.choice([for (final k in OpeningKind.values) k.name]),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final spot = roomWall(
          host.floorBase,
          args.id('room'),
          Facing.values.byName(args.choice('side')),
          host.document.footprint.northAngleDeg);
      if (spot == null) return const ActionResult.fail(noWallThere);
      Set<String> openings() => {
            for (final f in host.document.floors)
              for (final o in f.openings) o.id
          };
      final before = openings();
      final result = await _design('AddOpening', {
        'floorId': host.currentFloorId,
        'anchor': spot.wall.ref.anchor,
        'kind': OpeningKind.values.byName(args.choice('kind')),
        'centerAtTap': true,
        'tapT': spot.tapT,
      });
      return result.ok
          ? ActionResult.ok(changed: [...openings().difference(before)])
          : result;
    },
  ),
  AppAction(
    id: 'design.delete_opening',
    title: const L3('删除门窗', 'Есік-терезені жою', 'Удалить дверь или окно'),
    examples: const L3('删掉这扇窗', 'Осы терезені алып таста', 'Удали это окно'),
    params: const {'opening': Param.entity('opening')},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) =>
        _design('DeleteOpening', {'openingId': args.id('opening')}),
  ),
  AppAction(
    id: 'design.add_furniture',
    title: const L3('放家具', 'Жиһаз қою', 'Поставить мебель'),
    examples: const L3('卧室放一张双人床', 'Жатын бөлмеге екі кісілік төсек қой',
        'Поставь в спальню двуспальную кровать'),
    params: {
      'room': const Param.entity('room'),
      'kind': Param.choice([for (final k in FurnitureKind.values) k.name]),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final room = host.floorBase.roomGeometry
          .where((g) => g.id == args.id('room'))
          .firstOrNull;
      if (room == null) {
        return const ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': 'room'});
      }
      final kind = FurnitureKind.values.byName(args.choice('kind'));
      final (width, depth, _, _) = furnitureDefaults[kind]!;
      int snap(double v) => (v / 50).round() * 50;
      Set<String> furniture() =>
          {for (final f in host.document.extras.furniture) f.id};
      final before = furniture();
      // In the middle of the room's clear space, as a tap there would.
      final result = await _design('AddFurniture', {
        'floorId': host.currentFloorId,
        'kind': kind,
        'x': snap(room.labelAnchor.x - width / 2),
        'y': snap(room.labelAnchor.y - depth / 2),
      });
      return result.ok
          ? ActionResult.ok(changed: [...furniture().difference(before)])
          : result;
    },
  ),
  AppAction(
    id: 'design.delete_furniture',
    title: const L3('删除家具', 'Жиһазды жою', 'Удалить мебель'),
    examples: const L3('删掉这个柜子', 'Осы шкафты алып таста', 'Убери этот шкаф'),
    params: const {'furniture': Param.entity('furniture')},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) =>
        _design('DeleteFurniture', {'furnitureId': args.id('furniture')}),
  ),
  AppAction(
    id: 'editor.undo',
    title: const L3('撤销', 'Болдырмау', 'Отменить'),
    examples: const L3('撤销', 'Соңғы әрекетті болдырма', 'Отмени'),
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      return (_host?.undoDesign() ?? false)
          ? const ActionResult.ok()
          : const ActionResult.fail(ActionCodes.notAvailable);
    },
  ),
];
