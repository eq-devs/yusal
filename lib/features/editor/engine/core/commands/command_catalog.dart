import 'package:yusal/features/editor/engine/core/axis/axis_resolver.dart';
import 'package:yusal/features/editor/engine/core/commands/command_contract.dart';
import 'package:yusal/features/editor/engine/core/commands/outline_commands.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';

/// Every command [executeCommand] carries out, with the arguments each one
/// takes: the engine's own description of what can be asked of it.
///
/// It serves callers that cannot read the Dart source: an assistant choosing
/// a tool, a script, another process. [describeCommands] gives it as JSON
/// Schema, [decodeArguments] turns arguments written as plain JSON into the
/// Dart values the commands take, and [executeJsonCommand] does both steps
/// and runs the command.

/// An argument was missing, unknown or of the wrong shape.
class BadArgument implements Exception {
  const BadArgument(this.argument, this.message);
  final String argument;
  final String message;
  @override
  String toString() => '$argument: $message';
}

/// One kind of argument: how it is written in JSON, and how that becomes
/// the Dart value the command reads.
class ArgType {
  const ArgType(this.schema, this._decode);

  /// The JSON Schema of the value.
  final Map<String, Object?> schema;
  final Object? Function(Object? json, String at) _decode;

  /// [json] as the Dart value of this type; throws [BadArgument] naming
  /// [at] when it is not one.
  Object? decode(Object? json, String at) => _decode(json, at);
}

Never _bad(String at, String message) => throw BadArgument(at, message);

String _string(Object? v, String at) =>
    v is String ? v : _bad(at, 'expected a string');

int _integer(Object? v, String at) {
  if (v is int) return v;
  if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toInt();
  return _bad(at, 'expected a whole number');
}

Map<String, Object?> _object(Object? v, String at) => v is Map
    ? v.map((k, value) => MapEntry('$k', value))
    : _bad(at, 'expected an object');

List<Object?> _array(Object? v, String at) =>
    v is List ? v : _bad(at, 'expected an array');

void _only(Map<String, Object?> m, Set<String> known, String at) {
  for (final key in m.keys) {
    if (!known.contains(key)) _bad('$at.$key', 'unknown field');
  }
}

/// Free text.
const text = ArgType({'type': 'string'}, _string);

/// A whole number: millimetres unless the argument says otherwise.
const integer = ArgType({'type': 'integer'}, _integer);

/// A number the command rounds to a whole one.
final number = ArgType(const {'type': 'number'},
    (v, at) => v is num && v.isFinite ? v : _bad(at, 'expected a number'));

final flag = ArgType(const {'type': 'boolean'},
    (v, at) => v is bool ? v : _bad(at, 'expected true or false'));

/// The id of something in the house: [of] says of what.
ArgType reference(String of) => ArgType({
      'type': 'string',
      'description': 'id of ${of == 'axis' ? 'an' : 'a'} $of'
    }, (v, at) {
      final id = _string(v, at);
      return id.isEmpty ? _bad(at, 'expected an id') : id;
    });

/// One of [values], written by its name and handed over as the value.
ArgType choice<T extends Enum>(List<T> values) => ArgType({
      'type': 'string',
      'enum': [for (final v in values) v.name]
    }, (v, at) {
      final name = _string(v, at);
      for (final value in values) {
        if (value.name == name) return value;
      }
      return _bad(
          at, 'expected one of ${values.map((v) => v.name).join(', ')}');
    });

/// One of [values], which the command reads as the word itself.
ArgType word(List<Object> values) => ArgType(
        {'type': values.first is int ? 'integer' : 'string', 'enum': values},
        (v, at) {
      final value = values.first is int ? _integer(v, at) : v;
      return values.contains(value)
          ? value
          : _bad(at, 'expected one of ${values.join(', ')}');
    });

ArgType listOf(ArgType item) =>
    ArgType({'type': 'array', 'items': item.schema}, (v, at) {
      final list = _array(v, at);
      return [
        for (var i = 0; i < list.length; i++) item.decode(list[i], '$at[$i]')
      ];
    });

/// A stretch of a wall line: the axis it lies on and the two axes it runs
/// between.
final anchor = ArgType(const {
  'type': 'object',
  'description': 'A stretch of wall: the axis it lies on and the two '
      'crossing axes it runs between.',
  'properties': {
    'axisId': {'type': 'string'},
    'startAxisId': {'type': 'string'},
    'endAxisId': {'type': 'string'},
  },
  'required': ['axisId', 'startAxisId', 'endAxisId'],
  'additionalProperties': false,
}, (v, at) {
  final m = _object(v, at);
  _only(m, const {'axisId', 'startAxisId', 'endAxisId'}, at);
  return BoundaryAnchor(
      axisId: _string(m['axisId'], '$at.axisId'),
      startAxisId: _string(m['startAxisId'], '$at.startAxisId'),
      endAxisId: _string(m['endAxisId'], '$at.endAxisId'));
});

/// A rectangle between four axes.
final rectangle = ArgType(const {
  'type': 'object',
  'description': 'A rectangle between two vertical axes (x0, x1) and two '
      'horizontal ones (y0, y1).',
  'properties': {
    'x0': {'type': 'string'},
    'x1': {'type': 'string'},
    'y0': {'type': 'string'},
    'y1': {'type': 'string'},
  },
  'required': ['x0', 'x1', 'y0', 'y1'],
  'additionalProperties': false,
}, (v, at) {
  final m = _object(v, at);
  _only(m, const {'x0', 'x1', 'y0', 'y1'}, at);
  return AxisRectangle(
      x0: _string(m['x0'], '$at.x0'),
      x1: _string(m['x1'], '$at.x1'),
      y0: _string(m['y0'], '$at.y0'),
      y1: _string(m['y1'], '$at.y1'));
});

/// Cells of a floor's grid, each as [column, row] counted from the bottom
/// left.
final cells = ArgType(const {
  'type': 'array',
  'description': 'Grid cells as [column, row], counted from the bottom left.',
  'items': {
    'type': 'array',
    'items': {'type': 'integer'},
    'minItems': 2,
    'maxItems': 2,
  },
}, (v, at) {
  final list = _array(v, at);
  return <Cell>[
    for (var n = 0; n < list.length; n++)
      switch (_array(list[n], '$at[$n]')) {
        [final i, final j] =>
          Cell(_integer(i, '$at[$n][0]'), _integer(j, '$at[$n][1]')),
        _ => _bad('$at[$n]', 'expected [column, row]'),
      }
  ];
});

/// Where an opening sits on its stretch of wall, as a house file writes it.
final position = ArgType(const {
  'type': 'object',
  'description': 'Centred on its wall, or a distance d in millimetres from '
      'the start or the end of the wall.',
  'properties': {
    'type': {
      'type': 'string',
      'enum': ['center', 'fromStart', 'fromEnd']
    },
    'd': {'type': 'integer'},
  },
  'required': ['type'],
  'additionalProperties': false,
}, (v, at) {
  final m = _object(v, at);
  _only(m, const {'type', 'd'}, at);
  final type = _string(m['type'], '$at.type');
  return switch (type) {
    'center' when !m.containsKey('d') => <String, dynamic>{'type': type},
    'fromStart' || 'fromEnd' => <String, dynamic>{
        'type': type,
        'd': _integer(m['d'], '$at.d')
      },
    'center' => _bad('$at.d', 'a centred position takes no distance'),
    _ => _bad('$at.type', 'expected center, fromStart or fromEnd'),
  };
});

/// A roof, as a house file writes it.
final roof = ArgType(const {
  'type': 'object',
  'description': 'flat with parapetHeight; gable with ridgeDir (V or H), '
      'pitchDeg and overhang; hip with pitchDeg and overhang.',
  'properties': {
    'type': {
      'type': 'string',
      'enum': ['flat', 'gable', 'hip']
    },
    'parapetHeight': {'type': 'integer'},
    'ridgeDir': {
      'type': 'string',
      'enum': ['V', 'H']
    },
    'pitchDeg': {'type': 'integer'},
    'overhang': {'type': 'integer'},
  },
  'required': ['type'],
  'additionalProperties': false,
}, (v, at) {
  final m = _object(v, at);
  final type = _string(m['type'], '$at.type');
  final fields = switch (type) {
    'flat' => const ['parapetHeight'],
    'gable' => const ['ridgeDir', 'pitchDeg', 'overhang'],
    'hip' => const ['pitchDeg', 'overhang'],
    _ => _bad('$at.type', 'expected flat, gable or hip'),
  };
  _only(m, {'type', ...fields}, at);
  return <String, dynamic>{
    'type': type,
    for (final f in fields)
      f: f == 'ridgeDir'
          ? word(const ['V', 'H']).decode(m[f], '$at.$f')
          : _integer(m[f], '$at.$f')
  };
});

/// The layers of a wall, floor or roof build-up, outside first.
final layers = ArgType({
  'type': 'array',
  'items': {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'nameKk': {'type': 'string'},
      'thickness': {'type': 'integer'},
      'material': choice(LayerMaterial.values).schema,
      'lambda': {
        'type': 'integer',
        'description': 'thermal conductivity, thousandths of W/(m·K)'
      },
    },
    'required': ['name', 'thickness', 'material'],
    'additionalProperties': false,
  },
}, (v, at) {
  final list = _array(v, at);
  return <Layer>[
    for (var n = 0; n < list.length; n++)
      () {
        final here = '$at[$n]';
        final m = _object(list[n], here);
        _only(m, const {'name', 'nameKk', 'thickness', 'material', 'lambda'},
            here);
        final name = _string(m['name'], '$here.name');
        return Layer(
            name,
            m['nameKk'] == null ? name : _string(m['nameKk'], '$here.nameKk'),
            _integer(m['thickness'], '$here.thickness'),
            choice(LayerMaterial.values)
                .decode(m['material'], '$here.material')! as LayerMaterial,
            lambda: m['lambda'] == null
                ? null
                : _integer(m['lambda'], '$here.lambda'));
      }()
  ];
});

/// Rectangles on a plan in millimetres, each as [left, bottom, right, top].
final areas = ArgType(const {
  'type': 'array',
  'description': 'Plan rectangles as [left, bottom, right, top], millimetres.',
  'items': {
    'type': 'array',
    'items': {'type': 'integer'},
    'minItems': 4,
    'maxItems': 4,
  },
}, (v, at) {
  final list = _array(v, at);
  return <(int, int, int, int)>[
    for (var n = 0; n < list.length; n++)
      switch (_array(list[n], '$at[$n]')) {
        [final a, final b, final c, final d] => (
            _integer(a, '$at[$n][0]'),
            _integer(b, '$at[$n][1]'),
            _integer(c, '$at[$n][2]'),
            _integer(d, '$at[$n][3]')
          ),
        _ => _bad('$at[$n]', 'expected [left, bottom, right, top]'),
      }
  ];
});

/// Utility points to add in one go.
final utilityPoints = ArgType({
  'type': 'array',
  'items': {
    'type': 'object',
    'properties': {
      'kind': choice(UtilityKind.values).schema,
      'x': {'type': 'number'},
      'y': {'type': 'number'},
      'floorId': {'type': 'string'},
      'id': {'type': 'string'},
      'label': {'type': 'string'},
    },
    'required': ['kind', 'x', 'y'],
    'additionalProperties': false,
  },
}, (v, at) {
  final list = _array(v, at);
  return <Map<String, dynamic>>[
    for (var n = 0; n < list.length; n++)
      () {
        final here = '$at[$n]';
        final m = _object(list[n], here);
        _only(m, const {'kind', 'x', 'y', 'floorId', 'id', 'label'}, here);
        return <String, dynamic>{
          'kind': choice(UtilityKind.values).decode(m['kind'], '$here.kind'),
          'x': number.decode(m['x'], '$here.x'),
          'y': number.decode(m['y'], '$here.y'),
          for (final f in const ['floorId', 'id', 'label'])
            if (m[f] != null) f: _string(m[f], '$here.$f'),
        };
      }()
  ];
});

/// One argument of a command.
class CommandArgument {
  const CommandArgument(this.name, this.type,
      {this.required = false, this.nullable = false, this.note});
  final String name;
  final ArgType type;
  final bool required;

  /// Whether null is itself a value the command reads (to clear something).
  final bool nullable;
  final String? note;
}

/// One command: what it is called, what it does and what it takes.
class CommandSpec {
  const CommandSpec(this.kind, this.group, this.summary, this.arguments,
      {this.removes = false});
  final String kind;

  /// The part of the design it edits.
  final String group;
  final String summary;
  final List<CommandArgument> arguments;

  /// Whether it takes something out of the design. Every command can be
  /// undone; this marks the ones worth a second look before running.
  final bool removes;

  CommandArgument? argument(String name) {
    for (final a in arguments) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// The command as an assistant's tool: its name, what it does and the
  /// JSON Schema of its arguments.
  Map<String, Object?> toJson() => {
        'name': kind,
        'group': group,
        'summary': summary,
        'risk': removes ? 'remove' : 'edit',
        'parameters': {
          'type': 'object',
          'properties': {
            for (final a in arguments)
              a.name: {
                ...a.type.schema,
                if (a.note != null)
                  'description': [
                    if (a.type.schema['description'] != null)
                      a.type.schema['description'],
                    a.note
                  ].join(' '),
                if (a.nullable) 'type': [a.type.schema['type'], 'null'],
              }
          },
          'required': [
            for (final a in arguments)
              if (a.required) a.name
          ],
          'additionalProperties': false,
        },
      };
}

CommandArgument _need(String name, ArgType type, [String? note]) =>
    CommandArgument(name, type, required: true, note: note);
CommandArgument _may(String name, ArgType type, [String? note]) =>
    CommandArgument(name, type, note: note);

final _floor = reference('floor');
final _room = reference('room');
final _opening = reference('opening');
final _stair = reference('stair');
final _axis = reference('axis');
final _wall = reference('drawn wall');
final _confirmHosted = _may('deleteHostedObjects', flag,
    'Confirms removing the doors and windows that lose their wall.');
final _confirmStairs = _may('deleteStairs', flag,
    'Confirms removing the stairs that lose their floor.');

List<CommandArgument> _box() => [
      _need('left', integer),
      _need('bottom', integer),
      _need('right', integer),
      _need('top', integer),
    ];

const _lowWall = 'Millimetres the wall stands above the floor, 300 to 2100, '
    'for a low wall; 0 for a wall to the ceiling.';

List<CommandArgument> _line() => [
      _need('x0', integer),
      _need('y0', integer),
      _need('x1', integer),
      _need('y1', integer),
    ];

List<CommandArgument> _placed({bool size = true}) => [
      _may('x', number),
      _may('y', number),
      if (size) ...[_may('width', number), _may('depth', number)],
    ];

final List<CommandSpec> commandCatalog = List.unmodifiable([
  // ------------------------------------------------------------ house
  CommandSpec(
      'SetFootprintSize',
      'house',
      'Set the width and depth of the house.',
      [_may('width', integer), _may('depth', integer)]),
  CommandSpec(
      'SetNorthAngle', 'house', 'Set which way north points on the plan.', [
    _need('value', word(const [0, 90, 180, 270]), 'Degrees.')
  ]),
  CommandSpec('SetRoof', 'house', 'Replace the roof.', [_need('roof', roof)]),
  CommandSpec(
      'SetDefault',
      'house',
      'Set one of the default sizes new walls, floors, doors and windows take.',
      [
        _need(
            'field',
            word(const [
              'outerWallThickness',
              'innerWallThickness',
              'slabThickness',
              'stairRiserMax',
              'stairTread',
              'stairWidthMin',
              'floorHeight',
              'doorWidth',
              'doorHeight',
              'windowWidth',
              'windowHeight',
              'windowSill',
            ])),
        _need('value', integer),
      ]),
  CommandSpec('MirrorPlan', 'house',
      'Flip the whole plan left to right or top to bottom.', [
    _may('direction', word(const ['horizontal', 'vertical']))
  ]),
  CommandSpec(
      'CutOutline', 'house', 'Cut a rectangular corner off the outline.', [
    _need('corner', word(outlineCorners), 'tl, tr, bl or br.'),
    _need('width', number),
    _need('depth', number),
    _may('floorIds', listOf(_floor), 'Every floor when left out.'),
  ]),
  CommandSpec(
      'RestoreOutline',
      'house',
      'Make the outline a full rectangle again.',
      [_may('floorIds', listOf(_floor), 'Every floor when left out.')]),

  // ------------------------------------------------------------- axes
  CommandSpec('AddAxis', 'axes', 'Add a grid line.', [
    _need('dir', choice(AxisDir.values), 'V runs up the plan, H across it.'),
    _need('pos', integer),
    _may(
        'floorId', _floor, 'On this floor only; on every floor when left out.'),
  ]),
  CommandSpec(
      'MoveAxis',
      'axes',
      'Move a grid line; walls and rooms on it follow.',
      [_need('axisId', _axis), _need('pos', integer)]),
  CommandSpec(
      'PromoteFloorAxis',
      'axes',
      'Make a grid line of one floor a line of every floor.',
      [_need('axisId', _axis)]),
  CommandSpec(
      'DeleteAxis',
      'axes',
      'Remove a grid line.',
      [
        _need('axisId', _axis),
        _may(
            'resolution',
            word(const ['mergeRooms', 'keepLowSide', 'keepHighSide']),
            'What becomes of the rooms on either side.'),
        _confirmHosted,
        _confirmStairs,
      ],
      removes: true),

  // ----------------------------------------------------------- floors
  CommandSpec('AddFloor', 'floors', 'Add an empty floor above a floor.',
      [_need('floorId', _floor, 'The floor it goes above.')]),
  CommandSpec('CopyFloor', 'floors', 'Add a copy of a floor above it.',
      [_need('floorId', _floor)]),
  CommandSpec('DeleteFloor', 'floors', 'Remove a floor.',
      [_need('floorId', _floor), _confirmStairs],
      removes: true),
  CommandSpec('SetFloorHeight', 'floors', 'Set the height of a floor.',
      [_need('floorId', _floor), _need('value', integer)]),
  CommandSpec('RenameFloor', 'floors', 'Name a floor.',
      [_need('floorId', _floor), _need('value', text)]),

  // ------------------------------------------------------------ rooms
  CommandSpec('RenameRoom', 'rooms', 'Name a room.',
      [_need('roomId', _room), _need('value', text)]),
  CommandSpec('SetRoomType', 'rooms', 'Set what a room is used as.',
      [_need('roomId', _room), _need('value', choice(RoomType.values))]),
  CommandSpec('MergeRooms', 'rooms', 'Join two rooms that share a side.',
      [_need('roomIdA', _room), _need('roomIdB', _room), _confirmHosted]),
  CommandSpec('SplitSpace', 'rooms',
      'Divide the room at a point with a line across it.', [
    _need('floorId', _floor),
    _need('dir', choice(AxisDir.values)),
    _need('pos', integer, 'Where the line runs.'),
    _need('x', integer, 'A point in the room to divide.'),
    _need('y', integer),
  ]),
  CommandSpec(
      'CarveRoom', 'rooms', 'Make a room of a rectangle of the floor.', [
    _need('floorId', _floor),
    ..._box(),
    _may('roomType', choice(RoomType.values)),
  ]),
  CommandSpec(
      'PaintCells', 'rooms', 'Make a room of grid cells, or grow one.', [
    _need('floorId', _floor),
    _need('cells', cells),
    _may('roomType', choice(RoomType.values)),
  ]),
  CommandSpec('EraseCells', 'rooms', 'Take grid cells out of their rooms.',
      [_need('floorId', _floor), _need('cells', cells)],
      removes: true),
  CommandSpec(
      'SetRoomInfo', 'rooms', 'Set the note or the stated area of a room.', [
    _need('roomId', _room),
    const CommandArgument('note', text, nullable: true),
    CommandArgument('labelArea', number, nullable: true),
  ]),

  // --------------------------------------------------------- openings
  CommandSpec('AddOpening', 'openings', 'Put a door or window on a wall.', [
    _need('floorId', _floor),
    _need('anchor', anchor),
    _need('kind', choice(OpeningKind.values)),
    _need(
        'tapT', number, 'Distance along the wall, millimetres from its start.'),
    _may('centerAtTap', flag, 'Centre it there instead of at the usual place.'),
  ]),
  CommandSpec('SetOpeningKind', 'openings',
      'Turn an opening into a door or a window.', [
    _need('openingId', _opening),
    _need('kind', choice(OpeningKind.values))
  ]),
  CommandSpec(
      'ResizeOpening', 'openings', 'Set the size or sill of an opening.', [
    _need('openingId', _opening),
    _may('width', integer),
    _may('height', integer),
    _may('sill', integer),
  ]),
  CommandSpec('MoveOpening', 'openings',
      'Move an opening along its wall or to another.', [
    _need('openingId', _opening),
    _need('position', position),
    _may('anchor', anchor, 'The wall to move it to.'),
  ]),
  CommandSpec(
      'FlipDoor', 'openings', 'Change the side a door hangs on or opens to.', [
    _need('openingId', _opening),
    _may('hinge', word(const ['start', 'end'])),
    _may('opensTo', word(const ['positiveSide', 'negativeSide'])),
  ]),
  CommandSpec('DeleteOpening', 'openings', 'Remove an opening.',
      [_need('openingId', _opening)],
      removes: true),
  CommandSpec('SetMainEntrance', 'openings', 'Choose the main entrance door.', [
    CommandArgument('openingId', _opening,
        nullable: true, note: 'Null or left out for none.'),
  ]),
  CommandSpec('SetOpeningLabel', 'openings', 'Label an opening.', [
    _need('openingId', _opening),
    const CommandArgument('value', text, nullable: true)
  ]),

  // ----------------------------------------------------------- stairs
  CommandSpec('PlaceStair', 'stairs',
      'Put a stair in a rectangle of a floor, or move one.', [
    _need('floorId', _floor),
    ..._box(),
    _may('type', choice(StairType.values)),
    _may('stairId', _stair, 'The stair to move.'),
  ]),
  CommandSpec(
      'RemoveStair',
      'stairs',
      'Remove a stair and give its place back to the room.',
      [_need('stairId', _stair)],
      removes: true),
  CommandSpec(
      'AddStair', 'stairs', 'Add a stair over a rectangle of grid lines.', [
    _need('floorId', _floor),
    _need('region', rectangle),
    _need('type', choice(StairType.values)),
  ]),
  CommandSpec('UpdateStair', 'stairs', 'Change a stair.', [
    _need('stairId', _stair),
    _may('region', rectangle),
    _may('type', word(const ['straight', 'L', 'U'])),
    _may('startEdge', word(const ['bottom', 'top', 'left', 'right'])),
    _may('turn', word(const ['left', 'right'])),
  ]),
  CommandSpec(
      'DeleteStair', 'stairs', 'Remove a stair.', [_need('stairId', _stair)],
      removes: true),

  // ------------------------------------------------------------ walls
  CommandSpec('SetWallOverride', 'walls',
      'Open a stretch of wall, set its thickness, or make it usual again.', [
    _need('floorId', _floor),
    _need('anchor', anchor),
    _need('type', word(const ['default', 'open', 'thickness'])),
    _may('value', integer, 'The thickness, for type thickness.'),
  ]),
  CommandSpec(
      'MoveLocalWall', 'walls', 'Move a wall between two rooms on one floor.', [
    _need('floorId', _floor),
    _need('anchor', anchor),
    _need('pos', integer)
  ]),
  CommandSpec(
      'EnableWallDrawing',
      'walls',
      'Turn the walls of a floor into separate pieces that can be drawn and moved.',
      [_need('floorId', _floor)]),
  CommandSpec(
      'AddDrawnWall', 'walls', 'Draw a straight wall between two points.', [
    _need('floorId', _floor),
    ..._line(),
    _may('height', integer, _lowWall)
  ]),
  CommandSpec('UpdateDrawnWall', 'walls', 'Set the two ends of a drawn wall.', [
    _need('floorId', _floor),
    _may('wallId', _wall),
    _may('anchor', anchor, 'The wall by where it runs, when not by id.'),
    ..._line(),
    _may('height', integer, _lowWall),
  ]),
  CommandSpec(
      'SetDrawnWallHeight',
      'walls',
      'Make a drawn wall a low wall (a knee wall, a bar, a balustrade) or a '
          'wall to the ceiling again. A low wall divides no room and '
          'carries no door or window.',
      [
        _need('floorId', _floor),
        _may('wallId', _wall),
        _may('anchor', anchor, 'The wall by where it runs, when not by id.'),
        _need('height', integer, _lowWall),
      ]),
  CommandSpec('MoveDrawnWall', 'walls',
      'Move a drawn wall sideways; the walls ending on it follow.', [
    _need('floorId', _floor),
    _may('wallId', _wall),
    _may('anchor', anchor, 'The wall by where it runs, when not by id.'),
    _need('pos', integer),
  ]),
  CommandSpec(
      'DeleteDrawnWall',
      'walls',
      'Remove a drawn wall.',
      [
        _need('floorId', _floor),
        _may('wallId', _wall),
        _may('anchor', anchor, 'The wall by where it runs, when not by id.'),
        _confirmHosted,
      ],
      removes: true),

  // -------------------------------------------------------- furniture
  CommandSpec(
      'AddFurniture', 'furniture', 'Put a piece of furniture on a floor.', [
    _need('floorId', _floor),
    _need('kind', choice(FurnitureKind.values)),
    ..._placed(),
    _may('height', number),
    _may('elevation', number, 'Height above the floor.'),
    _may('variant', number),
    _may('label', text),
    _may('id', text, 'Its id; one is made when left out.'),
  ]),
  CommandSpec('UpdateFurniture', 'furniture',
      'Move, resize or change a piece of furniture.', [
    _need('furnitureId', reference('piece of furniture')),
    ..._placed(),
    _may('height', number),
    _may('elevation', number),
    _may('variant', number),
    _may('kind', choice(FurnitureKind.values)),
    _may('floorId', _floor),
    const CommandArgument('label', text,
        nullable: true, note: 'Null or empty clears it.'),
  ]),
  CommandSpec(
      'RotateFurniture',
      'furniture',
      'Turn a piece of furniture a quarter turn.',
      [_need('furnitureId', reference('piece of furniture'))]),
  CommandSpec('DeleteFurniture', 'furniture', 'Remove a piece of furniture.',
      [_need('furnitureId', reference('piece of furniture'))],
      removes: true),

  // ------------------------------------------------- notes and issues
  CommandSpec(
      'SetNote', 'notes', 'Set one of the notes kept with the design.', [
    _need('key', text),
    const CommandArgument('value', text, nullable: true)
  ]),
  CommandSpec('AddIssue', 'notes', 'Record something to fix or check.', [
    _need('title', text),
    _may('text', text),
    _may('level', choice(IssueLevel.values)),
    _may('floorId', _floor),
    _may('areas', areas),
    _may('id', text),
  ]),
  CommandSpec('UpdateIssue', 'notes', 'Change a recorded issue.', [
    _need('issueId', reference('issue')),
    _may('title', text),
    _may('text', text),
    _may('level', choice(IssueLevel.values)),
    _may('floorId', _floor),
    _may('areas', areas),
  ]),
  CommandSpec('DeleteIssue', 'notes', 'Remove a recorded issue.',
      [_need('issueId', reference('issue'))],
      removes: true),

  // -------------------------------------------------------- structure
  CommandSpec('SetFoundation', 'structure', 'Change the foundation.', [
    _may(
        'field',
        text,
        'A size to set with value: width, height, plinth, cushion and the '
            'reinforcement fields.'),
    _may('value', number),
    _may('type', choice(FoundationType.values),
        'Strips under the walls, one slab, or piles under beams.'),
    _may('partitions', flag, 'Whether partitions get a footing too.'),
    _may('concrete', text, 'The concrete grade.'),
    _may('reset', flag, 'Back to the usual foundation.'),
  ]),
  CommandSpec('SetLayers', 'structure',
      'Set the build-up of the walls, floors or roof.', [
    _need('group', word(const ['wall', 'floor', 'roof'])),
    _need('layers', layers)
  ]),
  CommandSpec(
      'AddSleeve', 'structure', 'Add a pipe sleeve through the foundation.', [
    _need('x', number),
    _need('y', number),
    _may('diameter', number),
    _may('kind', choice(SleeveKind.values)),
    _may('id', text),
  ]),
  CommandSpec('UpdateSleeve', 'structure', 'Change a pipe sleeve.', [
    _need('sleeveId', reference('sleeve')),
    _may('x', number),
    _may('y', number),
    _may('diameter', number),
    _may('kind', choice(SleeveKind.values)),
  ]),
  CommandSpec('DeleteSleeve', 'structure', 'Remove a pipe sleeve.',
      [_need('sleeveId', reference('sleeve'))],
      removes: true),

  // ------------------------------------------------------------- cost
  CommandSpec('SetCost', 'cost', 'Change how the estimate is worked out.', [
    _may('currency', choice(Currency.values),
        'Changing it drops the prices set.'),
    CommandArgument('labourPct', number, nullable: true),
    CommandArgument('contingencyPct', number, nullable: true),
    _may('priceKey', text, 'The price to set with price.'),
    CommandArgument('price', number,
        nullable: true, note: 'Null goes back to the example price.'),
    _may('resetPrices', flag),
    _may('outerUnit', choice(MasonryUnit.values),
        'What the outside walls are laid from.'),
    _may('innerUnit', choice(MasonryUnit.values),
        'What the inside walls are laid from.'),
    _may('labourByWork', flag,
        'Price labour per unit of work instead of as a share of materials.'),
    _may('labourKey', text, 'The labour rate to set with labourPrice.'),
    CommandArgument('labourPrice', number,
        nullable: true, note: 'Null goes back to the example rate.'),
    _may('selfStage', text,
        'A stage the family builds itself, so no labour is charged on it.'),
    _may('self', flag, 'False takes selfStage back.'),
    const CommandArgument('region', text,
        nullable: true, note: 'Where the house is built, for local prices.'),
  ]),
  CommandSpec(
      'AddCostItem', 'cost', 'Add a line of your own to the estimate.', [
    _need('name', text),
    _may('unit', text),
    _may('quantity', number, 'In hundredths.'),
    _may('price', number),
    _may('id', text),
  ]),
  CommandSpec('UpdateCostItem', 'cost', 'Change a line of your own.', [
    _need('itemId', reference('estimate line')),
    _may('name', text),
    _may('unit', text),
    _may('quantity', number),
    _may('price', number),
  ]),
  CommandSpec('DeleteCostItem', 'cost', 'Remove a line of your own.',
      [_need('itemId', reference('estimate line'))],
      removes: true),

  CommandSpec(
      'SetAreaBasis',
      'room',
      'Choose where room areas are measured to: clear is between the '
          'finished wall faces, centre to the middle of the walls, outer to '
          'the outer face of outside walls.',
      [_need('basis', choice(AreaBasis.values))]),

  // ------------------------------------------------------------- heat
  CommandSpec(
      'SetHeat', 'heat', 'Change what the heat loss is worked out from.', [
    _may(
        'field',
        word(const [
          'outdoor',
          'indoor',
          'degreeDays',
          'airChange',
          'windowU',
          'doorU',
          'efficiency',
        ]),
        'A figure to set with value.'),
    _may('value', number),
    _may('fuel', choice(FuelKind.values)),
    _may('reset', flag),
  ]),

  // -------------------------------------------------------- utilities
  CommandSpec(
      'AddUtility', 'utilities', 'Add a socket, light, tap or other point.', [
    _need('floorId', _floor),
    _need('kind', choice(UtilityKind.values)),
    _need('x', number),
    _need('y', number),
    _may('label', text),
    _may('id', text),
  ]),
  CommandSpec('AddUtilities', 'utilities', 'Add several points in one step.', [
    _need('points', utilityPoints),
    _may('floorId', _floor, 'For the points that name no floor.'),
  ]),
  CommandSpec('UpdateUtility', 'utilities', 'Move or change a point.', [
    _need('utilityId', reference('utility point')),
    _may('x', number),
    _may('y', number),
    _may('kind', choice(UtilityKind.values)),
    const CommandArgument('label', text,
        nullable: true, note: 'Null or empty clears it.'),
  ]),
  CommandSpec('DeleteUtility', 'utilities', 'Remove a point.',
      [_need('utilityId', reference('utility point'))],
      removes: true),
  CommandSpec(
      'ClearUtilities',
      'utilities',
      'Remove the points of a floor, of some kinds, or all.',
      [
        _may('floorId', _floor),
        _may('kinds', listOf(choice(UtilityKind.values))),
      ],
      removes: true),

  // ------------------------------------------------------------- site
  CommandSpec(
      'SetSite', 'site', 'Set the plot and where the house stands on it.', [
    _may('width', number),
    _may('depth', number),
    _may('houseX', number),
    _may('houseY', number),
    _may('fence', flag),
  ]),
  const CommandSpec('ClearSite', 'site', 'Remove the plot.', [], removes: true),
  CommandSpec(
      'AddSiteItem', 'site', 'Put an outbuilding or other item on the plot.', [
    _need('kind', choice(SiteKind.values)),
    ..._placed(),
    _may('label', text),
    _may('id', text),
  ]),
  CommandSpec(
      'UpdateSiteItem', 'site', 'Move, resize or change an item on the plot.', [
    _need('siteItemId', reference('plot item')),
    ..._placed(),
    _may('kind', choice(SiteKind.values)),
    const CommandArgument('label', text,
        nullable: true, note: 'Null or empty clears it.'),
  ]),
  CommandSpec(
      'RotateSiteItem',
      'site',
      'Turn an item on the plot a quarter turn.',
      [_need('siteItemId', reference('plot item'))]),
  CommandSpec('DeleteSiteItem', 'site', 'Remove an item from the plot.',
      [_need('siteItemId', reference('plot item'))],
      removes: true),

  // --------------------------------------------------------- schedule
  CommandSpec('SetStage', 'schedule', 'Change a stage of the build.', [
    _need('stageKey', text),
    const CommandArgument('start', text,
        nullable: true, note: 'A date; null or empty clears it.'),
    _may('toggleCheck', number, 'The check to tick or untick.'),
    _may('name', text),
    _may('status', choice(StageStatus.values)),
    _may('days', number),
    _may('spent', number),
    _may('note', text),
  ]),
  CommandSpec('AddStage', 'schedule', 'Add a stage of your own.', [
    _need('name', text),
    _may('after', text, 'The stage it follows; last when left out.'),
    _may('days', number),
    _may('id', text),
  ]),
  CommandSpec('DeleteStage', 'schedule', 'Remove a stage of your own.',
      [_need('stageKey', text)],
      removes: true),
  const CommandSpec(
      'ResetSchedule', 'schedule', 'Go back to the usual stages.', [],
      removes: true),
]);

final Map<String, CommandSpec> _byKind = {
  for (final c in commandCatalog) c.kind: c
};

/// The catalog entry of [kind], or null when there is no such command.
CommandSpec? commandSpec(String kind) => _byKind[kind];

/// Every command as an assistant's tool, in catalog order.
List<Map<String, Object?>> describeCommands() =>
    [for (final c in commandCatalog) c.toJson()];

/// Arguments written as plain JSON, as the Dart values command [spec]
/// reads. Throws [BadArgument] for an unknown, missing or malformed one.
Map<String, dynamic> decodeArguments(
    CommandSpec spec, Map<String, Object?> json) {
  final out = <String, dynamic>{};
  for (final entry in json.entries) {
    final argument = spec.argument(entry.key);
    if (argument == null) _bad(entry.key, 'unknown argument');
    if (entry.value == null) {
      if (argument.required && !argument.nullable) {
        _bad(entry.key, 'required');
      }
      // A null that means nothing is the same as leaving it out.
      if (argument.nullable) out[entry.key] = null;
      continue;
    }
    out[entry.key] = argument.type.decode(entry.value, entry.key);
  }
  for (final argument in spec.arguments) {
    if (argument.required && !json.containsKey(argument.name)) {
      _bad(argument.name, 'required');
    }
  }
  return out;
}

/// Runs command [kind] with [arguments] written as plain JSON. An unknown
/// command is refused as `UNKNOWN_COMMAND` and a bad argument as
/// `BAD_ARGUMENT`, with the argument named in the message.
CommandResult executeJsonCommand(UndoableDesignState state, String kind,
    Map<String, Object?> arguments, CommandContext context) {
  final spec = commandSpec(kind);
  if (spec == null) return Rejected('UNKNOWN_COMMAND', 'no command $kind');
  final Map<String, dynamic> decoded;
  try {
    decoded = decodeArguments(spec, arguments);
  } on BadArgument catch (e) {
    return Rejected('BAD_ARGUMENT', e.toString());
  }
  return executeCommand(state, DesignCommand(kind, decoded), context);
}
