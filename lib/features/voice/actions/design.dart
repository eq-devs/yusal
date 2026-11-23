import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/extras_commands.dart';
import 'package:yusal/features/editor/engine/core/commands/house_layout.dart';
import 'package:yusal/features/editor/engine/core/commands/house_spec.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/model/house_wish.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/actions/houses.dart';
import 'package:yusal/features/voice/state/screen.dart';
import 'package:yusal/service/settings/settings.dart';

export 'package:yusal/features/editor/engine/core/commands/house_spec.dart'
    show roomWall;

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

  /// Selects the room, opening or piece of furniture with [id] on the
  /// floor being edited, as a tap on it would. False when it is not there.
  bool select(String id);

  /// Shows the floor with [floorId]. False when there is none.
  bool showFloor(String floorId);
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

/// Failure code when the wall asked to move is the house's outer wall.
const outerWall = 'outer_wall';

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
  if (!await _show(doc)) {
    return const ActionResult.fail(ActionCodes.notAvailable);
  }
  return ActionResult.ok(say: {
    'floors': doc.floors.length,
    'rooms': doc.floors.fold<int>(0, (n, f) => n + f.rooms.length),
    if (built.notes.isNotEmpty) 'not_built': built.notes,
    if (issues.isNotEmpty) 'issues': issues,
  });
}

/// Puts a whole house in the editor, or in a new design when no editor is
/// open. False when there is neither.
Future<bool> _show(HouseDocument doc) async {
  final host = _host;
  final library = HouseLibrary.instance;
  if (host != null) {
    host.replaceDesign(doc);
  } else if (library != null) {
    await library.addDesign(doc);
  } else {
    return false;
  }
  return true;
}

/// Failure code when no plan fits: the house is too small for the rooms
/// asked for.
const tooSmall = 'too_small';

/// Lays a whole house out from what it must have ([housePlans]) and shows
/// the plan asked for: the best one, or with `plan` one of the others.
Future<ActionResult> planWholeHouse(Args args) async {
  int whole(String name, int otherwise) =>
      args.has(name) ? args.integer(name) : otherwise;
  bool flag(String name, bool otherwise) =>
      args.has(name) ? args.flag(name) : otherwise;
  final floors = whole('floors', 1);
  final int width;
  final int depth;
  if (args.has('width_mm') && args.has('depth_mm')) {
    width = args.integer('width_mm');
    depth = args.integer('depth_mm');
  } else if (args.has('area_sqm') && floors > 0) {
    // A little wider than deep, to the half metre.
    final each = args.number('area_sqm') / floors;
    width = (math.sqrt(each * 1.2) * 2).round() * 500;
    depth = (each * 1e6 / width / 100).round() * 100;
  } else {
    return const ActionResult.fail(ActionCodes.badArgs,
        say: {'hint': 'give width_mm and depth_mm, or area_sqm'});
  }
  final bedrooms = args.integer('bedrooms');
  if (width < 4000 ||
      width > 30000 ||
      depth < 4000 ||
      depth > 30000 ||
      floors < 1 ||
      floors > 2 ||
      bedrooms < 1 ||
      bedrooms > 8) {
    return const ActionResult.fail(ActionCodes.badArgs, say: {
      'hint': 'sides 4000-30000 mm, 1 or 2 floors, 1-8 bedrooms; '
          'anything else needs design.create_house'
    });
  }
  final plans = housePlans(
      HouseBrief(
          width: width,
          depth: depth,
          floors: floors,
          bedrooms: bedrooms,
          bathrooms: whole('bathrooms', 1).clamp(1, 2),
          hall: flag('hall', true),
          boiler: flag('boiler', true),
          storage: flag('storage', false),
          dining: flag('dining', false),
          entrance: args.has('entrance') ? args.choice('entrance') : null),
      name: args.has('name')
          ? args.text('name')
          : tr3('我的房屋', 'Менің үйім', 'Мой дом'),
      timestamp: DateTime.now().toUtc().toIso8601String(),
      newId: () => const Uuid().v4(),
      names: wishRoomNames());
  if (plans.isEmpty) {
    return const ActionResult.fail(tooSmall, say: {
      'hint': 'fewer rooms, another floor or a bigger house would fit'
    });
  }
  final pick = whole('plan', 1);
  if (pick < 1 || pick > plans.length) {
    return ActionResult.fail(ActionCodes.badArgs,
        say: {'param': 'plan', 'plans': plans.length});
  }
  final plan = plans[pick - 1];
  if (!await _show(plan.document)) {
    return const ActionResult.fail(ActionCodes.notAvailable);
  }
  return ActionResult.ok(say: {
    'plan': pick,
    'plans': plans.length,
    'layout': plan.layout,
    'entrance': plan.entrance,
    'width_mm': width,
    'depth_mm': depth,
    'floors': plan.document.floors.length,
    'rooms': plan.document.floors.fold<int>(0, (n, f) => n + f.rooms.length),
  });
}

/// The plan rectangle a room's cells cover.
PlanRect _bounds(FloorBase base, String roomId) {
  final cells =
      base.owners.entries.where((e) => e.value == roomId).map((e) => e.key);
  final v = base.axes.v;
  final h = base.axes.h;
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

/// Failure code when a stair is asked about on a floor that has none.
const noStair = 'no_stair_here';

Future<ActionResult> get _noStair async => const ActionResult.fail(noStair);

/// The stair named, else the one on the floor being edited.
Stair? _stair(Args args) {
  final host = _host!;
  final floor =
      host.document.floors.firstWhere((f) => f.id == host.currentFloorId);
  if (args.has('stair')) {
    final id = args.id('stair');
    return floor.stairs.where((s) => s.id == id).firstOrNull;
  }
  return floor.stairs.firstOrNull;
}

Set<String> _rooms() => {
      for (final f in _host!.document.floors)
        for (final r in f.rooms) r.id
    };

/// Where a new room can be asked to go. The name starts with its north or
/// south part and ends with its east or west part, when it has one.
const _places = [
  'southwest',
  'south',
  'southeast',
  'west',
  'center',
  'east',
  'northwest',
  'north',
  'northeast',
];

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
    id: 'design.plan_house',
    title: const L3('按需求排出整栋房子', 'Талап бойынша үйді жоспарлау',
        'Спланировать дом по пожеланиям'),
    examples: const L3(
        '设计一个三室、十二乘十米的平房，大门朝北',
        'Үш жатын бөлмелі, он екіге он метр үй, есігі солтүстікке',
        'Дом двенадцать на десять с тремя спальнями, вход с севера'),
    params: {
      // The size: both sides, or the total floor area.
      'width_mm': const Param.integer(optional: true),
      'depth_mm': const Param.integer(optional: true),
      'area_sqm': const Param.number(optional: true),
      'floors': const Param.integer(optional: true),
      'bedrooms': const Param.integer(),
      'bathrooms': const Param.integer(optional: true),
      // The side the main entrance faces.
      'entrance':
          Param.choice([for (final f in Facing.values) f.name], optional: true),
      // Rooms to have or leave out; a hall and a boiler room unless told.
      'hall': const Param.flag(optional: true),
      'boiler': const Param.flag(optional: true),
      'storage': const Param.flag(optional: true),
      'dining': const Param.flag(optional: true),
      // Which of the plans found, 1 the best: 2 or 3 for another one.
      'plan': const Param.integer(optional: true),
      'name': const Param.text(optional: true),
    },
    when: (ctx) => _host != null || HouseLibrary.instance != null,
    risk: Risk.undoable,
    run: (ctx, args) => planWholeHouse(args),
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
      // Where in the house: a corner, the middle of a side or the centre.
      'where': const Param.choice(_places, optional: true),
      // Or the south-west corner of the room exactly.
      'x_mm': const Param.integer(optional: true),
      'y_mm': const Param.integer(optional: true),
      'w_mm': const Param.integer(),
      'd_mm': const Param.integer(),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final before = _rooms();
      final int x;
      final int y;
      if (args.has('where')) {
        final place = args.choice('where');
        final footprint = host.document.footprint;
        final free = (
          footprint.width - args.integer('w_mm'),
          footprint.depth - args.integer('d_mm')
        );
        x = place.endsWith('west')
            ? 0
            : place.endsWith('east')
                ? free.$1
                : (free.$1 / 2).round();
        y = place.startsWith('south')
            ? 0
            : place.startsWith('north')
                ? free.$2
                : (free.$2 / 2).round();
      } else if (args.has('x_mm') && args.has('y_mm')) {
        x = args.integer('x_mm');
        y = args.integer('y_mm');
      } else {
        return const ActionResult.fail(ActionCodes.badArgs,
            say: {'hint': 'give where, or x_mm and y_mm'});
      }
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
    id: 'design.copy_floor',
    title:
        const L3('照这一层再盖一层', 'Қабатты көшіріп қосу', 'Добавить этаж как этот'),
    examples: const L3('二楼和一楼一样', 'Екінші қабат біріншідей болсын',
        'Сделай второй этаж таким же, как первый'),
    params: const {'floor': Param.entity('floor', optional: true)},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design('CopyFloor', {'floorId': _floor(args)}),
  ),
  AppAction(
    id: 'design.add_stair',
    title: const L3('放一部楼梯', 'Баспалдақ қою', 'Поставить лестницу'),
    examples: const L3('在西北角放一部楼梯', 'Солтүстік-батыс бұрышқа баспалдақ қой',
        'Поставь лестницу в северо-западном углу'),
    // The rectangle the stair takes up, south-west corner and size. Left
    // out, a two-flight stair goes in the first corner where it fits.
    params: {
      'floor': const Param.entity('floor', optional: true),
      'x_mm': const Param.integer(optional: true),
      'y_mm': const Param.integer(optional: true),
      'w_mm': const Param.integer(optional: true),
      'd_mm': const Param.integer(optional: true),
      'type': Param.choice([for (final t in StairType.values) t.name],
          optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final floorId = _floor(args);
      final fp = host.document.footprint;
      final type = args.has('type')
          ? StairType.values.byName(args.choice('type'))
          : null;
      Set<String> stairs() => {
            for (final f in host.document.floors)
              for (final s in f.stairs) s.id
          };
      final before = stairs();
      final sizes = args.has('w_mm') && args.has('d_mm')
          ? [(args.integer('w_mm'), args.integer('d_mm'))]
          : const [(2400, 3600), (3600, 2400), (1200, 4800), (4800, 1200)];
      ActionResult? last;
      for (final (w, d) in sizes) {
        final spots = args.has('x_mm') && args.has('y_mm')
            ? [(args.integer('x_mm'), args.integer('y_mm'))]
            : [
                (0, 0),
                (fp.width - w, 0),
                (0, fp.depth - d),
                (fp.width - w, fp.depth - d)
              ];
        for (final (x, y) in spots) {
          last = await _design('PlaceStair', {
            'floorId': floorId,
            'left': x,
            'bottom': y,
            'right': x + w,
            'top': y + d,
            if (type != null) 'type': type,
          });
          if (last.ok) {
            return ActionResult.ok(changed: [...stairs().difference(before)]);
          }
        }
      }
      return last!;
    },
  ),
  AppAction(
    id: 'design.move_stair',
    title: const L3('挪楼梯或改大小', 'Баспалдақты жылжыту', 'Передвинуть лестницу'),
    examples: const L3('把楼梯挪到东北角', 'Баспалдақты солтүстік-шығыс бұрышқа жылжыт',
        'Передвинь лестницу в северо-восточный угол'),
    params: const {
      'stair': Param.entity('stair', optional: true),
      'x_mm': Param.integer(),
      'y_mm': Param.integer(),
      'w_mm': Param.integer(optional: true),
      'd_mm': Param.integer(optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) {
      final stair = _stair(args);
      if (stair == null) return _noStair;
      final host = _host!;
      final axes = host.floorBase.axes;
      final at = resolveRect(axes, stair.region).rect!;
      final x = args.integer('x_mm');
      final y = args.integer('y_mm');
      return _design('PlaceStair', {
        'floorId': host.currentFloorId,
        'stairId': stair.id,
        'left': x,
        'bottom': y,
        'right':
            x + (args.has('w_mm') ? args.integer('w_mm') : at.right - at.left),
        'top':
            y + (args.has('d_mm') ? args.integer('d_mm') : at.top - at.bottom),
      });
    },
  ),
  AppAction(
    id: 'design.set_stair',
    title: const L3('换楼梯样式', 'Баспалдақ түрін өзгерту', 'Сменить вид лестницы'),
    examples: const L3(
        '楼梯换成 L 型', 'Баспалдақты L тәрізді қыл', 'Сделай лестницу Г-образной'),
    params: {
      'stair': const Param.entity('stair', optional: true),
      'type': Param.choice([for (final t in StairType.values) t.name],
          optional: true),
      // The side the first step is on, and which way it turns.
      'start': Param.choice([for (final e in StairEdge.values) e.name],
          optional: true),
      'turn': Param.choice([for (final t in StairTurn.values) t.name],
          optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) {
      final stair = _stair(args);
      if (stair == null) return _noStair;
      return _design('UpdateStair', {
        'stairId': stair.id,
        if (args.has('type')) 'type': args.choice('type'),
        if (args.has('start')) 'startEdge': args.choice('start'),
        if (args.has('turn')) 'turn': args.choice('turn'),
      }, changed: [
        stair.id
      ]);
    },
  ),
  AppAction(
    id: 'design.delete_stair',
    title: const L3('拆掉楼梯', 'Баспалдақты алып тастау', 'Убрать лестницу'),
    examples: const L3('把楼梯删掉', 'Баспалдақты алып таста', 'Убери лестницу'),
    params: const {'stair': Param.entity('stair', optional: true)},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) {
      final stair = _stair(args);
      if (stair == null) return _noStair;
      return _design('RemoveStair', {'stairId': stair.id});
    },
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
    id: 'design.resize_opening',
    title: const L3(
        '改门窗宽度', 'Есік-терезе енін өзгерту', 'Изменить ширину двери или окна'),
    examples: const L3('这扇窗改成一米五宽', 'Осы терезенің енін бір жарым метр қыл',
        'Сделай это окно шириной полтора метра'),
    params: const {
      'opening': Param.entity('opening'),
      'width_mm': Param.integer(),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design('ResizeOpening',
        {'openingId': args.id('opening'), 'width': args.integer('width_mm')},
        changed: [args.id('opening')]),
  ),
  AppAction(
    id: 'design.flip_door',
    title: const L3('门换个方向开', 'Есіктің ашылу жағын өзгерту',
        'Открывать дверь в другую сторону'),
    examples: const L3('这扇门朝另一边开', 'Осы есік екінші жаққа ашылсын',
        'Пусть эта дверь открывается в другую сторону'),
    params: const {'opening': Param.entity('opening')},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final door = _host!.document.floors
          .expand((f) => f.openings)
          .whereType<DoorOpening>()
          .where((o) => o.id == args.id('opening'))
          .firstOrNull;
      return _design('FlipDoor', {
        'openingId': args.id('opening'),
        if (door != null)
          'opensTo': (door.opensTo == OpeningSide.positiveSide
                  ? OpeningSide.negativeSide
                  : OpeningSide.positiveSide)
              .name,
      }, changed: [
        args.id('opening')
      ]);
    },
  ),
  AppAction(
    id: 'design.set_main_entrance',
    title: const L3('设为主入口', 'Басты кіреберіс ету', 'Сделать главным входом'),
    examples: const L3('这扇门是大门', 'Осы есік басты кіреберіс болсын',
        'Эта дверь — главный вход'),
    params: const {'opening': Param.entity('opening')},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) => _design(
        'SetMainEntrance', {'openingId': args.id('opening')},
        changed: [args.id('opening')]),
  ),
  AppAction(
    id: 'design.set_roof',
    title: const L3('换屋顶样式', 'Шатыр түрін өзгерту', 'Изменить тип крыши'),
    examples: const L3(
        '屋顶改成四坡的', 'Шатырды төрт еңісті қыл', 'Сделай крышу четырёхскатной'),
    params: {
      // flat, gable (two slopes) or hip (four slopes).
      'type': Param.choice([for (final t in RoofType.values) t.name]),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) {
      final roof = _host!.document.roof;
      final sloped = {
        'pitchDeg': roof.pitchDeg ?? 30,
        'overhang': roof.overhang ?? 500
      };
      return _design('SetRoof', {
        'roof': switch (RoofType.values.byName(args.choice('type'))) {
          RoofType.flat => {
              'type': 'flat',
              'parapetHeight': roof.parapetHeight ?? 900
            },
          RoofType.hip => {'type': 'hip', ...sloped},
          RoofType.gable => {
              'type': 'gable',
              'ridgeDir': roof.ridgeDir?.name ?? 'H',
              ...sloped
            },
        }
      });
    },
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
    id: 'design.resize_room',
    title:
        const L3('改房间大小', 'Бөлме өлшемін өзгерту', 'Изменить размер комнаты'),
    examples: const L3(
        '把主卧往东加宽到四米',
        'Жатын бөлмені шығысқа қарай төрт метрге кеңейт',
        'Расширь спальню на восток до четырёх метров'),
    params: {
      'room': const Param.entity('room'),
      // The wall that moves; the opposite one stays. The whole wall line
      // moves, so the rooms on its other side change by as much.
      'side': Param.choice([for (final f in Facing.values) f.name]),
      // The room's new size across that wall.
      'size_mm': const Param.integer(optional: true),
      // Or how much bigger it gets across that wall; negative for smaller.
      'by_mm': const Param.integer(optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      if (args.has('size_mm') == args.has('by_mm')) {
        return const ActionResult.fail(ActionCodes.badArgs,
            say: {'hint': 'give size_mm or by_mm'});
      }
      final host = _host!;
      final base = host.floorBase;
      final id = args.id('room');
      final spot = roomWall(base, id, Facing.values.byName(args.choice('side')),
          host.document.footprint.northAngleDeg);
      if (spot == null) return const ActionResult.fail(noWallThere);
      final axis = spot.wall.axis;
      if (axis.kind == 'boundary') {
        return const ActionResult.fail(outerWall,
            say: {'hint': 'design.set_size changes the size of the house'});
      }
      final r = _bounds(base, id);
      final (low, high) =
          axis.dir == AxisDir.V ? (r.left, r.right) : (r.bottom, r.top);
      final size = args.has('size_mm')
          ? args.integer('size_mm')
          : high - low + args.integer('by_mm');
      // Rooms the wall line bounds on either side change with it.
      final touched = {
        for (final e in base.edges)
          if (e.axis.id == axis.id)
            for (final cell in [e.negative, e.positive])
              if (cell != null) base.owners[cell]
      }.whereType<String>();
      return _design('MoveAxis', {
        'axisId': axis.id,
        'pos': (axis.pos == high ? low + size : high - size).round(),
      }, changed: [
        id,
        ...touched.where((room) => room != id)
      ]);
    },
  ),
  AppAction(
    id: 'design.swap_rooms',
    title: const L3(
        '交换两个房间', 'Екі бөлмені ауыстыру', 'Поменять две комнаты местами'),
    examples: const L3('把厨房和书房对调', 'Асхана мен кабинетті ауыстыр',
        'Поменяй местами кухню и кабинет'),
    // The two rooms trade their use and name; walls, doors and windows
    // stay where they are.
    params: const {'a': Param.entity('room'), 'b': Param.entity('room')},
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final rooms = {
        for (final f in host.document.floors)
          for (final r in f.rooms) r.id: r
      };
      final a = rooms[args.id('a')];
      final b = rooms[args.id('b')];
      if (a == null || b == null || a.id == b.id) {
        return ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': a == null ? 'a' : 'b'});
      }
      for (final (to, from) in [(a, b), (b, a)]) {
        host
          ..runDesign('SetRoomType', {'roomId': to.id, 'value': from.type})
          ..runDesign('RenameRoom', {'roomId': to.id, 'value': from.name});
      }
      return ActionResult.ok(changed: [a.id, b.id]);
    },
  ),
  AppAction(
    id: 'design.move_opening',
    title:
        const L3('移动门窗', 'Есік-терезені жылжыту', 'Передвинуть дверь или окно'),
    examples: const L3('这扇窗往东移半米', 'Осы терезені шығысқа жарты метр жылжыт',
        'Передвинь это окно на полметра к востоку'),
    params: {
      'opening': const Param.entity('opening'),
      // Along its wall: to the east or north when positive, to the west
      // or south when negative.
      'shift_mm': const Param.integer(optional: true),
      // Or the same as a direction and a distance; the direction has to
      // run along the wall.
      'toward':
          Param.choice([for (final f in Facing.values) f.name], optional: true),
      'by_mm': const Param.integer(optional: true),
      // Or to the middle of another wall: the side of a room.
      'room': const Param.entity('room', optional: true),
      'side':
          Param.choice([for (final f in Facing.values) f.name], optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final id = args.id('opening');
      final floor = deriveHouse(host.document)
          .floors
          .where((f) => f.openings.any((p) => p.opening.id == id))
          .firstOrNull;
      final placed =
          floor?.openings.where((p) => p.opening.id == id).firstOrNull;
      if (placed == null) {
        return const ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': 'opening'});
      }
      final width = placed.opening.width;
      final WallSegment wall;
      final double start;
      if (args.has('room') && args.has('side')) {
        final spot = roomWall(
            floor!.base,
            args.id('room'),
            Facing.values.byName(args.choice('side')),
            host.document.footprint.northAngleDeg);
        if (spot == null) return const ActionResult.fail(noWallThere);
        wall = spot.wall;
        start = (spot.from + spot.to) / 2 - width / 2;
      } else if (args.has('shift_mm') && placed.host != null) {
        wall = placed.host!;
        start = placed.start + args.integer('shift_mm');
      } else if (args.has('toward') &&
          args.has('by_mm') &&
          placed.host != null) {
        wall = placed.host!;
        // Along a wall, positions grow to the north or to the east.
        final (forward, back) = wall.axis.dir == AxisDir.V
            ? (Facing.north, Facing.south)
            : (Facing.east, Facing.west);
        final toward = Facing.values.byName(args.choice('toward'));
        if (toward != forward && toward != back) {
          return ActionResult.fail(ActionCodes.badArgs,
              say: {'hint': 'this wall runs ${back.name} to ${forward.name}'});
        }
        final by = args.integer('by_mm');
        start = placed.start + (toward == forward ? by : -by);
      } else {
        return const ActionResult.fail(ActionCodes.badArgs, say: {
          'hint': 'give toward and by_mm, or shift_mm, or room and side'
        });
      }
      if (start < wall.start.pos || start + width > wall.end.pos) {
        return ActionResult.fail(ActionCodes.badArgs, say: {
          'hint': 'the wall runs from ${wall.start.pos} to ${wall.end.pos}'
              ' and the opening is $width wide',
          'at': placed.start.round(),
        });
      }
      return _design('MoveOpening', {
        'openingId': id,
        'anchor': wall.ref.anchor,
        'position': {
          'type': 'fromStart',
          'd': (start - wall.start.pos).round()
        },
      }, changed: [
        id
      ]);
    },
  ),
  AppAction(
    id: 'design.move_furniture',
    title: const L3('移动家具', 'Жиһазды жылжыту', 'Передвинуть мебель'),
    examples: const L3('把床往北挪一米', 'Төсекті солтүстікке бір метр жылжыт',
        'Передвинь кровать на метр к северу'),
    params: const {
      'furniture': Param.entity('furniture'),
      // On the plan; negative is west or south.
      'east_mm': Param.integer(optional: true),
      'north_mm': Param.integer(optional: true),
      // Or a direction and a distance.
      'toward':
          Param.choice(['north', 'east', 'south', 'west'], optional: true),
      'by_mm': Param.integer(optional: true),
      // A quarter turn where it stands.
      'turn': Param.flag(optional: true),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final id = args.id('furniture');
      final item =
          host.document.extras.furniture.where((f) => f.id == id).firstOrNull;
      if (item == null) {
        return const ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': 'furniture'});
      }
      if (args.has('turn') && args.flag('turn')) {
        final turned = await _design('RotateFurniture', {'furnitureId': id});
        if (!turned.ok) return turned;
      }
      var east = args.has('east_mm') ? args.integer('east_mm') : 0;
      var north = args.has('north_mm') ? args.integer('north_mm') : 0;
      if (args.has('toward') && args.has('by_mm')) {
        final by = args.integer('by_mm');
        switch (args.choice('toward')) {
          case 'north':
            north += by;
          case 'south':
            north -= by;
          case 'east':
            east += by;
          case 'west':
            east -= by;
        }
      }
      if (east == 0 && north == 0) return ActionResult.ok(changed: [id]);
      final now = host.document.extras.furniture.firstWhere((f) => f.id == id);
      return _design('UpdateFurniture', {
        'furnitureId': id,
        'x': now.x + east,
        'y': now.y + north,
      }, changed: [
        id
      ]);
    },
  ),
  AppAction(
    id: 'editor.select',
    title: const L3('选中并显示', 'Таңдап көрсету', 'Выбрать и показать'),
    examples: const L3(
        '哪个是主卧，指给我看', 'Жатын бөлме қайсы, көрсет', 'Покажи, где спальня'),
    // One of the three: what to select on the plan.
    params: const {
      'room': Param.entity('room', optional: true),
      'opening': Param.entity('opening', optional: true),
      'furniture': Param.entity('furniture', optional: true),
    },
    when: _inEditor,
    risk: Risk.read,
    run: (ctx, args) async {
      for (final kind in ['room', 'opening', 'furniture']) {
        if (!args.has(kind)) continue;
        return _host!.select(args.id(kind))
            ? ActionResult.ok(changed: [args.id(kind)])
            : ActionResult.fail(ActionCodes.unknownEntity,
                say: {'param': kind});
      }
      return const ActionResult.fail(ActionCodes.badArgs);
    },
  ),
  AppAction(
    id: 'editor.show_floor',
    title: const L3('切换楼层', 'Қабатты ауыстыру', 'Перейти на этаж'),
    examples: const L3('看二楼', 'Екінші қабатты көрсет', 'Покажи второй этаж'),
    params: const {'floor': Param.entity('floor')},
    when: _inEditor,
    risk: Risk.read,
    run: (ctx, args) async => _host!.showFloor(args.id('floor'))
        ? const ActionResult.ok()
        : const ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': 'floor'}),
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
