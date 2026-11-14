import '../core/house_core.dart';
import 'action.dart';
import 'screen.dart';

/// Implemented by the design editor so design actions can reach it.
abstract interface class DesignHost {
  /// The floor being edited.
  String get currentFloorId;

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
