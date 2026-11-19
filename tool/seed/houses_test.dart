// Builds the house designs the backend seed publishes, with the app's own
// design core: real geometry, the takeoff behind the budget, the plan
// thumbnail and the frozen plan JSON, exactly what publishing from the
// editor sends. Run:
//
//   flutter test tool/seed/houses_test.dart --dart-define=SEED_OUT=/path/houses.json
//
// It is a plain test (no widget binding) so it can be run anywhere Flutter is.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yusal/app/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/axis/axis_resolver.dart';
import 'package:yusal/core/commands/command_contract.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/document/house_document.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/geometry/floor_base.dart';
import 'package:yusal/platform/snapshot/design_snapshot.dart';
import 'package:yusal/render2d/floor_plan_painter.dart';
import 'package:yusal/render2d/planning_names.dart';

const _out = String.fromEnvironment('SEED_OUT', defaultValue: 'houses.json');

class _Room {
  const _Room(this.type, this.name, this.cells);
  final RoomType type;
  final String name;
  final List<Cell> cells;
}

class _Spec {
  const _Spec(this.key, this.name, this.xs, this.ys, this.rooms,
      {this.roof = 'gable',
      this.upper,
      this.stair,
      this.upperName = '2 этаж',
      this.outer = 380,
      this.days = 10});
  final String key, name, roof, upperName;
  final List<int> xs, ys; // inner axis positions, mm
  final List<_Room> rooms;

  /// Rooms of the upper floor (same grid); null for one storey.
  final List<_Room>? upper;

  /// Stair cells (x0, x1, y0, y1 as axis indices) on both floors.
  final (int, int, int, int)? stair;
  final int outer;
  final int days;
}

Cell c(int x, int y) => Cell(x, y);

/// Nine houses of the pilot region, sized and laid out like the houses
/// people around Almaty actually build.
final _specs = <(_Spec, int, int)>[
  (
    const _Spec(
        'dinara',
        'Коттедж в Каскелене',
        [4000, 9000, 11500],
        [5500],
        [
          _Room(RoomType.custom, 'Гараж', [Cell(0, 0)]),
          _Room(RoomType.living, 'Гостиная',
              [Cell(1, 1), Cell(2, 1), Cell(3, 1)]),
          _Room(RoomType.kitchen, 'Кухня-столовая', [Cell(1, 0)]),
          _Room(RoomType.custom, 'Прихожая', [Cell(2, 0)]),
          _Room(RoomType.bedroom, 'Гостевая', [Cell(0, 1)]),
        ],
        upper: [
          _Room(RoomType.bedroom, 'Спальня', [Cell(0, 1)]),
          _Room(RoomType.bedroom, 'Детская', [Cell(1, 1)]),
          _Room(RoomType.bedroom, 'Детская 2', [Cell(0, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(1, 0)]),
          _Room(RoomType.custom, 'Холл', [Cell(2, 1), Cell(3, 1)]),
          _Room(RoomType.custom, 'Гардероб', [Cell(2, 0)]),
        ],
        stair: (3, 4, 0, 1),
        roof: 'hip',
        days: 9),
    14000,
    12000
  ),
  (
    const _Spec(
        'nurlan',
        'Компактный дом в Есике',
        [4200, 6400],
        [3200],
        [
          _Room(RoomType.living, 'Гостиная', [Cell(0, 1)]),
          _Room(RoomType.bedroom, 'Спальня', [Cell(2, 1)]),
          _Room(RoomType.kitchen, 'Кухня', [Cell(2, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(0, 0)]),
          _Room(RoomType.custom, 'Прихожая', [Cell(1, 0), Cell(1, 1)]),
        ],
        days: 30),
    10000,
    9000
  ),
  (
    const _Spec(
        'erlan',
        'Дом с мансардой под Алматы',
        [4500, 7000, 9000],
        [4000],
        [
          _Room(RoomType.living, 'Гостиная', [Cell(0, 1), Cell(1, 1)]),
          _Room(RoomType.kitchen, 'Кухня', [Cell(2, 1), Cell(3, 1)]),
          _Room(RoomType.bedroom, 'Спальня родителей', [Cell(0, 0)]),
          _Room(RoomType.custom, 'Прихожая', [Cell(1, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(2, 0)]),
        ],
        upper: [
          _Room(RoomType.bedroom, 'Детская', [Cell(0, 1)]),
          _Room(RoomType.bedroom, 'Кабинет', [Cell(0, 0)]),
          _Room(RoomType.custom, 'Холл',
              [Cell(1, 0), Cell(1, 1), Cell(2, 1), Cell(3, 1)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(2, 0)]),
        ],
        stair: (3, 4, 0, 1),
        upperName: 'Мансарда',
        days: 6),
    11000,
    10000
  ),
  (
    const _Spec(
        'asel',
        'Одноэтажный дом на пять комнат, Конаев',
        [3600, 7500, 11400],
        [4600],
        [
          _Room(RoomType.living, 'Гостиная', [Cell(1, 1), Cell(2, 1)]),
          _Room(RoomType.bedroom, 'Спальня', [Cell(0, 1)]),
          _Room(RoomType.bedroom, 'Детская', [Cell(3, 1)]),
          _Room(RoomType.bedroom, 'Детская 2', [Cell(3, 0)]),
          _Room(RoomType.kitchen, 'Кухня', [Cell(2, 0)]),
          _Room(RoomType.custom, 'Прихожая', [Cell(1, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(0, 0)]),
        ],
        roof: 'hip',
        days: 4),
    15000,
    10000
  ),
  (
    const _Spec(
        'timur',
        'Гостевой дом с баней',
        [3000],
        [2600],
        [
          _Room(RoomType.custom, 'Парная', [Cell(0, 0)]),
          _Room(RoomType.bathroom, 'Душевая', [Cell(0, 1)]),
          _Room(RoomType.living, 'Комната отдыха', [Cell(1, 0), Cell(1, 1)]),
        ],
        outer: 300,
        days: 12),
    8000,
    6000
  ),
  (
    const _Spec(
        'zhanar',
        'Двухэтажный дом 12 × 12',
        [4000, 8000],
        [4500, 8000],
        [
          _Room(RoomType.living, 'Гостиная', [Cell(0, 2), Cell(1, 2)]),
          _Room(RoomType.kitchen, 'Кухня', [Cell(2, 2)]),
          _Room(RoomType.dining, 'Столовая', [Cell(2, 1)]),
          _Room(RoomType.custom, 'Холл', [Cell(1, 1), Cell(1, 0)]),
          _Room(RoomType.bedroom, 'Спальня для бабушки', [Cell(0, 1)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(0, 0)]),
        ],
        upper: [
          _Room(RoomType.bedroom, 'Спальня', [Cell(0, 2), Cell(1, 2)]),
          _Room(RoomType.bedroom, 'Детская', [Cell(2, 2)]),
          _Room(RoomType.bedroom, 'Детская 2', [Cell(2, 1)]),
          _Room(RoomType.custom, 'Холл', [Cell(1, 1), Cell(1, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(0, 0)]),
          _Room(RoomType.custom, 'Гардероб', [Cell(0, 1)]),
        ],
        stair: (2, 3, 0, 1),
        days: 2),
    12000,
    12000
  ),
  (
    const _Spec(
        'madina',
        'Семейный дом с террасой',
        [4300, 8600],
        [5200],
        [
          _Room(RoomType.living, 'Гостиная', [Cell(1, 1)]),
          _Room(RoomType.kitchen, 'Кухня-столовая', [Cell(2, 1)]),
          _Room(RoomType.bedroom, 'Спальня', [Cell(0, 1)]),
          _Room(RoomType.bedroom, 'Детская', [Cell(0, 0)]),
          _Room(RoomType.custom, 'Прихожая', [Cell(1, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(2, 0)]),
        ],
        roof: 'hip',
        days: 7),
    13000,
    11000
  ),
  (
    const _Spec(
        'serik',
        'Дом на узком участке',
        [4500],
        [3400, 7200],
        [
          _Room(RoomType.living, 'Гостиная', [Cell(0, 2), Cell(1, 2)]),
          _Room(RoomType.kitchen, 'Кухня', [Cell(1, 1)]),
          _Room(RoomType.bedroom, 'Спальня', [Cell(0, 1)]),
          _Room(RoomType.custom, 'Прихожая', [Cell(1, 0)]),
          _Room(RoomType.bathroom, 'Санузел', [Cell(0, 0)]),
        ],
        days: 15),
    9000,
    12000
  ),
];

void main() {
  test('seed houses', () async {
    AppSettings.instance.lang = AppLang.ru;
    // Real glyphs on the thumbnail (tests otherwise draw boxes).
    final fonts = FontLoader(fontBody);
    for (final w in [400, 500, 600, 700]) {
      fonts.addFont(File('assets/fonts/Onest-$w.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    }
    await fonts.load();
    final mono = FontLoader('PlexMono')
      ..addFont(File('assets/fonts/IBMPlexMono-Regular.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await mono.load();
    final out = <Map<String, dynamic>>[];
    var n = 0;
    String id() => 'seed${n++}';
    final now = DateTime.utc(2026, 11, 12, 6);

    Future<void> emit(String key, HouseDocument doc) async {
      final e = extractDesign(doc, const [], nameOf: costLineName);
      final preview = await _preview(doc);
      final snap = buildSnapshot(
          projectId: 'seed-$key',
          doc: doc,
          stages: snapshotStages,
          lines: e.lines,
          summary:
              '${(e.width / 1000).toStringAsFixed(1)} × ${(e.depth / 1000).toStringAsFixed(1)} m · ${e.floors} эт. · ${e.buildingArea.toStringAsFixed(0)} m²',
          preview: preview);
      out.add({
        'key': key,
        'project_id': snap.projectId,
        'project_name': snap.projectName,
        'design_updated_at': snap.designUpdatedAt,
        'stages': snap.stages,
        'lines': [
          for (final l in snap.lines)
            {
              'name': l.name,
              'quantity': l.quantity,
              'unit': l.unit,
              'source': l.source.name,
              'stage': l.stage,
            }
        ],
        'summary': snap.summary,
        'preview': base64Encode(preview),
        'plan_json': snap.planJson,
        'area': double.parse(e.buildingArea.toStringAsFixed(1)),
        'floors': e.floors,
        'rooms': e.rooms,
        'estimated_cost': e.estimatedCost,
      });
    }

    // The Kazakh village house of the drafting page, twice: as the owner of
    // Talgar drew it and as a builder's finished job.
    for (final (key, name, days) in [
      ('aigerim', 'Дом для родителей в Талгаре', 8),
      ('bolat', 'Сельский дом 10 × 13, построили в 2025', 40),
    ]) {
      final ts = now.subtract(Duration(days: days)).toIso8601String();
      await emit(
          key,
          createKazakhTemplate(ts, id, name: name, names: const {
            'b1': 'Спальня',
            'b2': 'Детская',
            'bath': 'Санузел',
            'liv': 'Зал',
            'kit': 'Кухня',
            'cor': 'Коридор',
            'ent': 'Прихожая',
            'boil': 'Котельная',
          }));
    }
    for (final (spec, w, d) in _specs) {
      final ts = now.subtract(Duration(days: spec.days)).toIso8601String();
      await emit(spec.key, _build(spec, w, d, ts, id));
    }
    File(_out).writeAsStringSync(jsonEncode(out));
    // ignore: avoid_print
    print('wrote ${out.length} houses to $_out');
  });
}

HouseDocument _build(
    _Spec s, int width, int depth, String ts, String Function() newId) {
  var doc = createHouse(
      name: s.name,
      width: width,
      depth: depth,
      columns: 1,
      rows: 1,
      timestamp: ts,
      newId: newId);
  final context = CommandContext(newId: newId, now: () => ts);
  void run(String kind, Map<String, dynamic> args) {
    final r = executeCommand(
        extractDesignState(doc), DesignCommand(kind, args), context);
    if (r is! Applied) {
      throw StateError('${s.key}: $kind ${r is Rejected ? r.message : ''}');
    }
    doc = composeDocument(doc.meta, r.newState);
  }

  bool tryRun(String kind, Map<String, dynamic> args) {
    try {
      run(kind, args);
      return true;
    } catch (_) {
      return false;
    }
  }

  for (final (field, value) in [
    ('outerWallThickness', s.outer),
    ('innerWallThickness', 200),
    ('slabThickness', 220),
    ('doorWidth', 900),
  ]) run('SetDefault', {'field': field, 'value': value});
  run('SetRoof', {
    'roof': switch (s.roof) {
      'flat' => {'type': 'flat', 'parapetHeight': 1000},
      'hip' => {'type': 'hip', 'pitchDeg': 25, 'overhang': 500},
      _ => {
          'type': 'gable',
          'ridgeDir': width >= depth ? 'H' : 'V',
          'pitchDeg': 30,
          'overhang': 500
        },
    }
  });
  for (final x in s.xs) run('AddAxis', {'dir': AxisDir.V, 'pos': x});
  for (final y in s.ys) run('AddAxis', {'dir': AxisDir.H, 'pos': y});
  final first = doc.floors.first.id;
  run('RenameFloor', {'floorId': first, 'value': '1 этаж'});

  void paint(String floorId, List<_Room> rooms) {
    for (final r in rooms) {
      final floor = doc.floors.firstWhere((f) => f.id == floorId);
      final before = floor.rooms.map((r) => r.id).toSet();
      doc = paintCells(doc, floorId, r.cells, r.type, newId);
      final made = doc.floors
          .firstWhere((f) => f.id == floorId)
          .rooms
          .where((x) => !before.contains(x.id));
      for (final m in made)
        run('RenameRoom', {'roomId': m.id, 'value': r.name});
    }
  }

  paint(first, s.rooms);

  if (s.upper != null) {
    run('CopyFloor', {'floorId': first});
    final upper = doc.floors.last.id;
    run('RenameFloor', {'floorId': upper, 'value': s.upperName});
    // Clear the copied rooms and openings, then lay out the upper floor.
    for (final o in List.of(doc.floors.last.openings)) {
      tryRun('DeleteOpening', {'openingId': o.id});
    }
    final f = doc.floors.last;
    final all = <Cell>[];
    final axes = resolveFloorAxes(doc, upper)!;
    for (var i = 0; i < axes.v.length - 1; i++) {
      for (var j = 0; j < axes.h.length - 1; j++) {
        all.add(Cell(i, j));
      }
    }
    if (f.rooms.isNotEmpty) {
      doc = paintCells(doc, upper, all, RoomType.custom, newId, erase: true);
    }
    paint(upper, s.upper!);
    final st = s.stair!;
    for (final floorId in [first]) {
      final a = resolveFloorAxes(doc, floorId)!;
      final region = AxisRectangle(
          x0: a.v[st.$1].id,
          x1: a.v[st.$2].id,
          y0: a.h[st.$3].id,
          y1: a.h[st.$4].id);
      final placed = [
        StairType.L,
        StairType.U,
        StairType.straight
      ].any((type) => tryRun(
          'AddStair', {'floorId': floorId, 'type': type, 'region': region}));
      if (!placed) throw StateError('${s.key}: no stair fits');
    }
  }

  // Openings: one main door, windows on every outside wall of a room,
  // doors between a room and the hall / living room it opens onto.
  String? entrance;
  for (final floor in List.of(doc.floors)) {
    final ground = floor.id == first;
    final rooms = {for (final r in floor.rooms) r.id: r};
    final hubs = rooms.values
        .where((r) =>
            r.type == RoomType.living ||
            r.name.startsWith('Прихожая') ||
            r.name.startsWith('Холл') ||
            r.name.startsWith('Коридор') ||
            r.name.startsWith('Комната отдыха'))
        .map((r) => r.id)
        .toSet();
    final base = deriveFloorBase(doc, floor.id);
    WallSegment? segOf(UnitEdge e) => base.wallSegments
        .where((w) =>
            w.axis.id == e.axis.id &&
            w.start.pos <= e.start.pos &&
            w.end.pos >= e.end.pos)
        .firstOrNull;
    bool add(UnitEdge e, OpeningKind kind, int width, int height, int sill,
        {double at = 0.5}) {
      final w = segOf(e);
      if (w == null) return false;
      final len = e.end.pos - e.start.pos;
      if (len < width + 500) return false;
      final before = doc.floors
          .firstWhere((f) => f.id == floor.id)
          .openings
          .map((o) => o.id)
          .toSet();
      final center = e.start.pos + len * at;
      if (!tryRun('AddOpening', {
        'floorId': floor.id,
        'anchor': w.ref.anchor,
        'kind': kind,
        'centerAtTap': true,
        'tapT': center - w.start.pos
      })) return false;
      final id = doc.floors
          .firstWhere((f) => f.id == floor.id)
          .openings
          .firstWhere((o) => !before.contains(o.id))
          .id;
      tryRun('ResizeOpening',
          {'openingId': id, 'width': width, 'height': height, 'sill': sill});
      if (kind == OpeningKind.door &&
          ground &&
          entrance == null &&
          e.kind == 'exterior') {
        entrance = id;
      }
      return true;
    }

    // Group edges by side per room so each wall gets one opening.
    final seen = <String>{};
    final edges = List.of(base.edges)
      ..sort((a, b) =>
          (b.end.pos - b.start.pos).compareTo(a.end.pos - a.start.pos));
    // Main entrance first: the entrance hall's (or living room's) front wall.
    if (ground) {
      for (final pref in [
        'Прихожая',
        'Холл',
        'Гостиная',
        'Комната отдыха',
        'Зал'
      ]) {
        if (entrance != null) break;
        for (final e in edges) {
          if (e.kind != 'exterior') continue;
          final owner = base.owners[e.negative] ?? base.owners[e.positive];
          if (owner == null || !(rooms[owner]?.name.startsWith(pref) ?? false))
            continue;
          if (add(e, OpeningKind.door, 1000, 2100, 0, at: 0.5)) {
            seen.add('$owner:${e.axis.id}');
            break;
          }
        }
      }
    }
    for (final e in edges) {
      final a = base.owners[e.negative], b = base.owners[e.positive];
      if (e.kind == 'exterior') {
        final owner = a ?? b;
        final room = rooms[owner];
        if (room == null) continue;
        final k = '$owner:${e.axis.id}';
        if (!seen.add(k)) continue;
        if (room.name == 'Гараж') {
          add(e, OpeningKind.door, 2700, 2300, 0);
        } else if (room.type == RoomType.bathroom ||
            room.name == 'Парная' ||
            room.name == 'Котельная' ||
            room.name == 'Гардероб') {
          add(e, OpeningKind.window, 600, 600, 1500);
        } else {
          add(e, OpeningKind.window, room.type == RoomType.living ? 1800 : 1400,
              1500, 850);
        }
      } else if (e.kind == 'interior' && a != null && b != null && a != b) {
        if (!rooms.containsKey(a) || !rooms.containsKey(b)) continue;
        if (!(hubs.contains(a) || hubs.contains(b))) continue;
        final k = ([a, b]..sort()).join('|');
        if (!seen.add(k)) continue;
        add(e, OpeningKind.door, 800, 2100, 0);
      }
    }
  }
  if (entrance != null) run('SetMainEntrance', {'openingId': entrance});
  return doc;
}

/// The plan thumbnail, as the editor renders it (PNG instead of WebP, since
/// the image codec plugin is not available outside the app).
Future<List<int>> _preview(HouseDocument document) async {
  final derived = deriveHouse(document).floors.first;
  final width = document.footprint.width.toDouble(),
      depth = document.footprint.depth.toDouble();
  final size = width >= depth
      ? Size(512, 96 + 416 * depth / width)
      : Size(96 + 416 * width / depth, 512);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xfff6f7f3));
  final rooms = document.floors.first.rooms;
  FloorPlanPainter(derived.base, {for (final r in rooms) r.id: r.name},
          {for (final r in rooms) r.id: roomColors[r.type]!},
          openings: derived.openings,
          stairs: derived.stairs,
          northAngleDeg: document.footprint.northAngleDeg)
      .paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
