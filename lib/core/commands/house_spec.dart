import 'dart:math' as math;

import '../analysis/house_analysis.dart';
import '../axis/axis_resolver.dart';
import '../document/house_document.dart';
import '../geometry/floor_base.dart';
import 'command_contract.dart';
import 'extras_commands.dart';
import 'room_commands.dart';

/// A whole house described as data, as a language model writes it:
/// footprint, floors, rooms as rectangles, doors, windows and furniture by
/// room and side. [buildHouseFromSpec] turns it into an ordinary editable
/// design with the same commands a tap runs.
///
/// Plan coordinates are millimetres from the south-west corner: x grows
/// to the east, y to the north.
///
/// ```json
/// {"name": "Үй", "width_mm": 12000, "depth_mm": 10000, "roof": "gable",
///  "floors": [{"rooms": [
///     {"id": "liv", "type": "living", "x_mm": 0, "y_mm": 0, "w_mm": 6000, "d_mm": 5000}],
///   "doors": [{"room": "liv", "side": "south", "main": true},
///             {"room": "liv", "to": "kit"}],
///   "windows": [{"room": "liv", "side": "south", "count": 2}],
///   "open": [["liv", "din"]],
///   "furniture": [{"room": "liv", "kind": "sofa"}]}],
///  "stairs": [{"floor": 1, "x_mm": 0, "y_mm": 0, "w_mm": 1200, "d_mm": 3000}]}
/// ```
class HouseSpecResult {
  const HouseSpecResult(this.document, this.errors, this.notes);

  /// Null when the spec could not be built at all; [errors] say why.
  final HouseDocument? document;
  final List<String> errors;

  /// Parts that were left out (a door that found no wall, furniture that
  /// did not fit). The rest of the house is built.
  final List<String> notes;
}

/// Edges closer than this to another become one wall line, as the
/// editor refuses walls closer than 0.30 m.
const _merge = 300;

/// The JSON schema of a spec, offered to the language model as the
/// argument of `design.create_house`.
Map<String, Object?> houseSpecSchema() {
  Map<String, Object?> mm(String what) =>
      {'type': 'integer', 'description': '$what, millimetres'};
  final rect = {
    'x_mm': mm('west edge from the house\'s west wall'),
    'y_mm': mm('south edge from the house\'s south wall'),
    'w_mm': mm('size west to east'),
    'd_mm': mm('size south to north'),
  };
  final sides = [for (final f in Facing.values) f.name];
  return {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'width_mm': mm('house size west to east, 4000-30000'),
      'depth_mm': mm('house size south to north, 4000-30000'),
      'roof': {
        'type': 'string',
        'enum': [for (final r in RoofType.values) r.name]
      },
      'outer_wall_mm': mm('outer wall thickness, e.g. 400 for block walls'),
      'floors': {
        'type': 'array',
        'description': 'ground floor first',
        'items': {
          'type': 'object',
          'properties': {
            'height_mm': mm('floor to floor height'),
            'rooms': {
              'type': 'array',
              'description':
                  'rectangles that do not overlap and together fill the floor',
              'items': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string', 'description': 'short key, e.g. b1'},
                  'type': {
                    'type': 'string',
                    'enum': [for (final t in RoomType.values) t.name]
                  },
                  'name': {'type': 'string'},
                  ...rect,
                },
                'required': ['id', 'type', 'x_mm', 'y_mm', 'w_mm', 'd_mm'],
              },
            },
            'doors': {
              'type': 'array',
              'description':
                  'a door to another room ("to"), or in the outer wall on "side"',
              'items': {
                'type': 'object',
                'properties': {
                  'room': {'type': 'string'},
                  'to': {'type': 'string'},
                  'side': {'type': 'string', 'enum': sides},
                  'main': {
                    'type': 'boolean',
                    'description': 'the main entrance, ground floor'
                  },
                },
                'required': ['room'],
              },
            },
            'windows': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'room': {'type': 'string'},
                  'side': {'type': 'string', 'enum': sides},
                  'count': {'type': 'integer'},
                  'width_mm': mm('window width'),
                },
                'required': ['room', 'side'],
              },
            },
            'open': {
              'type': 'array',
              'description': 'pairs of rooms joined without a wall',
              'items': {
                'type': 'array',
                'items': {'type': 'string'}
              },
            },
            'furniture': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'room': {'type': 'string'},
                  'kind': {
                    'type': 'string',
                    'enum': [for (final k in FurnitureKind.values) k.name]
                  },
                },
                'required': ['room', 'kind'],
              },
            },
          },
          'required': ['rooms'],
        },
      },
      'stairs': {
        'type': 'array',
        'description': 'on the floor they start from (1 = ground)',
        'items': {
          'type': 'object',
          'properties': {
            'floor': {'type': 'integer'},
            'type': {
              'type': 'string',
              'enum': [for (final s in StairType.values) s.name]
            },
            ...rect,
          },
          'required': ['floor', 'x_mm', 'y_mm', 'w_mm', 'd_mm'],
        },
      },
    },
    'required': ['width_mm', 'depth_mm', 'floors'],
  };
}

/// Where a new opening goes: the wall of [roomId] that faces [side], and
/// the middle of the room's stretch of it ([from], [to] along the wall).
/// With [exterior], only outer walls count. Null when the room has no
/// such wall on that side.
({WallSegment wall, double tapT, double from, double to})? roomWall(
    FloorBase base, String roomId, Facing side, int northAngleDeg,
    {bool exterior = false}) {
  final a = northAngleDeg * math.pi / 180;
  ({WallSegment wall, double from, double to})? best;
  for (final wall in base.wallSegments) {
    double? from, to;
    for (final e in wall.edges) {
      if (exterior && e.kind != 'exterior') continue;
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
    tapT: (best.from + best.to) / 2 - best.wall.start.pos,
    from: best.from,
    to: best.to,
  );
}

/// The longest wall between rooms [a] and [b]: the segment, and the
/// stretch of it they share, with the unit edges of that stretch.
({WallSegment wall, double from, double to, List<UnitEdge> edges})? sharedWall(
    FloorBase base, String a, String b) {
  ({WallSegment wall, double from, double to, List<UnitEdge> edges})? best;
  for (final wall in base.wallSegments) {
    final shared = [
      for (final e in wall.edges)
        if ({base.owners[e.negative], base.owners[e.positive]}
            .containsAll([a, b]))
          e
    ];
    if (shared.isEmpty) continue;
    final from = shared.map((e) => e.start.pos).reduce(math.min).toDouble(),
        to = shared.map((e) => e.end.pos).reduce(math.max).toDouble();
    if (best == null || to - from > best.to - best.from) {
      best = (wall: wall, from: from, to: to, edges: shared);
    }
  }
  return best;
}

typedef _Rect = ({int x0, int y0, int x1, int y1});

HouseSpecResult buildHouseFromSpec(
    Map<String, Object?> spec, String timestamp, String Function() newId) {
  final errors = <String>[], notes = <String>[];
  HouseSpecResult fail(String why) =>
      HouseSpecResult(null, [...errors, why], notes);

  int? integer(Object? v) =>
      v is num && v.isFinite ? (v / 10).round() * 10 : null;
  List<Map<String, Object?>> list(Object? v) => [
        if (v is List)
          for (final item in v)
            if (item is Map) item.cast<String, Object?>()
      ];
  T? choice<T extends Enum>(List<T> values, Object? v) =>
      values.where((e) => e.name == v).firstOrNull;

  final width = integer(spec['width_mm']), depth = integer(spec['depth_mm']);
  if (width == null || depth == null)
    return fail('width_mm and depth_mm are required');
  if (width < 4000 || width > 30000 || depth < 4000 || depth > 30000) {
    return fail('width_mm and depth_mm must be 4000-30000');
  }
  final floors = list(spec['floors']);
  if (floors.isEmpty) return fail('floors needs at least one floor');
  if (floors.length > 4) return fail('at most 4 floors');

  // Every edge of every room and stair, merged into wall lines.
  final stairs = list(spec['stairs']);
  final xs = <int>{0, width}, ys = <int>{0, depth};
  _Rect? rectOf(Map<String, Object?> m, String what) {
    final x = integer(m['x_mm']), y = integer(m['y_mm']);
    final w = integer(m['w_mm']), d = integer(m['d_mm']);
    if (x == null || y == null || w == null || d == null) {
      errors.add('$what: x_mm, y_mm, w_mm and d_mm are required');
      return null;
    }
    if (x < 0 ||
        y < 0 ||
        x + w > width ||
        y + d > depth ||
        w < 600 ||
        d < 600) {
      errors
          .add('$what: must lie inside the house and be at least 600 mm wide');
      return null;
    }
    xs.addAll([x, x + w]);
    ys.addAll([y, y + d]);
    return (x0: x, y0: y, x1: x + w, y1: y + d);
  }

  final roomRects = <List<(Map<String, Object?>, _Rect)>>[];
  for (final (f, floor) in floors.indexed) {
    final rooms = <(Map<String, Object?>, _Rect)>[];
    final seen = <String>{};
    for (final room in list(floor['rooms'])) {
      final id = '${room['id'] ?? ''}';
      final what = 'floor ${f + 1} room "$id"';
      if (id.isEmpty || !seen.add(id)) {
        errors.add('$what: every room needs its own id');
        continue;
      }
      if (choice(RoomType.values, room['type']) == null) {
        errors.add('$what: unknown type ${room['type']}');
        continue;
      }
      final r = rectOf(room, what);
      if (r != null) rooms.add((room, r));
    }
    if (rooms.isEmpty) errors.add('floor ${f + 1}: no rooms');
    roomRects.add(rooms);
  }
  final stairRects = <(int, StairType, _Rect)>[];
  for (final (i, s) in stairs.indexed) {
    final on = s['floor'] is num ? (s['floor'] as num).toInt() : 0;
    if (on < 1 || on >= floors.length) {
      errors.add('stair ${i + 1}: floor must have a floor above it');
      continue;
    }
    final r = rectOf(s, 'stair ${i + 1}');
    if (r != null) {
      stairRects.add((
        on - 1,
        choice(StairType.values, s['type']) ?? StairType.straight,
        r
      ));
    }
  }
  if (errors.isNotEmpty) return HouseSpecResult(null, errors, notes);

  Map<int, int> snap(Set<int> values, int max) {
    final sorted = values.toList()..sort();
    final kept = <int>[0];
    for (final v in sorted) {
      if (v - kept.last >= _merge && max - v >= _merge) kept.add(v);
    }
    kept.add(max);
    int nearest(int v) =>
        kept.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);
    return {for (final v in values) v: nearest(v)};
  }

  final sx = snap(xs, width), sy = snap(ys, depth);
  _Rect snapped(_Rect r) =>
      (x0: sx[r.x0]!, y0: sy[r.y0]!, x1: sx[r.x1]!, y1: sy[r.y1]!);
  bool overlap(_Rect a, _Rect b) =>
      a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1;
  for (final (f, rooms) in roomRects.indexed) {
    for (var i = 0; i < rooms.length; i++) {
      final a = snapped(rooms[i].$2);
      if (a.x1 <= a.x0 || a.y1 <= a.y0) {
        errors.add('floor ${f + 1} room "${rooms[i].$1['id']}" is too small');
      }
      for (var j = i + 1; j < rooms.length; j++) {
        if (overlap(a, snapped(rooms[j].$2))) {
          errors.add(
              'floor ${f + 1}: rooms "${rooms[i].$1['id']}" and "${rooms[j].$1['id']}" overlap');
        }
      }
    }
  }
  if (errors.isNotEmpty) return HouseSpecResult(null, errors, notes);

  var doc = createHouse(
      name: '${spec['name'] ?? ''}'.trim().isEmpty
          ? '我的房屋'
          : '${spec['name']}'.trim(),
      width: width,
      depth: depth,
      columns: 1,
      rows: 1,
      timestamp: timestamp,
      newId: newId);
  final context = CommandContext(newId: newId, now: () => timestamp);
  String? run(String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        extractDesignState(doc), DesignCommand(kind, args), context);
    switch (result) {
      case Applied(:final newState):
        doc = composeDocument(doc.meta, newState);
        return null;
      case Rejected(:final message):
        return message;
      case NeedsResolution(:final conflict):
        return conflict.message;
    }
  }

  final outer = integer(spec['outer_wall_mm']);
  if (outer != null && outer >= 120 && outer <= 800) {
    run('SetDefault', {'field': 'outerWallThickness', 'value': outer});
  }
  final roof = choice(RoofType.values, spec['roof']) ?? RoofType.gable;
  run('SetRoof', {
    'roof': switch (roof) {
      RoofType.flat => {'type': 'flat', 'parapetHeight': 600},
      RoofType.hip => {'type': 'hip', 'pitchDeg': 30, 'overhang': 500},
      RoofType.gable => {
          'type': 'gable',
          // The ridge runs along the long side.
          'ridgeDir': (width >= depth ? AxisDir.H : AxisDir.V).name,
          'pitchDeg': 30,
          'overhang': 500
        },
    }
  });
  for (final x in {...sx.values}..removeAll([0, width])) {
    run('AddAxis', {'dir': AxisDir.V, 'pos': x});
  }
  for (final y in {...sy.values}..removeAll([0, depth])) {
    run('AddAxis', {'dir': AxisDir.H, 'pos': y});
  }

  List<Cell> cells(String floorId, _Rect r) {
    final axes = resolveFloorAxes(doc, floorId)!;
    return [
      for (var j = 0; j < axes.ny; j++)
        for (var i = 0; i < axes.nx; i++)
          if (axes.v[i].pos >= r.x0 &&
              axes.v[i + 1].pos <= r.x1 &&
              axes.h[j].pos >= r.y0 &&
              axes.h[j + 1].pos <= r.y1)
            Cell(i, j)
    ];
  }

  // Rooms, floor by floor; spec id → room id.
  final ids = <Map<String, String>>[];
  for (final (f, floor) in floors.indexed) {
    if (f > 0) run('AddFloor', {'floorId': doc.floors[f - 1].id});
    final floorId = doc.floors[f].id;
    final height = integer(floor['height_mm']);
    if (height != null && height >= 2400 && height <= 4500) {
      run('SetFloorHeight', {'floorId': floorId, 'value': height});
    }
    final byKey = <String, String>{};
    for (final (room, rect) in roomRects[f]) {
      final key = '${room['id']}';
      final before = doc.floors[f].rooms.map((r) => r.id).toSet();
      final why = run('PaintCells', {
        'floorId': floorId,
        'cells': cells(floorId, snapped(rect)),
        'roomType': choice(RoomType.values, room['type'])!,
      });
      final added =
          doc.floors[f].rooms.where((r) => !before.contains(r.id)).firstOrNull;
      if (why != null || added == null) {
        notes.add(
            'floor ${f + 1} room "$key" was not built: ${why ?? 'no space'}');
        continue;
      }
      byKey[key] = added.id;
      final name = '${room['name'] ?? ''}'.trim();
      if (name.isNotEmpty)
        run('RenameRoom', {'roomId': added.id, 'value': name});
    }
    ids.add(byKey);
  }
  for (final (f, type, rect) in stairRects) {
    final r = snapped(rect);
    final axes = resolveFloorAxes(doc, doc.floors[f].id)!;
    String axis(List<ResolvedAxis> list, int pos) =>
        list.firstWhere((a) => a.pos == pos).id;
    final why = run('AddStair', {
      'floorId': doc.floors[f].id,
      'type': type,
      'region': AxisRectangle(
          x0: axis(axes.v, r.x0),
          x1: axis(axes.v, r.x1),
          y0: axis(axes.h, r.y0),
          y1: axis(axes.h, r.y1)),
    });
    if (why != null) notes.add('stair on floor ${f + 1} was not built: $why');
  }

  // Walls opened between rooms come before doors, which need the walls.
  for (final (f, floor) in floors.indexed) {
    final floorId = doc.floors[f].id;
    for (final pair
        in floor['open'] is List ? floor['open'] as List : const []) {
      final keys =
          pair is List ? [for (final k in pair) '$k'] : const <String>[];
      final a = keys.isNotEmpty ? ids[f][keys.first] : null;
      final b = keys.length > 1 ? ids[f][keys[1]] : null;
      final wall = a != null && b != null
          ? sharedWall(deriveFloorBase(doc, floorId), a, b)
          : null;
      if (wall == null) {
        notes
            .add('floor ${f + 1}: ${keys.join(' and ')} share no wall to open');
        continue;
      }
      final first = wall.edges.first, last = wall.edges.last;
      final why = run('SetWallOverride', {
        'floorId': floorId,
        'anchor': BoundaryAnchor(
            axisId: first.axis.id,
            startAxisId: first.start.id,
            endAxisId: last.end.id),
        'type': 'open',
      });
      if (why != null)
        notes.add('floor ${f + 1}: ${keys.join(' and ')} not opened: $why');
    }
  }

  // Adds an opening centred at [at] along [wall], [width] wide.
  String? opening(String floorId, WallSegment wall, double at, OpeningKind kind,
      int width, String what) {
    final f = doc.floors.indexWhere((v) => v.id == floorId);
    final before = doc.floors[f].openings.map((o) => o.id).toSet();
    var why = run('AddOpening', {
      'floorId': floorId,
      'anchor': wall.ref.anchor,
      'kind': kind,
      'centerAtTap': true,
      'tapT': at - wall.start.pos,
    });
    final added =
        doc.floors[f].openings.where((o) => !before.contains(o.id)).firstOrNull;
    if (why == null && added != null && added.width != width) {
      why = run('ResizeOpening', {
        'openingId': added.id,
        'width': width,
        'height': added.height,
        'sill': added.sill
      });
      if (why != null) why = null; // the default size stays
    }
    if (why != null || added == null) {
      notes.add('$what was not added: ${why ?? 'no wall'}');
      return null;
    }
    return added.id;
  }

  String? main, firstOuterDoor;
  final north = doc.footprint.northAngleDeg;
  for (final (f, floor) in floors.indexed) {
    final floorId = doc.floors[f].id;
    for (final door in list(floor['doors'])) {
      final room = ids[f]['${door['room']}'];
      final what = 'floor ${f + 1} door of "${door['room']}"';
      if (room == null) {
        notes.add('$what: no such room');
        continue;
      }
      final base = deriveFloorBase(doc, floorId);
      final doorWidth = doc.defaults.doorWidth;
      if (door['to'] != null) {
        final other = ids[f]['${door['to']}'];
        final wall = other == null ? null : sharedWall(base, room, other);
        if (wall == null) {
          notes.add('$what to "${door['to']}": they share no wall');
          continue;
        }
        if (wall.to - wall.from < doorWidth + 200) {
          notes.add('$what to "${door['to']}": the shared wall is too short');
          continue;
        }
        opening(floorId, wall.wall, (wall.from + wall.to) / 2, OpeningKind.door,
            doorWidth, '$what to "${door['to']}"');
        continue;
      }
      final side = choice(Facing.values, door['side']);
      final spot = side == null
          ? null
          : roomWall(base, room, side, north, exterior: true);
      if (spot == null) {
        notes.add('$what: no outer wall on side ${door['side']}');
        continue;
      }
      final id = opening(floorId, spot.wall, (spot.from + spot.to) / 2,
          OpeningKind.door, math.max(doorWidth, 1000), what);
      if (id != null && f == 0) {
        firstOuterDoor ??= id;
        if (door['main'] == true) main ??= id;
      }
    }
    for (final window in list(floor['windows'])) {
      final room = ids[f]['${window['room']}'];
      final side = choice(Facing.values, window['side']);
      final what = 'floor ${f + 1} window of "${window['room']}"';
      if (room == null || side == null) {
        notes.add('$what: unknown room or side');
        continue;
      }
      final spot = roomWall(deriveFloorBase(doc, floorId), room, side, north,
          exterior: true);
      if (spot == null) {
        notes.add('$what: no outer wall on side ${side.name}');
        continue;
      }
      final count = window['count'] is num
          ? (window['count'] as num).toInt().clamp(1, 4)
          : 1;
      final share = (spot.to - spot.from) / count;
      final width = math.min(
          integer(window['width_mm']) ?? doc.defaults.windowWidth,
          (share - 400).floor());
      if (width < 400) {
        notes.add('$what: the wall is too short');
        continue;
      }
      for (var k = 0; k < count; k++) {
        opening(floorId, spot.wall, spot.from + share * (k + 0.5),
            OpeningKind.window, width, what);
      }
    }
  }
  final entrance = main ?? firstOuterDoor;
  if (entrance != null) run('SetMainEntrance', {'openingId': entrance});

  // Furniture in rows along the room's clear space, from its south-west
  // corner, so pieces do not land on top of one another.
  for (final (f, floor) in floors.indexed) {
    final floorId = doc.floors[f].id;
    final placed = <String, ({double x, double y, double row})>{};
    final base = deriveFloorBase(doc, floorId);
    for (final item in list(floor['furniture'])) {
      final room = ids[f]['${item['room']}'];
      final kind = choice(FurnitureKind.values, item['kind']);
      final what = 'floor ${f + 1} ${item['kind']} in "${item['room']}"';
      final geometry = base.roomGeometry.where((g) => g.id == room).firstOrNull;
      if (geometry == null || kind == null || geometry.clearRects.isEmpty) {
        notes.add('$what: unknown room or kind');
        continue;
      }
      final clear =
          geometry.clearRects.reduce((a, b) => a.area >= b.area ? a : b);
      final (w, d, _, _) = furnitureDefaults[kind]!;
      const gap = 100.0;
      var at = placed[room!] ??
          (x: clear.left + gap, y: clear.bottom + gap, row: 0.0);
      if (at.x + w > clear.right - gap) {
        at = (x: clear.left + gap, y: at.y + at.row + gap, row: 0.0);
      }
      if (at.x + w > clear.right - gap || at.y + d > clear.top - gap) {
        notes.add('$what: does not fit');
        continue;
      }
      final why = run('AddFurniture', {
        'floorId': floorId,
        'kind': kind,
        'x': (at.x / 10).round() * 10,
        'y': (at.y / 10).round() * 10,
      });
      if (why != null) {
        notes.add('$what: $why');
        continue;
      }
      placed[room] =
          (x: at.x + w + gap, y: at.y, row: math.max(at.row, d.toDouble()));
    }
  }
  return HouseSpecResult(doc, const [], notes);
}
