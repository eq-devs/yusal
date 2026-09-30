import 'dart:convert';
import 'schema_validator.dart';

import '../document/house_document.dart';
import '../validation/document_validator.dart';

const currentSchemaVersion = 1;
const maxHouseBytes = 10485760;

class LoadError {
  const LoadError(this.code, this.path, this.message);
  final String code, path, message;
}

class LoadFailure {
  const LoadFailure(this.stage, this.errors);
  final String stage;
  final List<LoadError> errors;
}

class LoadResult {
  const LoadResult.success(this.document) : failure = null;
  const LoadResult.failure(this.failure) : document = null;
  final HouseDocument? document;
  final LoadFailure? failure;
  bool get isSuccess => document != null;
}

class _DecodeException implements Exception {
  _DecodeException(this.code, this.path, this.message);
  final String code, path, message;
}

Object? _parseJson(String source) {
  var i = 0;
  void ws() {
    while (i < source.length && ' \n\r\t'.contains(source[i])) i++;
  }

  String string() {
    final start = i++;
    while (i < source.length) {
      final c = source.codeUnitAt(i++);
      if (c == 0x22) break;
      if (c == 0x5c) {
        if (i < source.length) i++;
      }
    }
    return jsonDecode(source.substring(start, i)) as String;
  }

  Object? value(String path) {
    ws();
    if (i >= source.length) throw const FormatException();
    final c = source[i];
    if (c == '{') {
      i++;
      ws();
      final map = <String, Object?>{};
      if (i < source.length && source[i] == '}') {
        i++;
        return map;
      }
      while (true) {
        ws();
        if (i >= source.length || source[i] != '"')
          throw const FormatException();
        final key = string();
        if (map.containsKey(key))
          throw _DecodeException(
            'DUPLICATE_JSON_KEY',
            '$path/${key.replaceAll('~', '~0').replaceAll('/', '~1')}',
            'JSON 对象包含重复键 $key',
          );
        ws();
        if (i >= source.length || source[i++] != ':')
          throw const FormatException();
        map[key] = value(
          '$path/${key.replaceAll('~', '~0').replaceAll('/', '~1')}',
        );
        ws();
        if (i >= source.length) throw const FormatException();
        final sep = source[i++];
        if (sep == '}') break;
        if (sep != ',') throw const FormatException();
      }
      return map;
    }
    if (c == '[') {
      i++;
      ws();
      final list = <Object?>[];
      if (i < source.length && source[i] == ']') {
        i++;
        return list;
      }
      while (true) {
        list.add(value('$path/${list.length}'));
        ws();
        if (i >= source.length) throw const FormatException();
        final sep = source[i++];
        if (sep == ']') break;
        if (sep != ',') throw const FormatException();
      }
      return list;
    }
    if (c == '"') return string();
    final start = i;
    while (i < source.length && !',]} \n\r\t'.contains(source[i])) i++;
    if (start == i) throw const FormatException();
    return jsonDecode(source.substring(start, i));
  }

  final result = value('');
  ws();
  if (i != source.length) throw const FormatException();
  return result;
}

class _Decoder {
  final errors = <LoadError>[];
  void err(String code, String path, String message) {
    if (errors.length < 100) errors.add(LoadError(code, path, message));
  }

  Map<String, Object?> obj(Object? value, String path, List<String> allowed) {
    if (value is! Map) {
      err(value == null ? 'NULL_NOT_ALLOWED' : 'WRONG_TYPE', path, '应为对象');
      return const {};
    }
    final m = value.cast<String, Object?>();
    for (final key in allowed) {
      if (!m.containsKey(key)) err('MISSING_FIELD', '$path/$key', '缺少字段 $key');
    }
    for (final key in m.keys) {
      if (!allowed.contains(key))
        err('UNKNOWN_FIELD', '$path/$key', '未知字段 $key');
    }
    return m;
  }

  String str(Object? v, String p, {bool id = false}) {
    if (v is! String) {
      err(v == null ? 'NULL_NOT_ALLOWED' : 'WRONG_TYPE', p, '应为字符串');
      return '';
    }
    if (id && v.isEmpty) err('EMPTY_ID', p, 'id 不可为空');
    return v;
  }

  int integer(Object? v, String p) {
    if (v is int) {
      if (v.abs() > 2147483647) {
        err('INT_OUT_OF_RANGE', p, '整数超出 32 位范围');
        return 0;
      }
      return v;
    }
    if (v is double) {
      err('NOT_INTEGER', p, '必须是整数字面量');
      return 0;
    }
    err(v == null ? 'NULL_NOT_ALLOWED' : 'WRONG_TYPE', p, '应为整数');
    return 0;
  }

  List<Object?> arr(Object? v, String p) {
    if (v is List) return v;
    if (v == null)
      err('NULL_NOT_ALLOWED', p, '不可为 null');
    else
      err('WRONG_TYPE', p, '应为数组');
    return const [];
  }

  T en<T extends Enum>(Object? v, String p, List<T> values) {
    if (v is String) for (final x in values) if (x.name == v) return x;
    err('UNKNOWN_ENUM', p, '未知枚举值');
    return values.first;
  }

  bool timestamp(String v) {
    final re = RegExp(
      r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(?:Z|[+-]\d\d:\d\d)$',
    );
    if (!re.hasMatch(v)) return false;
    try {
      final date = DateTime.parse(v.substring(0, 10));
      if (date.toIso8601String().substring(0, 10) != v.substring(0, 10))
        return false;
      if (int.parse(v.substring(11, 13)) > 23 ||
          int.parse(v.substring(14, 16)) > 59 ||
          int.parse(v.substring(17, 19)) > 59) return false;
      DateTime.parse(v);
      return true;
    } catch (_) {
      return false;
    }
  }

  void strictTimestamp(String v, String p) {
    if (!timestamp(v)) err('INVALID_TIMESTAMP', p, '时间格式无效');
  }

  Meta meta(Object? v, String p) {
    final m = obj(v, p, ['name', 'createdAt', 'updatedAt']);
    final n = str(m['name'], '$p/name'),
        c = str(m['createdAt'], '$p/createdAt'),
        u = str(m['updatedAt'], '$p/updatedAt');
    strictTimestamp(c, '$p/createdAt');
    strictTimestamp(u, '$p/updatedAt');
    return Meta(name: n, createdAt: c, updatedAt: u);
  }

  Defaults defaults(Object? v, String p) {
    const f = [
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
    ];
    final m = obj(v, p, f);
    final a = [for (final k in f) integer(m[k], '$p/$k')];
    return Defaults(
      outerWallThickness: a[0],
      innerWallThickness: a[1],
      slabThickness: a[2],
      stairRiserMax: a[3],
      stairTread: a[4],
      stairWidthMin: a[5],
      floorHeight: a[6],
      doorWidth: a[7],
      doorHeight: a[8],
      windowWidth: a[9],
      windowHeight: a[10],
      windowSill: a[11],
    );
  }

  BuildingFootprint footprint(Object? v, String p) {
    final m = obj(v, p, ['width', 'depth', 'northAngleDeg']);
    return BuildingFootprint(
      width: integer(m['width'], '$p/width'),
      depth: integer(m['depth'], '$p/depth'),
      northAngleDeg: integer(m['northAngleDeg'], '$p/northAngleDeg'),
    );
  }

  AxisRectangle rect(Object? v, String p) {
    final m = obj(v, p, ['x0', 'x1', 'y0', 'y1']);
    return AxisRectangle(
      x0: str(m['x0'], '$p/x0', id: true),
      x1: str(m['x1'], '$p/x1', id: true),
      y0: str(m['y0'], '$p/y0', id: true),
      y1: str(m['y1'], '$p/y1', id: true),
    );
  }

  BoundaryAnchor anchor(Object? v, String p) {
    final m = obj(v, p, ['axisId', 'startAxisId', 'endAxisId']);
    return BoundaryAnchor(
      axisId: str(m['axisId'], '$p/axisId', id: true),
      startAxisId: str(m['startAxisId'], '$p/startAxisId', id: true),
      endAxisId: str(m['endAxisId'], '$p/endAxisId', id: true),
    );
  }

  OpeningPosition position(Object? v, String p) {
    if (v is! Map) {
      err(v == null ? 'NULL_NOT_ALLOWED' : 'WRONG_TYPE', p, '应为位置对象');
      return const CenterPosition();
    }
    final m = v.cast<String, Object?>();
    final t = en(m['type'], '$p/type', PositionType.values);
    final keys = t == PositionType.center ? ['type'] : ['type', 'd'];
    _shape(m, p, keys);
    if (t == PositionType.center) return const CenterPosition();
    final d = integer(m['d'], '$p/d');
    return t == PositionType.fromStart
        ? FromStartPosition(d)
        : FromEndPosition(d);
  }

  void _shape(Map<String, Object?> m, String p, List<String> required,
      {List<String>? allowed}) {
    final accepted = allowed ?? required;
    for (final k in required)
      if (!m.containsKey(k)) err('MISSING_FIELD', '$p/$k', '缺少字段 $k');
    for (final k in m.keys)
      if (!accepted.contains(k))
        err('FIELD_NOT_ALLOWED', '$p/$k', '此形状不允许字段 $k');
  }

  WallOverride wall(Object? v, String p) {
    if (v is! Map) {
      err('WRONG_TYPE', p, '应为对象');
      return const OpenWall(
        id: 'invalid',
        anchor: BoundaryAnchor(axisId: '', startAxisId: '', endAxisId: ''),
      );
    }
    final m = v.cast<String, Object?>();
    final raw = m['type'];
    if (raw == 'open') {
      _shape(m, p, ['type', 'id', 'anchor']);
      return OpenWall(
        id: str(m['id'], '$p/id', id: true),
        anchor: anchor(m['anchor'], '$p/anchor'),
      );
    }
    if (raw == 'thickness') {
      _shape(m, p, ['type', 'id', 'anchor', 'value']);
      return ThicknessWall(
        id: str(m['id'], '$p/id', id: true),
        anchor: anchor(m['anchor'], '$p/anchor'),
        value: integer(m['value'], '$p/value'),
      );
    }
    err('UNKNOWN_DISCRIMINATOR', '$p/type', '未知 type');
    return const OpenWall(
      id: 'invalid',
      anchor: BoundaryAnchor(axisId: '', startAxisId: '', endAxisId: ''),
    );
  }

  Opening opening(Object? v, String p) {
    if (v is! Map) {
      err('WRONG_TYPE', p, '应为对象');
      return const WindowOpening(
        id: 'invalid',
        anchor: BoundaryAnchor(axisId: '', startAxisId: '', endAxisId: ''),
        position: CenterPosition(),
        width: 1,
        height: 1,
        sill: 0,
      );
    }
    final m = v.cast<String, Object?>();
    final raw = m['kind'];
    final kind = OpeningKind.values.where((e) => e.name == raw).firstOrNull;
    if (kind == null) err('UNKNOWN_DISCRIMINATOR', '$p/kind', '未知 kind');
    final required = [
      'kind',
      'id',
      'anchor',
      'position',
      'width',
      'height',
      'sill',
      if (kind == OpeningKind.door) 'hinge',
      if (kind == OpeningKind.door) 'opensTo',
    ];
    _shape(m, p, required);
    final id = str(m['id'], '$p/id', id: true),
        a = anchor(m['anchor'], '$p/anchor'),
        pos = position(m['position'], '$p/position');
    final w = integer(m['width'], '$p/width'),
        h = integer(m['height'], '$p/height'),
        s = integer(m['sill'], '$p/sill');
    if (kind == OpeningKind.door)
      return DoorOpening(
        id: id,
        anchor: a,
        position: pos,
        width: w,
        height: h,
        sill: s,
        hinge: en(m['hinge'], '$p/hinge', Hinge.values),
        opensTo: en(m['opensTo'], '$p/opensTo', OpeningSide.values),
      );
    if (kind == OpeningKind.sliding)
      return SlidingOpening(
        id: id,
        anchor: a,
        position: pos,
        width: w,
        height: h,
        sill: s,
      );
    return WindowOpening(
      id: id,
      anchor: a,
      position: pos,
      width: w,
      height: h,
      sill: s,
    );
  }

  Stair stair(Object? v, String p) {
    if (v is! Map) {
      err('WRONG_TYPE', p, '应为对象');
      return const StraightStair(
        id: 'invalid',
        region: AxisRectangle(x0: '', x1: '', y0: '', y1: ''),
        startEdge: StairEdge.bottom,
      );
    }
    final m = v.cast<String, Object?>();
    final raw = m['type'];
    final type = StairType.values.where((e) => e.name == raw).firstOrNull;
    if (type == null) err('UNKNOWN_DISCRIMINATOR', '$p/type', '未知 type');
    _shape(m, p, [
      'type',
      'id',
      'region',
      'startEdge',
      if (type == StairType.L || type == StairType.U) 'turn',
    ]);
    final id = str(m['id'], '$p/id', id: true),
        r = rect(m['region'], '$p/region'),
        edge = en(m['startEdge'], '$p/startEdge', StairEdge.values);
    if (type == StairType.L || type == StairType.U)
      return TurnStair(
        id: id,
        region: r,
        startEdge: edge,
        turn: en(m['turn'], '$p/turn', StairTurn.values),
        type: type!,
      );
    return StraightStair(id: id, region: r, startEdge: edge);
  }

  Roof roof(Object? v, String p) {
    if (v is! Map) {
      err('WRONG_TYPE', p, '应为对象');
      return const Roof.flat(0);
    }
    final m = v.cast<String, Object?>();
    final raw = m['type'];
    if (raw == 'flat') {
      _shape(m, p, ['type', 'parapetHeight']);
      return Roof.flat(integer(m['parapetHeight'], '$p/parapetHeight'));
    }
    if (raw == 'gable') {
      _shape(m, p, ['type', 'ridgeDir', 'pitchDeg', 'overhang']);
      return Roof.gable(
        ridgeDir: en(m['ridgeDir'], '$p/ridgeDir', AxisDir.values),
        pitchDeg: integer(m['pitchDeg'], '$p/pitchDeg'),
        overhang: integer(m['overhang'], '$p/overhang'),
      );
    }
    err('UNKNOWN_DISCRIMINATOR', '$p/type', '未知屋顶 type');
    return const Roof.flat(0);
  }

  Floor floor(Object? v, String p) {
    final keys = [
      'id',
      'name',
      'height',
      'rooms',
      'wallOverrides',
      'openings',
      'stairs',
    ];
    final m = obj(v, p, keys);
    final rooms = arr(m['rooms'], '$p/rooms'),
        walls = arr(m['wallOverrides'], '$p/wallOverrides'),
        opens = arr(m['openings'], '$p/openings'),
        stairs = arr(m['stairs'], '$p/stairs');
    return Floor(
      id: str(m['id'], '$p/id', id: true),
      name: str(m['name'], '$p/name'),
      height: integer(m['height'], '$p/height'),
      rooms: [
        for (var i = 0; i < rooms.length; i++) _room(rooms[i], '$p/rooms/$i'),
      ],
      wallOverrides: [
        for (var i = 0; i < walls.length; i++)
          wall(walls[i], '$p/wallOverrides/$i'),
      ],
      openings: [
        for (var i = 0; i < opens.length; i++)
          opening(opens[i], '$p/openings/$i'),
      ],
      stairs: [
        for (var i = 0; i < stairs.length; i++)
          stair(stairs[i], '$p/stairs/$i'),
      ],
    );
  }

  Room _room(Object? v, String p) {
    final m = obj(v, p, ['id', 'type', 'name', 'regions']);
    final r = arr(m['regions'], '$p/regions');
    return Room(
      id: str(m['id'], '$p/id', id: true),
      type: en(m['type'], '$p/type', RoomType.values),
      name: str(m['name'], '$p/name'),
      regions: [for (var i = 0; i < r.length; i++) rect(r[i], '$p/regions/$i')],
    );
  }

  AxisSystem axes(Object? v, String p) {
    final m = obj(v, p, ['global', 'floor']);
    final g = arr(m['global'], '$p/global'), f = arr(m['floor'], '$p/floor');
    final globals = <GlobalAxis>[], floors = <FloorAxis>[];
    for (var i = 0; i < g.length; i++) {
      final x = obj(g[i], '$p/global/$i', ['id', 'dir', 'pos']);
      globals.add(
        GlobalAxis(
          id: str(x['id'], '$p/global/$i/id', id: true),
          dir: en(x['dir'], '$p/global/$i/dir', AxisDir.values),
          pos: integer(x['pos'], '$p/global/$i/pos'),
        ),
      );
    }
    for (var i = 0; i < f.length; i++) {
      final x = obj(f[i], '$p/floor/$i', ['id', 'floorId', 'dir', 'pos']);
      floors.add(
        FloorAxis(
          id: str(x['id'], '$p/floor/$i/id', id: true),
          floorId: str(x['floorId'], '$p/floor/$i/floorId', id: true),
          dir: en(x['dir'], '$p/floor/$i/dir', AxisDir.values),
          pos: integer(x['pos'], '$p/floor/$i/pos'),
        ),
      );
    }
    return AxisSystem(global: globals, floor: floors);
  }

  HouseDocument document(Object? value) {
    final keys = [
      'schemaVersion',
      'meta',
      'mainEntranceOpeningId',
      'defaults',
      'footprint',
      'axes',
      'floors',
      'roof',
    ];
    if (value is! Map) {
      err('ROOT_NOT_OBJECT', '', '根节点应为对象');
      return _empty();
    }
    final m = value.cast<String, Object?>();
    _shape(m, '', keys.where((key) => key != 'mainEntranceOpeningId').toList(),
        allowed: keys);
    String? entrance;
    if (m.containsKey('mainEntranceOpeningId'))
      entrance = str(
        m['mainEntranceOpeningId'],
        '/mainEntranceOpeningId',
        id: true,
      );
    final ds = arr(m['floors'], '/floors');
    return HouseDocument(
      schemaVersion: integer(m['schemaVersion'], '/schemaVersion'),
      meta: meta(m['meta'], '/meta'),
      mainEntranceOpeningId: entrance,
      defaults: defaults(m['defaults'], '/defaults'),
      footprint: footprint(m['footprint'], '/footprint'),
      axes: axes(m['axes'], '/axes'),
      floors: [for (var i = 0; i < ds.length; i++) floor(ds[i], '/floors/$i')],
      roof: roof(m['roof'], '/roof'),
    );
  }

  HouseDocument _empty() => HouseDocument(
        schemaVersion: 1,
        meta: const Meta(
          name: '',
          createdAt: '2000-01-01T00:00:00Z',
          updatedAt: '2000-01-01T00:00:00Z',
        ),
        defaults: const Defaults(
          outerWallThickness: 1,
          innerWallThickness: 1,
          slabThickness: 1,
          stairRiserMax: 1,
          stairTread: 1,
          stairWidthMin: 1,
          floorHeight: 2400,
          doorWidth: 1,
          doorHeight: 1,
          windowWidth: 1,
          windowHeight: 1,
          windowSill: 0,
        ),
        footprint: const BuildingFootprint(
          width: 3000,
          depth: 3000,
          northAngleDeg: 0,
        ),
        axes: AxisSystem(global: [], floor: []),
        floors: [],
        roof: const Roof.flat(0),
      );
}

LoadResult loadHouse(List<int> bytes) {
  if (bytes.length > maxHouseBytes)
    return const LoadResult.failure(
      LoadFailure('file', [LoadError('FILE_TOO_LARGE', '', '文件超过 10 MiB')]),
    );
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf)
    return const LoadResult.failure(
      LoadFailure('file', [LoadError('BOM_NOT_ALLOWED', '', '不允许 UTF-8 BOM')]),
    );
  String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
  } catch (_) {
    return const LoadResult.failure(
      LoadFailure('file', [LoadError('NOT_UTF8', '', '文件不是有效 UTF-8')]),
    );
  }
  Object? raw;
  try {
    raw = _parseJson(source);
  } catch (e) {
    if (e is _DecodeException)
      return LoadResult.failure(
        LoadFailure('file', [LoadError(e.code, e.path, e.message)]),
      );
    return const LoadResult.failure(
      LoadFailure('file', [LoadError('NOT_JSON', '', '文件不是合法 JSON')]),
    );
  }
  if (raw is! Map)
    return const LoadResult.failure(
      LoadFailure('envelope', [LoadError('ROOT_NOT_OBJECT', '', '根节点应为对象')]),
    );
  final env = raw.cast<String, Object?>();
  if (!env.containsKey('schemaVersion'))
    return const LoadResult.failure(
      LoadFailure('envelope', [
        LoadError('MISSING_VERSION', '/schemaVersion', '缺少 schemaVersion'),
      ]),
    );
  final version = env['schemaVersion'];
  if (version is! int || version < 1)
    return const LoadResult.failure(
      LoadFailure('envelope', [
        LoadError('INVALID_VERSION', '/schemaVersion', 'schemaVersion 无效'),
      ]),
    );
  if (version > currentSchemaVersion)
    return const LoadResult.failure(
      LoadFailure('envelope', [
        LoadError('UNSUPPORTED_NEWER_VERSION', '/schemaVersion', '文件版本高于当前版本'),
      ]),
    );
  return decodeV1(raw);
}

LoadResult decodeV1(Object? raw) {
  final schemaErrors = validateSchemaV1(raw);
  if (schemaErrors.isNotEmpty)
    return LoadResult.failure(LoadFailure('decode', schemaErrors));
  final d = _Decoder(), doc = d.document(raw);
  if (d.errors.isNotEmpty)
    return LoadResult.failure(
      LoadFailure('decode', List.unmodifiable(d.errors)),
    );
  final validation = validateHouse(doc);
  if (validation.isNotEmpty)
    return LoadResult.failure(
      LoadFailure('validate', [
        for (final e in validation) LoadError(e.code, e.path, e.message),
      ]),
    );
  return LoadResult.success(doc);
}

String encodeHouse(HouseDocument d) {
  assert(validateHouse(d).isEmpty, 'Only valid documents can be encoded');
  Map<String, Object?> rect(AxisRectangle r) => {
        'x0': r.x0,
        'x1': r.x1,
        'y0': r.y0,
        'y1': r.y1,
      };
  Map<String, Object?> anchor(BoundaryAnchor a) => {
        'axisId': a.axisId,
        'startAxisId': a.startAxisId,
        'endAxisId': a.endAxisId,
      };
  Map<String, Object?> pos(OpeningPosition p) => switch (p) {
        CenterPosition() => {'type': 'center'},
        FromStartPosition(:final d) => {'type': 'fromStart', 'd': d},
        FromEndPosition(:final d) => {'type': 'fromEnd', 'd': d},
      };
  final root = <String, Object?>{
    'schemaVersion': d.schemaVersion,
    'meta': {
      'name': d.meta.name,
      'createdAt': d.meta.createdAt,
      'updatedAt': d.meta.updatedAt,
    },
    if (d.mainEntranceOpeningId != null)
      'mainEntranceOpeningId': d.mainEntranceOpeningId,
    'defaults': {
      'outerWallThickness': d.defaults.outerWallThickness,
      'innerWallThickness': d.defaults.innerWallThickness,
      'slabThickness': d.defaults.slabThickness,
      'stairRiserMax': d.defaults.stairRiserMax,
      'stairTread': d.defaults.stairTread,
      'stairWidthMin': d.defaults.stairWidthMin,
      'floorHeight': d.defaults.floorHeight,
      'doorWidth': d.defaults.doorWidth,
      'doorHeight': d.defaults.doorHeight,
      'windowWidth': d.defaults.windowWidth,
      'windowHeight': d.defaults.windowHeight,
      'windowSill': d.defaults.windowSill,
    },
    'footprint': {
      'width': d.footprint.width,
      'depth': d.footprint.depth,
      'northAngleDeg': d.footprint.northAngleDeg,
    },
    'axes': {
      'global': [
        for (final a in d.axes.global)
          {'id': a.id, 'dir': a.dir.name, 'pos': a.pos},
      ],
      'floor': [
        for (final a in d.axes.floor)
          {'id': a.id, 'floorId': a.floorId, 'dir': a.dir.name, 'pos': a.pos},
      ],
    },
    'floors': [
      for (final f in d.floors)
        {
          'id': f.id,
          'name': f.name,
          'height': f.height,
          'rooms': [
            for (final r in f.rooms)
              {
                'id': r.id,
                'type': r.type.name,
                'name': r.name,
                'regions': [for (final x in r.regions) rect(x)],
              },
          ],
          'wallOverrides': [
            for (final w in f.wallOverrides)
              switch (w) {
                OpenWall() => {
                    'type': 'open',
                    'id': w.id,
                    'anchor': anchor(w.anchor),
                  },
                ThicknessWall() => {
                    'type': 'thickness',
                    'id': w.id,
                    'anchor': anchor(w.anchor),
                    'value': w.value,
                  },
              },
          ],
          'openings': [
            for (final o in f.openings)
              switch (o) {
                DoorOpening() => {
                    'kind': 'door',
                    'id': o.id,
                    'anchor': anchor(o.anchor),
                    'position': pos(o.position),
                    'width': o.width,
                    'height': o.height,
                    'sill': o.sill,
                    'hinge': o.hinge.name,
                    'opensTo': o.opensTo.name,
                  },
                WindowOpening() => {
                    'kind': 'window',
                    'id': o.id,
                    'anchor': anchor(o.anchor),
                    'position': pos(o.position),
                    'width': o.width,
                    'height': o.height,
                    'sill': o.sill,
                  },
                SlidingOpening() => {
                    'kind': 'sliding',
                    'id': o.id,
                    'anchor': anchor(o.anchor),
                    'position': pos(o.position),
                    'width': o.width,
                    'height': o.height,
                    'sill': o.sill,
                  },
              },
          ],
          'stairs': [
            for (final s in f.stairs)
              switch (s) {
                StraightStair() => {
                    'type': 'straight',
                    'id': s.id,
                    'region': rect(s.region),
                    'startEdge': s.startEdge.name,
                  },
                TurnStair() => {
                    'type': s.type.name,
                    'id': s.id,
                    'region': rect(s.region),
                    'startEdge': s.startEdge.name,
                    'turn': s.turn.name,
                  },
              },
          ],
        },
    ],
    'roof': switch (d.roof.type) {
      RoofType.flat => {'type': 'flat', 'parapetHeight': d.roof.parapetHeight},
      RoofType.gable => {
          'type': 'gable',
          'ridgeDir': d.roof.ridgeDir!.name,
          'pitchDeg': d.roof.pitchDeg,
          'overhang': d.roof.overhang,
        },
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(root)}\n';
}
