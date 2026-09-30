import 'house_codec.dart' show LoadError;

List<LoadError> validateSchemaV1(Object? value) {
  final errors = <LoadError>[];
  void error(String code, String path, String message) {
    if (errors.length < 100) errors.add(LoadError(code, path, message));
  }

  const enums = {
    'AxisDir': ['V', 'H'],
    'RoomType': [
      'living',
      'bedroom',
      'kitchen',
      'bathroom',
      'dining',
      'custom'
    ],
    'Hinge': ['start', 'end'],
    'OpeningSide': ['positiveSide', 'negativeSide'],
    'StairEdge': ['bottom', 'top', 'left', 'right'],
    'StairTurn': ['left', 'right']
  };
  const fields = {
    'Project': {
      'schemaVersion': 'int',
      'meta': 'Meta',
      'mainEntranceOpeningId?': 'id',
      'defaults': 'Defaults',
      'footprint': 'Footprint',
      'axes': 'Axes',
      'floors': '[]Floor',
      'roof': 'Roof'
    },
    'Meta': {
      'name': 'string',
      'createdAt': 'timestamp',
      'updatedAt': 'timestamp'
    },
    'Defaults': {
      'outerWallThickness': 'int',
      'innerWallThickness': 'int',
      'slabThickness': 'int',
      'stairRiserMax': 'int',
      'stairTread': 'int',
      'stairWidthMin': 'int',
      'floorHeight': 'int',
      'doorWidth': 'int',
      'doorHeight': 'int',
      'windowWidth': 'int',
      'windowHeight': 'int',
      'windowSill': 'int'
    },
    'Footprint': {'width': 'int', 'depth': 'int', 'northAngleDeg': 'int'},
    'Axes': {'global': '[]GlobalAxis', 'floor': '[]FloorAxis'},
    'GlobalAxis': {'id': 'id', 'dir': 'AxisDir', 'pos': 'int'},
    'FloorAxis': {'id': 'id', 'floorId': 'id', 'dir': 'AxisDir', 'pos': 'int'},
    'Rect': {'x0': 'id', 'x1': 'id', 'y0': 'id', 'y1': 'id'},
    'Anchor': {'axisId': 'id', 'startAxisId': 'id', 'endAxisId': 'id'},
    'Floor': {
      'id': 'id',
      'name': 'string',
      'height': 'int',
      'rooms': '[]Room',
      'wallOverrides': '[]Wall',
      'openings': '[]Opening',
      'stairs': '[]Stair'
    },
    'Room': {
      'id': 'id',
      'type': 'RoomType',
      'name': 'string',
      'regions': '[]Rect'
    },
    'Wall.open': {'type': 'string', 'id': 'id', 'anchor': 'Anchor'},
    'Wall.thickness': {
      'type': 'string',
      'id': 'id',
      'anchor': 'Anchor',
      'value': 'int'
    },
    'Position.center': {'type': 'string'},
    'Position.fromStart': {'type': 'string', 'd': 'int'},
    'Position.fromEnd': {'type': 'string', 'd': 'int'},
    'Opening.door': {
      'kind': 'string',
      'id': 'id',
      'anchor': 'Anchor',
      'position': 'Position',
      'width': 'int',
      'height': 'int',
      'sill': 'int',
      'hinge': 'Hinge',
      'opensTo': 'OpeningSide'
    },
    'Opening.window': {
      'kind': 'string',
      'id': 'id',
      'anchor': 'Anchor',
      'position': 'Position',
      'width': 'int',
      'height': 'int',
      'sill': 'int'
    },
    'Opening.sliding': {
      'kind': 'string',
      'id': 'id',
      'anchor': 'Anchor',
      'position': 'Position',
      'width': 'int',
      'height': 'int',
      'sill': 'int'
    },
    'Stair.straight': {
      'type': 'string',
      'id': 'id',
      'region': 'Rect',
      'startEdge': 'StairEdge'
    },
    'Stair.L': {
      'type': 'string',
      'id': 'id',
      'region': 'Rect',
      'startEdge': 'StairEdge',
      'turn': 'StairTurn'
    },
    'Stair.U': {
      'type': 'string',
      'id': 'id',
      'region': 'Rect',
      'startEdge': 'StairEdge',
      'turn': 'StairTurn'
    },
    'Roof.flat': {'type': 'string', 'parapetHeight': 'int'},
    'Roof.gable': {
      'type': 'string',
      'ridgeDir': 'AxisDir',
      'pitchDeg': 'int',
      'overhang': 'int'
    },
  };
  const unions = {
    'Wall': ['open', 'thickness'],
    'Position': ['center', 'fromStart', 'fromEnd'],
    'Opening': ['door', 'window', 'sliding'],
    'Stair': ['straight', 'L', 'U'],
    'Roof': ['flat', 'gable']
  };
  String child(String path, String field) =>
      '$path/${field.replaceAll('~', '~0').replaceAll('/', '~1')}';
  bool time(String v) {
    if (!RegExp(
            r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(?:Z|[+-]\d\d:\d\d)$')
        .hasMatch(v)) return false;
    try {
      if (DateTime.parse(v.substring(0, 10))
              .toIso8601String()
              .substring(0, 10) !=
          v.substring(0, 10)) return false;
      if (int.parse(v.substring(11, 13)) > 23 ||
          int.parse(v.substring(14, 16)) > 59 ||
          int.parse(v.substring(17, 19)) > 59) return false;
      if (!v.endsWith('Z')) {
        if (int.parse(v.substring(v.length - 5, v.length - 3)) > 23 ||
            int.parse(v.substring(v.length - 2)) > 59) return false;
      }
      DateTime.parse(v);
      return true;
    } catch (_) {
      return false;
    }
  }

  void node(Object? v, String type, String path) {
    if (errors.length >= 100) return;
    if (v == null) {
      error('NULL_NOT_ALLOWED', path, '不可为 null');
      return;
    }
    if (type.startsWith('[]')) {
      if (v is! List) {
        error('WRONG_TYPE', path, '应为数组');
        return;
      }
      for (var i = 0; i < v.length && errors.length < 100; i++)
        node(v[i], type.substring(2), '$path/$i');
      return;
    }
    if (type == 'int') {
      if (v is int) {
        if (v.abs() > 2147483647)
          error('INT_OUT_OF_RANGE', path, '整数超出 32 位范围');
      } else
        error(v is double ? 'NOT_INTEGER' : 'WRONG_TYPE', path, '必须是整数字面量');
      return;
    }
    if (['string', 'id', 'timestamp'].contains(type) ||
        enums.containsKey(type)) {
      if (v is! String) {
        error('WRONG_TYPE', path, '应为字符串');
        return;
      }
      if (type == 'id' && v.isEmpty) error('EMPTY_ID', path, 'id 不可为空');
      if (type == 'timestamp' && !time(v))
        error('INVALID_TIMESTAMP', path, '带时区的时间无效');
      if (enums.containsKey(type) && !enums[type]!.contains(v))
        error('UNKNOWN_ENUM', path, '未知枚举值');
      return;
    }
    if (v is! Map) {
      error('WRONG_TYPE', path, '应为对象');
      return;
    }
    final union = unions[type];
    var shape = type;
    if (union != null) {
      final disc = type == 'Opening' ? 'kind' : 'type';
      if (!v.containsKey(disc)) {
        error('MISSING_FIELD', child(path, disc), '缺少区分字段');
        return;
      }
      if (v[disc] == null) {
        error('NULL_NOT_ALLOWED', child(path, disc), '不可为 null');
        return;
      }
      if (v[disc] is! String) {
        error('WRONG_TYPE', child(path, disc), '区分字段应为字符串');
        return;
      }
      if (!union.contains(v[disc])) {
        error('UNKNOWN_DISCRIMINATOR', child(path, disc), '未知对象形状');
        return;
      }
      shape = '$type.${v[disc]}';
    }
    final schema = fields[shape]!;
    final accepted = <String>{};
    for (final field in schema.entries) {
      final optional = field.key.endsWith('?'),
          key = optional
              ? field.key.substring(0, field.key.length - 1)
              : field.key;
      accepted.add(key);
      if (!v.containsKey(key)) {
        if (!optional) error('MISSING_FIELD', child(path, key), '缺少字段 $key');
      } else {
        node(v[key], field.value, child(path, key));
      }
      if (errors.length >= 100) return;
    }
    final otherShapeKeys = union == null
        ? <String>{}
        : {for (final variant in union) ...fields['$type.$variant']!.keys};
    for (final key in v.keys) {
      if (!accepted.contains(key))
        error(
            otherShapeKeys.contains(key)
                ? 'FIELD_NOT_ALLOWED'
                : 'UNKNOWN_FIELD',
            child(path, key as String),
            '此对象不允许字段 $key');
      if (errors.length >= 100) return;
    }
  }

  node(value, 'Project', '');
  return List.unmodifiable(errors);
}
