import '../document/house_document.dart';
import '../axis/axis_resolver.dart';
import '../geometry/floor_base.dart';
import 'command_contract.dart';
import 'room_commands.dart';

/// The one-storey 10 × 13 m village house from the drafting page: a
/// 400 mm load-bearing spine, bedrooms on the west, living room, kitchen,
/// corridor, entrance and a 4 m² boiler room, furnished in the Kazakh way.
/// Everything in it is an ordinary editable design.
///
/// [names] gives room names in the user's language, keyed b1, b2, bath,
/// liv, kit, cor, ent, boil.
HouseDocument createKazakhTemplate(
    String timestamp, String Function() newId,
    {String name = '哈萨克乡村住宅', Map<String, String> names = const {}}) {
  var doc = createHouse(
      name: name,
      width: 10000,
      depth: 13000,
      columns: 1,
      rows: 1,
      timestamp: timestamp,
      newId: newId);
  final context = CommandContext(newId: newId, now: () => timestamp);
  void run(String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        extractDesignState(doc), DesignCommand(kind, args), context);
    if (result is! Applied)
      throw StateError('kz template: $kind ${result is Rejected ? result.message : ''}');
    doc = composeDocument(doc.meta, result.newState);
  }

  for (final (field, value) in [
    ('outerWallThickness', 400),
    ('innerWallThickness', 200),
    ('slabThickness', 220),
    ('doorWidth', 800),
  ]) run('SetDefault', {'field': field, 'value': value});
  run('SetRoof', {
    'roof': {'type': 'flat', 'parapetHeight': 1000}
  });
  for (final x in [4200, 5900, 7300]) run('AddAxis', {'dir': AxisDir.V, 'pos': x});
  for (final y in [2300, 2700, 7700]) run('AddAxis', {'dir': AxisDir.H, 'pos': y});
  final floorId = doc.floors.first.id;
  String axis(AxisDir dir, int pos) =>
      doc.axes.global.firstWhere((a) => a.dir == dir && a.pos == pos).id;

  // Columns x: 0 | 4200 | 5900 | 7300 | 10000; rows y: 0 | 2300 | 2700 | 7700 | 13000.
  final rooms = <String, (RoomType, List<Cell>, int)>{
    'liv': (RoomType.living, const [Cell(1, 3), Cell(2, 3), Cell(3, 3)], 26),
    'b1': (RoomType.bedroom, const [Cell(0, 3)], 17),
    'b2': (RoomType.bedroom, const [Cell(0, 2)], 15),
    'bath': (RoomType.bathroom, const [Cell(0, 0), Cell(0, 1)], 7),
    'kit': (
      RoomType.kitchen,
      const [Cell(2, 1), Cell(3, 1), Cell(2, 2), Cell(3, 2)],
      16
    ),
    'cor': (RoomType.custom, const [Cell(1, 1), Cell(1, 2)], 9),
    'ent': (RoomType.custom, const [Cell(1, 0), Cell(2, 0)], 5),
    'boil': (RoomType.custom, const [Cell(3, 0)], 4),
  };
  final roomIds = <String, String>{};
  for (final entry in rooms.entries) {
    final before = doc.floors.first.rooms.map((r) => r.id).toSet();
    doc = paintCells(doc, floorId, entry.value.$2, entry.value.$1, newId);
    roomIds[entry.key] = doc.floors.first.rooms
        .firstWhere((r) => !before.contains(r.id))
        .id;
  }
  for (final entry in names.entries)
    if (roomIds[entry.key] != null)
      run('RenameRoom', {'roomId': roomIds[entry.key], 'value': entry.value});

  // The spine wall is load-bearing: 400 mm on its whole length.
  run('SetWallOverride', {
    'floorId': floorId,
    'anchor': BoundaryAnchor(
        axisId: axis(AxisDir.V, 4200), startAxisId: '@bottom', endAxisId: '@top'),
    'type': 'thickness',
    'value': 400
  });
  // The corridor opens to the living room and to the entrance.
  for (final y in [7700, 2300])
    run('SetWallOverride', {
      'floorId': floorId,
      'anchor': BoundaryAnchor(
          axisId: axis(AxisDir.H, y),
          startAxisId: axis(AxisDir.V, 4200),
          endAxisId: axis(AxisDir.V, 5900)),
      'type': 'open',
    });

  // Openings: wall axis, from, to (mm along the wall), kind, sill, height.
  final openings = <(String, AxisDir?, int, int, int, OpeningKind, int, int)>[
    ('@top', null, 0, 1200, 2800, OpeningKind.window, 900, 1400),
    ('@left', null, 0, 9000, 11100, OpeningKind.window, 900, 1400),
    ('@left', null, 0, 4300, 6100, OpeningKind.window, 900, 1400),
    ('@right', null, 0, 4400, 6200, OpeningKind.window, 900, 1400),
    ('@bottom', null, 0, 1300, 2700, OpeningKind.window, 1400, 800),
    ('@bottom', null, 0, 8300, 9300, OpeningKind.window, 1100, 1100),
    ('@bottom', null, 0, 6500, 7100, OpeningKind.window, 1100, 1100),
    ('@top', null, 0, 5300, 8800, OpeningKind.window, 600, 1800),
    ('@bottom', null, 0, 4600, 5600, OpeningKind.door, 0, 2100),
    ('@right', null, 0, 1100, 2000, OpeningKind.door, 0, 2100),
    ('', AxisDir.V, 4200, 8000, 8800, OpeningKind.door, 0, 2100),
    ('', AxisDir.V, 4200, 3600, 4400, OpeningKind.door, 0, 2100),
    ('', AxisDir.V, 4200, 1300, 2100, OpeningKind.door, 0, 2100),
    ('', AxisDir.V, 5900, 2500, 3300, OpeningKind.door, 0, 2100),
    ('', AxisDir.V, 7300, 600, 1400, OpeningKind.door, 0, 2100),
  ];
  String? entrance;
  for (final (boundary, dir, pos, a0, a1, kind, sill, height) in openings) {
    final base = deriveFloorBase(doc, floorId);
    final axisId = boundary.isNotEmpty ? boundary : axis(dir!, pos);
    final wall = base.wallSegments.firstWhere((w) =>
        w.axis.id == axisId && w.start.pos <= a0 && w.end.pos >= a1);
    final before = doc.floors.first.openings.map((o) => o.id).toSet();
    run('AddOpening', {
      'floorId': floorId,
      'anchor': wall.ref.anchor,
      'kind': kind,
      'centerAtTap': true,
      'tapT': (a0 + a1) / 2 - wall.start.pos
    });
    final id = doc.floors.first.openings
        .firstWhere((o) => !before.contains(o.id))
        .id;
    run('ResizeOpening',
        {'openingId': id, 'width': a1 - a0, 'height': height, 'sill': sill});
    run('MoveOpening', {
      'openingId': id,
      'position': {'type': 'fromStart', 'd': a0 - wall.start.pos}
    });
    if (boundary == '@bottom' && kind == OpeningKind.door) entrance = id;
  }
  if (entrance != null) run('SetMainEntrance', {'openingId': entrance});

  // Furniture, in the drafting page's metres measured down the drawing.
  void item(FurnitureKind kind, double x0, double z0, double x1, double z1,
      double h,
      {double y0 = 0, int v = 0, String? label}) {
    run('AddFurniture', {
      'floorId': floorId,
      'kind': kind,
      'x': (x0 * 1000).round(),
      'y': (13000 - z1 * 1000).round(),
      'width': ((x1 - x0) * 1000).round(),
      'depth': ((z1 - z0) * 1000).round(),
      'height': (h * 1000).round(),
      'elevation': (y0 * 1000).round(),
      'variant': v,
      if (label != null) 'label': label,
    });
  }

  const k = FurnitureKind.values;
  FurnitureKind f(String name) => k.byName(name);
  item(f('terrace'), 4.6, -2.6, 9.4, 0, 0.1);
  item(f('porch'), 3.6, 13.0, 6.6, 14.6, 0.15);
  item(f('rug'), 5.0, 1.0, 9.2, 4.6, 0.015);
  item(f('dastarkhan'), 6.4, 2.1, 7.8, 3.5, 0.35);
  item(f('korpe'), 5.2, 1.4, 5.85, 4.2, 0.08);
  item(f('korpe'), 8.35, 1.4, 9.0, 4.2, 0.08, v: 1);
  item(f('korpe'), 6.0, 1.05, 8.2, 1.65, 0.08, v: 2);
  for (final (x, z, v) in [
    (5.2, 1.5, 1),
    (5.2, 2.6, 2),
    (5.2, 3.6, 0),
    (8.75, 1.5, 2),
    (8.75, 2.6, 0),
    (8.75, 3.6, 1),
  ]) item(f('cushion'), x, z, x + 0.25, z + 0.5, 0.3, y0: 0.08, v: v);
  item(f('wallRug'), 9.56, 1.3, 9.6, 4.3, 1.8, y0: 0.5);
  item(f('sandyq'), 8.3, 4.6, 9.5, 5.18, 0.55);
  item(f('rug'), 0.8, 0.9, 3.6, 4.0, 0.015, v: 1);
  item(f('bed'), 2.0, 1.6, 4.0, 3.2, 0.5);
  item(f('wallRug'), 3.96, 1.3, 4.0, 3.5, 1.5, y0: 0.7, v: 1);
  item(f('sandyq'), 0.5, 4.6, 1.7, 5.18, 0.55, v: 1);
  item(f('rug'), 0.8, 6.2, 3.6, 9.5, 0.015, v: 2);
  item(f('bed'), 2.0, 6.6, 4.0, 8.2, 0.5);
  item(f('wallRug'), 3.96, 6.3, 4.0, 8.5, 1.5, y0: 0.7);
  item(f('sandyq'), 0.45, 9.6, 1.65, 10.18, 0.55);
  item(f('alasha'), 4.6, 5.6, 5.6, 9.6, 0.012);
  item(f('alasha'), 4.6, 10.0, 5.6, 11.4, 0.012);
  item(f('hooks'), 4.4, 9.9, 4.46, 10.75, 0.25, y0: 1.45);
  item(f('counter'), 6.0, 5.4, 9.0, 6.0, 0.9);
  item(f('counter'), 9.0, 5.4, 9.6, 8.8, 0.9);
  item(f('stove'), 9.03, 5.6, 9.57, 6.4, 0.94);
  item(f('sink'), 9.05, 7.4, 9.55, 8.0, 0.93);
  item(f('fridge'), 9.0, 9.0, 9.6, 9.7, 1.9);
  item(f('pantry'), 9.0, 9.7, 9.6, 10.6, 2.2);
  item(f('shelf'), 7.2, 10.2, 9.0, 10.6, 2.2);
  item(f('diningTable'), 6.9, 6.9, 7.8, 9.0, 0.75);
  item(f('bench'), 6.45, 6.9, 6.8, 9.0, 0.45);
  item(f('bench'), 7.9, 6.9, 8.25, 9.0, 0.45);
  item(f('bathtub'), 0.4, 11.9, 2.1, 12.6, 0.55);
  item(f('toilet'), 2.4, 11.9, 2.8, 12.6, 0.42);
  item(f('basin'), 3.0, 12.15, 3.6, 12.6, 0.85);
  item(f('washer'), 0.4, 10.4, 1.0, 11.0, 0.85);
  item(f('boiler'), 8.5, 10.8, 9.3, 11.2, 0.8, y0: 1.0);
  item(f('wardrobe'), 5.9, 10.8, 7.2, 11.4, 2.2);

  for (final entry in rooms.entries)
    run('SetRoomInfo',
        {'roomId': roomIds[entry.key], 'labelArea': entry.value.$3 * 100});
  for (final (x, y, d, kind) in [
    (2600, 200, 110, SleeveKind.sewer),
    (9800, 5300, 110, SleeveKind.sewer),
    (7800, 200, 50, SleeveKind.water),
    (9800, 700, 50, SleeveKind.power),
  ]) run('AddSleeve', {'x': x, 'y': y, 'diameter': d, 'kind': kind});
  return doc;
}
