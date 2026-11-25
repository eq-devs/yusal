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
  AppAction(
    id: 'design.measure_room',
    title: const L3('测量房间净面积与最窄净宽', 'Бөлменің таза ауданы мен ең тар енін өлшеу', 'Измерить чистую площадь и минимальную ширину комнаты', 'Measure clear room area and minimum span'),
    examples: const L3('主卧的净面积是多少', 'Жатын бөлменің таза ауданы қанша?', 'Какая чистая площадь спальни?', 'Measure the bedroom'),
    params: const {'room': Param.entity('room')},
    when: _inEditor, risk: Risk.read,
    run: (ctx, args) async {
      final host = _host!;
      final id = args.id('room');
      final geometry = host.floorBase.roomsById[id];
      if (geometry == null || !host.select(id)) {
        return const ActionResult.fail(ActionCodes.unknownEntity);
      }
      return ActionResult.ok(say: {
        'clear_area_m2': (geometry.clearArea / 10000).round() / 100,
        'min_clear_span_mm': geometry.minClearSpan.round(),
      });
    },
  ),
  AppAction(
    id: 'design.locate_shared_wall',
    title: const L3('定位两个房间之间的墙段并读取轴线长度', 'Екі бөлменің ортақ қабырғасын тауып, осьтік ұзындығын өлшеу', 'Найти общую стену комнат и её длину по оси', 'Locate a shared wall and measure its axis length'),
    examples: const L3('找出厨房与客厅之间的墙', 'Асүй мен қонақ бөлменің арасындағы қабырғаны көрсет', 'Покажи стену между кухней и гостиной', 'Find the wall between kitchen and living room'),
    params: const {'a': Param.entity('room'), 'b': Param.entity('room')},
    when: _inEditor, risk: Risk.read,
    run: (ctx, args) async {
      final host = _host!;
      final walls = host.floorBase.wallsBetween(args.id('a'), args.id('b')).toList();
      if (walls.isEmpty) return const ActionResult.fail('no_shared_wall');
      final segments = [
        for (final wall in walls) {
          'axis': wall.axis.dir.name, 'axis_position_mm': wall.axis.pos,
          'start_mm': wall.start.pos, 'end_mm': wall.end.pos,
          'axis_length_mm': wall.end.pos - wall.start.pos,
        },
      ];
      if (walls.length > 1) {
        return ActionResult.fail('multiple_shared_segments', say: {'segments': segments});
      }
      host.showSharedWall(walls.single);
      return ActionResult.ok(say: segments.single);
    },
  ),
  AppAction(
    id: 'editor.view',
    title: const L3('切换平面、外观、漫游或预算', 'Жоспарды, сыртқы көріністі, ішкі көріністі немесе сметаны ашу', 'Открыть план, внешний вид, прогулку или смету', 'Open a design view'),
    examples: const L3('走进厨房看看', 'Асүйге кіріп көрейік', 'Покажи кухню изнутри', 'Walk into the kitchen'),
    params: const {'view': Param.choice(['plan','exterior','walk','budget']), 'room': Param.entity('room', optional: true)},
    when: _inEditor, risk: Risk.read,
    run: (ctx, args) async {
      final host = _host!;
      final view = args.choice('view');
      if (args.has('room')) {
        if (view != 'walk' && view != 'plan') return const ActionResult.fail(ActionCodes.badArgs);
        final id = args.id('room');
        if (!host.floorBase.roomsById.containsKey(id)) return const ActionResult.fail(ActionCodes.unknownEntity);
        if (view == 'walk') {
          host.showRoomWalk(id);
        } else {
          host.select(id);
        }
      } else {
        host.showTab(switch(view){'exterior'=>'ext','budget'=>'cost',_=>view});
      }
      return ActionResult.ok(say: {'view': view});
    },
  ),
  AppAction(
    id: 'design.preview_wall_move',
    title: const L3('预演向相邻房间借空间', 'Ортақ қабырғаны жылжытуды алдын ала көру', 'Предпросмотр переноса общей стены', 'Preview moving a shared wall'),
    examples: const L3('从客厅借三十厘米加宽厨房，客厅至少留十六平', 'Қабырғаны қонақ бөлмеге қарай 30 см жылжытып, асүйді кеңейт. Қонақ бөлмеде кемінде 16 м² қалсын', 'Расширь кухню за счёт гостиной на 30 см, оставив гостиной минимум 16 м²', 'Preview enlarging the kitchen by 300 mm'),
    params: const {'grow': Param.entity('room'), 'shrink': Param.entity('room'),
      'distance_mm': Param.integer(optional: true), 'target_area_m2': Param.number(optional: true), 'min_remaining_m2': Param.number(optional: true)},
    when: _inEditor, risk: Risk.read,
    run: (_, args) async => _host!.previewWallMove(args.id('grow'), args.id('shrink'),
      args.has('distance_mm') ? args.integer('distance_mm') : null,
      targetArea: args.has('target_area_m2') ? args.number('target_area_m2').toDouble() : null, minRemainingArea:
        args.has('min_remaining_m2') ? args.number('min_remaining_m2').toDouble() : null),
  ),
  AppAction(
    id: 'design.finish_wall_preview',
    title: const L3('按用户决定应用或取消上一轮移墙试改', 'Алдыңғы ұсынысты қолдану немесе одан бас тарту', 'Применить или отменить предложение прошлого хода', 'Apply or cancel the previous turn’s preview'),
    examples: const L3('就按刚才的预览改', 'Алдыңғы ұсынысты қолдан', 'Примени предыдущий вариант', 'Apply the previous preview'),
    params: const {'preview_id': Param.text(), 'decision': Param.choice(['apply','cancel'])},
    when: _inEditor, risk: Risk.undoable,
    run: (_, args) async => _host!.finishWallPreview(args.text('preview_id'),
      apply: args.choice('decision') == 'apply'),
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
