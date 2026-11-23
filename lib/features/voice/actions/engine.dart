import 'package:yusal/features/editor/engine/core/commands/command_catalog.dart';
import 'package:yusal/features/editor/engine/core/commands/object_catalog.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/session/engine_session.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/state/screen.dart';

/// The whole design engine for the assistant: any of its commands by name,
/// and the facts to choose arguments from. The actions in design.dart stay
/// the first choice for what they cover, since they take a room by what
/// the user calls it; these reach everything else.

DesignHost? get _host {
  final Object? screen = VoiceScreens.current;
  return screen is DesignHost ? screen : null;
}

bool _inEditor(ActionContext ctx) => _host != null;

/// Failure code of an engine command whose arguments cannot be read;
/// `say.parameters` is the schema to write them by.
const badCommandArguments = 'bad_command_arguments';

/// [arguments] with every alias from the screen ("r1") put back to the id
/// it stands for, where an argument names something by id.
Map<String, Object?> _withIds(
    ActionContext ctx, Map<String, Object?> arguments) {
  final ids = {for (final e in ctx.entities) e.alias: e.id};
  Object? id(Object? v) => v is String ? ids[v] ?? v : v;
  return {
    for (final MapEntry(:key, :value) in arguments.entries)
      key: key.endsWith('Id') || key == 'roomIdA' || key == 'roomIdB'
          ? id(value)
          : key == 'floorIds' && value is List
              ? [for (final v in value) id(v)]
              : value
  };
}

final engineActions = <AppAction>[
  AppAction(
    id: 'design.command',
    title: const L3('执行设计引擎命令', 'Жоба қозғалтқышының пәрменін орындау',
        'Выполнить команду движка проекта', 'Run a design engine command', ky: 'Долбоор кыймылдаткычынын буйругун аткаруу', uz: 'Loyiha dvigateli buyrugʻini bajarish'),
    examples: const L3(
        '在这层加一个插座', 'Осы қабатқа розетка қос', 'Добавь розетку на этом этаже', 'Add a socket on this floor', ky: 'Бул кабатка розетка кош', uz: 'Bu qavatga rozetka qoʻsh'),
    params: {
      'kind': Param.choice([for (final c in commandCatalog) c.kind]),
      // Written by the command's schema in docs/engine_commands.json; ids
      // come from design.describe, or are aliases from the screen.
      'arguments': const Param.object({'type': 'object'}),
    },
    when: _inEditor,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final host = _host!;
      final spec = commandSpec(args.choice('kind'))!;
      final Map<String, dynamic> decoded;
      try {
        decoded =
            decodeArguments(spec, _withIds(ctx, args.object('arguments')));
      } on BadArgument catch (e) {
        return ActionResult.fail(badCommandArguments, say: {
          'message': e.toString(),
          'parameters': spec.toJson()['parameters'],
        });
      }
      final before = _ids(host.document);
      return switch (host.runDesign(spec.kind, decoded)) {
        Applied() => ActionResult.ok(
            changed: _ids(host.document).difference(before).toList(),
            say: {'created': _ids(host.document).difference(before).toList()}),
        Rejected(:final reason, :final message) =>
          ActionResult.fail(reason, say: {'message': message}),
        NeedsResolution(:final conflict) => ActionResult.fail(needsResolution,
            say: {'message': conflict.message, 'choices': conflict.choices}),
      };
    },
  ),
  AppAction(
    id: 'design.describe',
    title: const L3('读取房屋的结构和编号', 'Үйдің құрылымы мен нөмірлерін оқу',
        'Прочитать состав дома', "Read the house's structure and ids", ky: 'Үйдүн түзүлүшүн жана номерлерин окуу', uz: 'Uyning tuzilishi va raqamlarini oʻqish'),
    examples: const L3(
        '这层有哪些房间和门窗',
        'Бұл қабатта қандай бөлмелер мен есік-терезелер бар',
        'Какие комнаты и проёмы на этом этаже', 'Which rooms, doors and windows are on this floor', ky: 'Бул кабатта кандай бөлмөлөр, эшиктер жана терезелер бар', uz: 'Bu qavatda qanday xonalar, eshik va derazalar bor'),
    params: const {
      // The floor to describe in full; the one being edited when left out.
      'floor': Param.entity('floor', optional: true),
      // Also what the layout rules find and what the house would cost.
      'checks': Param.flag(optional: true),
      'cost': Param.flag(optional: true),
      // Also the kinds of rooms, furniture and other things there are.
      'kinds': Param.flag(optional: true),
    },
    when: _inEditor,
    risk: Risk.read,
    run: (ctx, args) async {
      final host = _host!;
      final session = EngineSession(host.document);
      final floorId =
          args.has('floor') ? args.id('floor') : host.currentFloorId;
      final alias = {for (final e in ctx.entities) e.id: e.alias};
      Map<String, Object?> named(Map<String, Object?> m) =>
          {if (alias[m['id']] != null) 'alias': alias[m['id']], ...m};
      final house = session.describe();
      return ActionResult.ok(say: {
        ...house,
        'floors': [
          for (final f
              in (house['floors']! as List).cast<Map<String, Object?>>())
            // The other floors by name only, to keep the answer short.
            if (f['id'] != floorId)
              named({'id': f['id'], 'name': f['name'], 'height': f['height']})
            else
              named({
                ...f,
                for (final part in const ['rooms', 'openings'])
                  part: [
                    for (final m
                        in (f[part]! as List).cast<Map<String, Object?>>())
                      named(m)
                  ],
              })
        ],
        'furniture': [
          for (final f in host.document.extras.furniture)
            if (f.floorId == floorId)
              named({
                'id': f.id,
                'kind': f.kind.name,
                'x': f.x,
                'y': f.y,
                'width': f.width,
                'depth': f.depth,
              })
        ],
        if (args.has('checks') && args.flag('checks'))
          'checks': session.check(),
        if (args.has('cost') && args.flag('cost')) 'cost': session.cost(),
        if (args.has('kinds') && args.flag('kinds')) 'kinds': describeObjects(),
      });
    },
  ),
];

Set<String> _ids(HouseDocument d) => {
      for (final a in d.axes.global) a.id,
      for (final a in d.axes.floor) a.id,
      for (final f in d.floors) ...[
        f.id,
        for (final r in f.rooms) r.id,
        for (final o in f.openings) o.id,
        for (final s in f.stairs) s.id,
      ],
      for (final f in d.extras.furniture) f.id,
      for (final u in d.extras.utilities) u.id,
    };
