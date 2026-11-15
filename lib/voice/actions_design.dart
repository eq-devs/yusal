import 'package:uuid/uuid.dart';

import '../core/analysis/house_analysis.dart';
import '../core/checks/check_engine.dart';
import '../core/commands/extras_commands.dart';
import '../core/commands/house_spec.dart';
import '../core/geometry/derived_house.dart';
import '../core/geometry/floor_base.dart';
import '../core/house_core.dart';
import 'action.dart';
import 'actions_houses.dart';
import 'screen.dart';

export '../core/commands/house_spec.dart' show roomWall;

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

  /// Between these, every change undoes as one step.
  void beginUndoGroup();
  void endUndoGroup();

  /// Puts [doc]'s design in place of the current one, as one undoable
  /// change. The design keeps its name and file.
  void replaceDesign(HouseDocument doc);

  /// Writes unsaved changes now, before the editor is closed.
  Future<void> saveNow();
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

/// Failure code when a room has no wall on the side asked for.
const noWallThere = 'no_wall_on_that_side';

/// Failure code of a house spec that cannot be built; `say.errors` lists
/// what to fix.
const badSpec = 'bad_spec';

/// Builds a whole house from the language model's spec, checks it with
/// the design rules and puts it in the editor, or in a new design when no
/// editor is open. The rule findings go back so the model can correct
/// the spec and call again.
Future<ActionResult> designWholeHouse(Map<String, Object?> spec) async {
  final built = buildHouseFromSpec(
      spec, DateTime.now().toUtc().toIso8601String(), () => const Uuid().v4());
  final doc = built.document;
  if (doc == null) {
    return ActionResult.fail(badSpec, say: {'errors': built.errors});
  }
  final issues = [
    for (final c in runChecks(doc, deriveHouse(doc)))
      if (c.level != 'info') '${c.ruleId} ${c.level}: ${c.message}'
  ];
  final host = _host, library = HouseLibrary.instance;
  if (host != null) {
    host.replaceDesign(doc);
  } else if (library != null) {
    await library.addDesign(doc);
  } else {
    return const ActionResult.fail(ActionCodes.notAvailable);
  }
  return ActionResult.ok(say: {
    'floors': doc.floors.length,
    'rooms': doc.floors.fold<int>(0, (n, f) => n + f.rooms.length),
    if (built.notes.isNotEmpty) 'not_built': built.notes,
    if (issues.isNotEmpty) 'issues': issues,
  });
}

/// The plan rectangle a room's cells cover.
PlanRect _bounds(FloorBase base, String roomId) {
  final cells =
      base.owners.entries.where((e) => e.value == roomId).map((e) => e.key);
  final v = base.axes.v, h = base.axes.h;
  return PlanRect(
      cells.map((c) => v[c.i].pos).reduce((a, b) => a < b ? a : b).toDouble(),
      cells.map((c) => h[c.j].pos).reduce((a, b) => a < b ? a : b).toDouble(),
      cells
          .map((c) => v[c.i + 1].pos)
          .reduce((a, b) => a > b ? a : b)
          .toDouble(),
      cells
          .map((c) => h[c.j + 1].pos)
          .reduce((a, b) => a > b ? a : b)
          .toDouble());
}

Set<String> _rooms() => {
      for (final f in _host!.document.floors)
        for (final r in f.rooms) r.id
    };

/// Design commands that map one to one onto a spoken request. Lengths
/// are millimetres, as in the document.
final designActions = [
  AppAction(
    id: 'design.create_house',
    title: const L3('设计整栋房子', 'Бүкіл үйді жобалау', 'Спроектировать весь дом'),
    examples: const L3(
        '设计一个三室一厅、十二乘十米的平房',
        'Үш жатын бөлмелі, он екіге он метр бір қабатты үй жобала',
        'Спроектируй одноэтажный дом двенадцать на десять с тремя спальнями'),
    params: {'spec': Param.object(houseSpecSchema())},
    when: (ctx) => _host != null || HouseLibrary.instance != null,
    risk: Risk.undoable,
    run: (ctx, args) => designWholeHouse(args.object('spec')),
  ),
  AppAction(
    id: 'design.add_room',
    title: const L3('画一个房间', 'Бөлме қосу', 'Добавить комнату'),
    examples: const L3(
        '在西南角画一个三乘四米的卧室',
        'Оңтүстік-батыс бұрышқа үшке төрт метр жатын бөлме қос',
        'Добавь спальню три на четыре метра в юго-западном углу'),
    params: {
      'type': Param.choice([for (final t in RoomType.values) t.name]),
      'name': const Param.text(optional: true),
      'x_mm': const Param.integer(),
      'y_mm': const Param.integer(),
      'w_mm': const Param.integer(),
      'd_mm': const Param.integer(),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final before = _rooms();
      final x = args.integer('x_mm'), y = args.integer('y_mm');
      final result = await _design('CarveRoom', {
        'floorId': host.currentFloorId,
        'left': x,
        'bottom': y,
        'right': x + args.integer('w_mm'),
        'top': y + args.integer('d_mm'),
        'roomType': RoomType.values.byName(args.choice('type')),
      });
      if (!result.ok) return result;
      final added = _rooms().difference(before);
      if (args.has('name') && added.length == 1) {
        host.runDesign(
            'RenameRoom', {'roomId': added.single, 'value': args.text('name')});
      }
      return ActionResult.ok(changed: [...added]);
    },
  ),
  AppAction(
    id: 'design.split_room',
    title:
        const L3('把房间分成两间', 'Бөлмені екіге бөлу', 'Разделить комнату на две'),
    examples: const L3(
        '把这间从中间隔开', 'Бұл бөлмені ортасынан бөл', 'Раздели эту комнату пополам'),
    params: {
      'room': const Param.entity('room'),
      // Which way the new wall runs.
      'wall': const Param.choice(['north_south', 'east_west']),
      // From the room's west edge (north_south) or south edge (east_west);
      // the middle when left out.
      'at_mm': const Param.integer(optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final base = host.floorBase;
      final id = args.id('room');
      final room = base.roomGeometry.where((g) => g.id == id).firstOrNull;
      if (room == null) {
        return const ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': 'room'});
      }
      final r = _bounds(base, id);
      final across = args.choice('wall') == 'north_south';
      final (low, high) = across ? (r.left, r.right) : (r.bottom, r.top);
      final pos =
          (args.has('at_mm') ? low + args.integer('at_mm') : (low + high) / 2)
              .round();
      if (pos <= low || pos >= high) {
        return const ActionResult.fail(ActionCodes.badArgs,
            say: {'param': 'at_mm'});
      }
      final before = _rooms();
      final result = await _design('SplitSpace', {
        'floorId': host.currentFloorId,
        'dir': across ? AxisDir.V : AxisDir.H,
        'pos': pos,
        'x': room.labelAnchor.x.round(),
        'y': room.labelAnchor.y.round(),
      });
      return result.ok
          ? ActionResult.ok(changed: [id, ..._rooms().difference(before)])
          : result;
    },
  ),
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
    id: 'design.mirror',
    title: const L3('把房子翻过来', 'Үйді айнадай аудару', 'Отразить дом зеркально'),
    examples: const L3('把整个房子左右翻过来', 'Бүкіл үйді оңнан солға аудар',
        'Отрази весь дом слева направо'),
    params: const {
      // left_right swaps west and east on the plan; top_bottom swaps
      // the front and the back.
      'direction': Param.choice(['left_right', 'top_bottom']),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design('MirrorPlan', {
      'direction':
          args.choice('direction') == 'top_bottom' ? 'vertical' : 'horizontal'
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
