import 'dart:convert';
import '../document/house_document.dart';
import '../serialization/house_codec.dart';
import '../axis/axis_resolver.dart';
import '../geometry/derived_house.dart';
import '../geometry/opening_constraints.dart';
import '../geometry/floor_base.dart';
import 'room_commands.dart';
import '../canonicalization/room_canonicalizer.dart';

class EditResult {
  const EditResult(this.document, this.error);
  final HouseDocument? document;
  final String? error;
  bool get accepted => document != null;
}

EditResult executeDocumentCommand(HouseDocument original, String kind,
    Map<String, dynamic> args, String Function() newId) {
  try {
    var doc = original;
    if (kind == 'AddStair' ||
        (kind == 'UpdateStair' && args['region'] != null)) {
      final targetFloor = kind == 'AddStair'
          ? args['floorId'] as String
          : doc.floors
              .firstWhere((f) => f.stairs.any((s) => s.id == args['stairId']))
              .id;
      final index = doc.floors.indexWhere((f) => f.id == targetFloor);
      if (index < 0 || index == doc.floors.length - 1)
        return const EditResult(null, '楼梯需要上方还有楼层');
      final region = args['region'] as AxisRectangle,
          axes = resolveFloorAxes(doc, targetFloor)!;
      if (doc.floors[index].explicitWalls) {
        final r = resolveRect(axes, region).rect!;
        final walls = deriveFloorBase(doc, targetFloor).wallSegments;
        if (walls.any((w) =>
            w.axis.kind != 'boundary' &&
            (w.axis.dir == AxisDir.V
                ? w.axis.pos > r.left &&
                    w.axis.pos < r.right &&
                    w.start.pos < r.top &&
                    w.end.pos > r.bottom
                : w.axis.pos > r.bottom &&
                    w.axis.pos < r.top &&
                    w.start.pos < r.right &&
                    w.end.pos > r.left)))
          return const EditResult(null, '楼梯不能穿过已有墙体，请先移动或删除这段墙');
      }
      doc = paintCells(doc, targetFloor,
          cellsOfRect(resolveRect(axes, region).rect!), RoomType.custom, newId,
          erase: true);
    }
    final raw = jsonDecode(encodeHouse(doc)) as Map<String, dynamic>;
    final floors = raw['floors'] as List<dynamic>;
    Map<String, dynamic> floor(String id) =>
        floors.cast<Map<String, dynamic>>().firstWhere((f) => f['id'] == id);
    Map<String, dynamic> object(String list, String id) => floors
        .expand((f) => f[list] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((v) => v['id'] == id);
    Map<String, dynamic> anchor(BoundaryAnchor a) => {
          'axisId': a.axisId,
          'startAxisId': a.startAxisId,
          'endAxisId': a.endAxisId
        };
    switch (kind) {
      case 'SetFootprintSize':
        for (final field in ['width', 'depth'])
          if (args.containsKey(field)) raw['footprint'][field] = args[field];
        break;
      case 'SetNorthAngle':
        if (![0, 90, 180, 270].contains(args['value']))
          return const EditResult(null, '请选择四个正北方向之一');
        raw['footprint']['northAngleDeg'] = args['value'];
        break;
      case 'SetRoof':
        raw['roof'] = args['roof'];
        break;
      case 'SetDefault':
        raw['defaults'][args['field']] = args['value'];
        break;
      case 'AddAxis':
        final axis = {
          'id': newId(),
          'dir': (args['dir'] as AxisDir).name,
          'pos': args['pos']
        };
        if (args['floorId'] != null) axis['floorId'] = args['floorId'];
        (raw['axes'][args['floorId'] == null ? 'global' : 'floor'] as List)
            .add(axis);
        break;
      case 'PromoteFloorAxis':
        final local = raw['axes']['floor'] as List;
        final axis = local
            .cast<Map<String, dynamic>>()
            .firstWhere((a) => a['id'] == args['axisId']);
        local.remove(axis);
        axis.remove('floorId');
        (raw['axes']['global'] as List).add(axis);
        break;
      case 'MoveAxis':
        final id = args['axisId'] as String, value = args['pos'] as int;
        for (final f in doc.floors) {
          final axes = resolveFloorAxes(doc, f.id)!;
          final lookup = lookupAxis(axes, id).axis;
          if (lookup == null) continue;
          if (lookup.kind == 'boundary')
            return const EditResult(null, '边界尺寸请通过房屋宽深修改');
          final list = lookup.dir == AxisDir.V ? axes.v : axes.h;
          if (value < list[lookup.index - 1].pos + 300 ||
              value > list[lookup.index + 1].pos - 300)
            return const EditResult(null, '分隔线不能越过相邻线，间距至少 0.30 米');
        }
        for (final a in [
          ...(raw['axes']['global'] as List),
          ...(raw['axes']['floor'] as List)
        ]) if (a['id'] == id) a['pos'] = value;
        break;
      case 'AddFloor':
      case 'CopyFloor':
        final source = floor(args['floorId'] as String),
            index = floors.indexOf(source);
        final id = newId();
        if (kind == 'AddFloor') {
          floors.insert(index + 1, {
            'id': id,
            'name': '${floors.length + 1}楼',
            'height': doc.defaults.floorHeight,
            'rooms': [],
            'wallOverrides': [],
            'openings': [],
            'stairs': []
          });
        } else {
          final copy = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
          final mapping = <String, String>{(source['id'] as String): id};
          final locals = (raw['axes']['floor'] as List)
              .where((a) => a['floorId'] == source['id'])
              .toList();
          for (final a in locals) mapping[a['id'] as String] = newId();
          for (final list in ['rooms', 'wallOverrides', 'openings'])
            for (final o in (copy[list] as List))
              mapping[o['id'] as String] = newId();
          dynamic remap(dynamic value) {
            if (value is String) return value;
            if (value is List) return value.map(remap).toList();
            if (value is Map)
              return value.map((k, v) => MapEntry(
                  k,
                  [
                            'id',
                            'floorId',
                            'x0',
                            'x1',
                            'y0',
                            'y1',
                            'axisId',
                            'startAxisId',
                            'endAxisId'
                          ].contains(k) &&
                          v is String
                      ? mapping[v] ?? v
                      : remap(v)));
            return value;
          }

          final mapped = remap(copy) as Map;
          mapped['name'] = '${source['name']} 副本';
          mapped['stairs'] = [];
          floors.insert(index + 1, mapped);
          for (final a in locals) (raw['axes']['floor'] as List).add(remap(a));
        }
        break;
      case 'DeleteFloor':
        if (floors.length == 1) return const EditResult(null, '至少保留一层');
        final removed = floor(args['floorId'] as String);
        final removedIndex = floors.indexOf(removed);
        if (removedIndex == floors.length - 1 &&
            removedIndex > 0 &&
            (floors[removedIndex - 1]['stairs'] as List).isNotEmpty) {
          if (args['deleteStairs'] != true)
            return const EditResult(null, '删除顶层后，下层楼梯没有上层。请确认同时删除这些楼梯');
          (floors[removedIndex - 1]['stairs'] as List).clear();
        }
        final openingIds =
            (removed['openings'] as List).map((o) => o['id']).toSet();
        if (openingIds.contains(raw['mainEntranceOpeningId']))
          raw.remove('mainEntranceOpeningId');
        floors.remove(removed);
        (raw['axes']['floor'] as List)
            .removeWhere((a) => a['floorId'] == args['floorId']);
        break;
      case 'SetFloorHeight':
        floor(args['floorId'] as String)['height'] = args['value'];
        break;
      case 'RenameFloor':
        floor(args['floorId'] as String)['name'] = args['value'];
        break;
      case 'MergeRooms':
        final a = args['roomIdA'] as String, b = args['roomIdB'] as String;
        if (a == b) return EditResult(original, null);
        final f = doc.floors.firstWhere((f) => f.rooms.any((r) => r.id == a));
        final ra = f.rooms.firstWhere((r) => r.id == a);
        final rb = f.rooms.where((r) => r.id == b).firstOrNull;
        if (rb == null) return const EditResult(null, '只能合并同一楼层的房间');
        final axes = resolveFloorAxes(doc, f.id)!;
        final ca = regionCells(axes, ra.regions).cells,
            cb = regionCells(axes, rb.regions).cells;
        final cells = {...ca, ...cb};
        if (!isConnected(cells)) return const EditResult(null, '只能合并相邻房间');
        final keep = compareComponentPriority(axes, ca, cb) <= 0 ? ra : rb;
        final rooms = floor(f.id)['rooms'] as List;
        rooms.removeWhere((r) => r['id'] == (keep.id == a ? b : a));
        object('rooms', keep.id)['regions'] = canonicalizeCells(axes, cells)
            .regions
            .map((r) => {'x0': r.x0, 'x1': r.x1, 'y0': r.y0, 'y1': r.y1})
            .toList();
        break;
      case 'RenameRoom':
        object('rooms', args['roomId'] as String)['name'] = args['value'];
        break;
      case 'SetRoomType':
        final room = object('rooms', args['roomId'] as String);
        final previous = RoomType.values.byName(room['type'] as String);
        final next = args['value'] as RoomType;
        if (room['name'] == roomNames[previous]) room['name'] = roomNames[next];
        room['type'] = next.name;
        break;
      case 'AddOpening':
        final a = args['anchor'] as BoundaryAnchor,
            f = floor(args['floorId'] as String),
            base = deriveFloorBase(doc, args['floorId'] as String);
        final chain = resolveAnchor(base.axes, a).chain!,
            tap = (args['tapT'] as num).toDouble(),
            openingKind = args['kind'] as OpeningKind;
        if (tap < 0 || tap > chain.nominalLength)
          return const EditResult(null, '点击位置不在墙段内');
        final isDoor = openingKind == OpeningKind.door,
            start = tap <= chain.nominalLength / 2;
        final opening = <String, dynamic>{
          'kind': openingKind.name,
          'id': newId(),
          'anchor': anchor(a),
          'position': isDoor
              ? {'type': start ? 'fromStart' : 'fromEnd', 'd': 200}
              : {'type': 'center'},
          'width': openingKind == OpeningKind.window
              ? doc.defaults.windowWidth
              : doc.defaults.doorWidth,
          'height': openingKind == OpeningKind.window
              ? doc.defaults.windowHeight
              : doc.defaults.doorHeight,
          'sill':
              openingKind == OpeningKind.window ? doc.defaults.windowSill : 0
        };
        if (isDoor) {
          opening['hinge'] = start ? 'start' : 'end';
          final segment = chain.locate(tap.round())!;
          double score(Cell? c) {
            if (c == null) return -1;
            final id = base.owners[c];
            return base.roomGeometry
                    .where((g) => g.id == id)
                    .firstOrNull
                    ?.clearArea ??
                0;
          }

          opening['opensTo'] =
              score(segment.positiveSide) >= score(segment.negativeSide)
                  ? 'positiveSide'
                  : 'negativeSide';
        }
        if (args['centerAtTap'] == true) {
          final width = opening['width'] as int;
          if (width > chain.nominalLength) {
            return const EditResult(null, '墙面太短，放不下这个门窗');
          }
          opening['position'] = {
            'type': 'fromStart',
            'd': (tap - width / 2).round().clamp(0, chain.nominalLength - width)
          };
        }
        (f['openings'] as List).add(opening);
        break;
      case 'SetOpeningKind':
        final o = object('openings', args['openingId'] as String);
        final kind = args['kind'] as OpeningKind;
        o['kind'] = kind.name;
        if (kind == OpeningKind.door) {
          o['sill'] = 0;
          o['hinge'] = o['position']['type'] == 'fromEnd' ? 'end' : 'start';
          final f = doc.floors
              .firstWhere((f) => f.openings.any((p) => p.id == o['id']));
          final g = deriveHouse(doc).floors[doc.floors.indexOf(f)];
          final p = g.openings.firstWhere((p) => p.opening.id == o['id']);
          final chain = resolveAnchor(g.base.axes, p.opening.anchor).chain!;
          final segment = chain.locate(((p.start + p.end) / 2 - chain.start.pos)
              .round()
              .clamp(0, chain.nominalLength))!;
          double score(Cell? cell) {
            if (cell == null) return -1;
            return g.base.roomGeometry
                    .where((r) => r.id == g.base.owners[cell])
                    .firstOrNull
                    ?.clearArea ??
                0;
          }

          o['opensTo'] =
              score(segment.positiveSide) >= score(segment.negativeSide)
                  ? 'positiveSide'
                  : 'negativeSide';
        } else {
          o.remove('hinge');
          o.remove('opensTo');
          o['sill'] = kind == OpeningKind.window ? doc.defaults.windowSill : 0;
          if (kind == OpeningKind.window)
            o['height'] = doc.defaults.windowHeight;
          if (raw['mainEntranceOpeningId'] == o['id'])
            raw.remove('mainEntranceOpeningId');
        }
        break;
      case 'ResizeOpening':
        final o = object('openings', args['openingId'] as String);
        for (final field in ['width', 'height', 'sill'])
          if (args.containsKey(field)) o[field] = args[field];
        break;
      case 'FlipDoor':
        final o = object('openings', args['openingId'] as String);
        if (o['kind'] != 'door') return const EditResult(null, '只有门可以调整开向');
        for (final field in ['hinge', 'opensTo'])
          if (args.containsKey(field)) o[field] = args[field];
        break;
      case 'MoveOpening':
        final o = object('openings', args['openingId'] as String);
        if (args['anchor'] != null)
          o['anchor'] = anchor(args['anchor'] as BoundaryAnchor);
        o['position'] = args['position'];
        if (args['anchor'] != null && o['kind'] == 'door') {
          final f = doc.floors
              .firstWhere((f) => f.openings.any((p) => p.id == o['id']));
          final base = deriveFloorBase(doc, f.id);
          final chain =
              resolveAnchor(base.axes, args['anchor'] as BoundaryAnchor).chain!;
          final position = args['position'] as Map<String, dynamic>;
          final center = switch (position['type']) {
            'fromStart' =>
              (position['d'] as num).toDouble() + (o['width'] as num) / 2,
            'fromEnd' => chain.nominalLength -
                (position['d'] as num) -
                (o['width'] as num) / 2,
            _ => chain.nominalLength / 2,
          };
          final segment =
              chain.locate(center.round().clamp(0, chain.nominalLength))!;
          double score(Cell? cell) => cell == null
              ? -1
              : base.roomGeometry
                      .where((g) => g.id == base.owners[cell])
                      .firstOrNull
                      ?.clearArea ??
                  0;
          o['opensTo'] =
              score(segment.positiveSide) >= score(segment.negativeSide)
                  ? 'positiveSide'
                  : 'negativeSide';
        }
        break;
      case 'DeleteOpening':
        for (final f in floors)
          (f['openings'] as List)
              .removeWhere((o) => o['id'] == args['openingId']);
        if (raw['mainEntranceOpeningId'] == args['openingId'])
          raw.remove('mainEntranceOpeningId');
        break;
      case 'SetMainEntrance':
        if (args['openingId'] == null) {
          raw.remove('mainEntranceOpeningId');
        } else {
          if (object('openings', args['openingId'] as String)['kind'] != 'door')
            return const EditResult(null, '主入口需要是一扇门');
          raw['mainEntranceOpeningId'] = args['openingId'];
        }
        break;
      case 'AddStair':
        final r = args['region'] as AxisRectangle,
            type = args['type'] as StairType;
        (floor(args['floorId'] as String)['stairs'] as List).add({
          'type': type.name,
          'id': newId(),
          'region': {'x0': r.x0, 'x1': r.x1, 'y0': r.y0, 'y1': r.y1},
          'startEdge': 'bottom',
          if (type != StairType.straight) 'turn': 'left'
        });
        break;
      case 'UpdateStair':
        final stair = object('stairs', args['stairId'] as String);
        if (args['region'] is AxisRectangle) {
          final r = args['region'] as AxisRectangle;
          stair['region'] = {'x0': r.x0, 'x1': r.x1, 'y0': r.y0, 'y1': r.y1};
        }
        for (final field in ['type', 'startEdge', 'turn'])
          if (args.containsKey(field)) stair[field] = args[field];
        if (stair['type'] == 'straight') {
          stair.remove('turn');
        } else {
          stair['turn'] ??= 'left';
        }
        break;
      case 'DeleteStair':
        for (final f in floors)
          (f['stairs'] as List).removeWhere((s) => s['id'] == args['stairId']);
        break;
      case 'SetWallOverride':
        final a = args['anchor'] as BoundaryAnchor,
            type = args['type'],
            f = floor(args['floorId'] as String);
        final axes = resolveFloorAxes(doc, args['floorId'] as String)!,
            chain = resolveAnchor(axes, a).chain!;
        final newOverrides = <dynamic>[];
        for (final w in (f['wallOverrides'] as List)) {
          final old = BoundaryAnchor(
                  axisId: w['anchor']['axisId'] as String,
                  startAxisId: w['anchor']['startAxisId'] as String,
                  endAxisId: w['anchor']['endAxisId'] as String),
              c = resolveAnchor(axes, old).chain!;
          if (c.carrier.id != chain.carrier.id ||
              c.startPos >= chain.endPos ||
              chain.startPos >= c.endPos) {
            newOverrides.add(w);
            continue;
          }
          final left = c.startPos < chain.startPos,
              right = c.endPos > chain.endPos;
          if (left) {
            final copy = jsonDecode(jsonEncode(w));
            copy['anchor']['endAxisId'] = a.startAxisId;
            newOverrides.add(copy);
          }
          if (right) {
            final copy = jsonDecode(jsonEncode(w));
            if (left) copy['id'] = newId();
            copy['anchor']['startAxisId'] = a.endAxisId;
            newOverrides.add(copy);
          }
        }
        final explicit =
            f['explicitWalls'] == true && chain.carrier.kind != 'boundary';
        if (type != 'default' || explicit)
          newOverrides.add({
            'type': explicit && type != 'open' ? 'solid' : type,
            'id': newId(),
            'anchor': anchor(a),
            if (type == 'thickness') 'value': args['value'],
            if (explicit && type == 'default')
              'value': doc.defaults.innerWallThickness,
          });
        f['wallOverrides'] = newOverrides;
        break;
      default:
        return EditResult(null, '尚未支持的命令 $kind');
    }
    final loaded = loadHouse(utf8.encode(jsonEncode(raw)));
    if (!loaded.isSuccess)
      return EditResult(null, '操作无法完成：${loaded.failure!.errors.first.message}');
    if (kind == 'SetFootprintSize' || kind == 'MoveAxis') {
      final healthy = documentOpenings(doc)
          .where((p) => p.status == 'ok')
          .map((p) => p.opening.id)
          .toSet();
      if (documentOpenings(loaded.document!)
          .any((p) => healthy.contains(p.opening.id) && p.status != 'ok')) {
        return const EditResult(null, '此尺寸会影响已有门窗，请先调整门窗或保留更多空间');
      }
    }
    if (['AddOpening', 'MoveOpening', 'ResizeOpening', 'SetOpeningKind']
        .contains(kind)) {
      final originalIds =
          doc.floors.expand((f) => f.openings).map((o) => o.id).toSet();
      final placements = documentOpenings(loaded.document!);
      for (final candidate in placements) {
        final changed = kind == 'AddOpening'
            ? !originalIds.contains(candidate.opening.id)
            : candidate.opening.id == args['openingId'];
        if (!changed) continue;
        if (candidate.status != 'ok') {
          return const EditResult(null, '门窗超出有效墙面，请换一个位置或调整尺寸');
        }
        for (final other in placements) {
          if (candidate.opening.id == other.opening.id || other.status != 'ok')
            continue;
          if (candidate.host?.ref == other.host?.ref &&
              candidate.start < other.end &&
              other.start < candidate.end &&
              candidate.opening.sill <
                  other.opening.sill + other.opening.height &&
              other.opening.sill <
                  candidate.opening.sill + candidate.opening.height) {
            return const EditResult(null, '与已有门窗重叠，请挪开一些');
          }
        }
      }
    }
    return EditResult(loaded.document, null);
  } catch (_) {
    return const EditResult(null, '操作参数无效，原设计已保留');
  }
}
