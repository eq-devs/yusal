/// A first draft from a few answers, with no assistant: rooms in two rows
/// along a corridor, the day rooms to the south and the bedrooms to the
/// north, as most single-family houses are laid out. The result is a
/// house spec for [buildHouseFromSpec]; everything in it can be changed
/// afterwards.
///
/// Sizes are millimetres. [names] gives room names by type for the
/// app's language; a type left out keeps the built-in name.
Map<String, Object?> wishSpec(
    {required String name,
    required int width,
    required int depth,
    required int floors,
    required int bedrooms,
    required int bathrooms,
    bool hall = true,
    bool boiler = false,
    bool storage = false,
    bool dining = false,
    Map<String, String> names = const {}}) {
  int snap(num v) => (v / 100).round() * 100;
  final two = floors >= 2;
  // A house too shallow for two rows gets one, with the corridor behind.
  final rows = depth >= 6000;
  final corridor = depth >= 9000 ? 1500 : 1200;
  var south = rows ? snap((depth - corridor) * 0.52) : depth - corridor;
  // The stair needs 3.6 m of the north row.
  if (two &&
      rows &&
      depth - corridor - south < 3600 &&
      depth - corridor >= 6300) {
    south = depth - corridor - 3600;
  }
  final north = depth - corridor - south;
  const stairWidth = 2400;
  final inner = two ? width - stairWidth : width;

  ({String type, int weight, int least}) kind(String type) => switch (type) {
        'living' => (type: type, weight: 50, least: 3300),
        'bedroom' => (type: type, weight: 34, least: 2700),
        'kitchen' => (type: type, weight: 30, least: 2400),
        'dining' => (type: type, weight: 30, least: 2400),
        'hall' => (type: type, weight: 20, least: 1800),
        'bathroom' => (type: type, weight: 19, least: 1600),
        'boiler' => (type: type, weight: 17, least: 1500),
        _ => (type: type, weight: 16, least: 1300),
      };
  int least(List<String> row) =>
      row.fold(0, (sum, type) => sum + kind(type).least);

  final floorSpecs = <Map<String, Object?>>[];
  var left = bedrooms;
  for (var f = 0; f < (two ? 2 : 1); f++) {
    final ground = f == 0;
    final day = <String>[];
    final night = <String>[];
    if (ground) {
      day.addAll([if (hall) 'hall', 'living', if (dining) 'dining', 'kitchen']);
      final here = two ? (bedrooms >= 3 ? 1 : 0) : bedrooms;
      night.addAll([
        for (var i = 0; i < here; i++) 'bedroom',
        'bathroom',
        if (!two && bathrooms >= 2) 'bathroom',
        if (boiler) 'boiler',
        if (storage) 'storage',
      ]);
      left -= here;
    } else {
      final up = (left / 2).ceil();
      night.addAll([
        for (var i = 0; i < up; i++) 'bedroom',
        if (bathrooms >= 2) 'bathroom'
      ]);
      day.addAll([for (var i = 0; i < left - up; i++) 'bedroom', 'living']);
      left = 0;
    }
    if (!rows) {
      day.addAll(night);
      night.clear();
    }
    // Bedrooms go to whichever row is less crowded for its width.
    double crowd(List<String> row, int across, [int more = 0]) =>
        (least(row) + more) / across;
    while (rows &&
        night.contains('bedroom') &&
        crowd(night, inner) > crowd(day, width, 2700)) {
      night.remove('bedroom');
      day.add('bedroom');
    }
    while (rows &&
        day.contains('bedroom') &&
        crowd(day, width) > crowd(night, inner, 2700)) {
      day.remove('bedroom');
      night.insert(0, 'bedroom');
    }

    // A house far too small for the wish keeps the rooms it cannot do
    // without.
    for (final (row, across) in [(day, rows ? width : inner), (night, inner)])
      for (final extra in ['storage', 'boiler', 'dining', 'hall']) {
        if (least(row) > across * 1.5) row.remove(extra);
      }

    final rooms = <Map<String, Object?>>[];
    final doors = <Map<String, Object?>>[];
    final windows = <Map<String, Object?>>[];
    final open = <List<String>>[];
    final furniture = <Map<String, Object?>>[];
    final counts = <String, int>{};
    void row(List<String> types, int x1, int y, int d, String side) {
      if (types.isEmpty) return;
      // Each room its least width, the rest shared out by weight; a row
      // too short for that shrinks every room alike.
      final floor = least(types),
          total = types.fold(0, (sum, t) => sum + kind(t).weight);
      var x = 0;
      for (final (i, type) in types.indexed) {
        final k = kind(type);
        final w = i == types.length - 1
            ? x1 - x
            // Rounded down, so the last room never comes up short.
            : floor > x1
                ? x1 * k.least ~/ floor ~/ 100 * 100
                : (k.least + (x1 - floor) * k.weight / total) ~/ 100 * 100;
        final n = counts[type] = (counts[type] ?? 0) + 1;
        final id = '$type$n';
        final many = [...day, ...night].where((t) => t == type).length > 1;
        // Upstairs the room people sit in is a family room.
        final label = type == 'living' && !ground
            ? names['family'] ?? names[type]
            : names[type];
        rooms.add({
          'id': id,
          'type': type,
          if (label != null) 'name': many ? '$label $n' : label,
          'x_mm': x,
          'y_mm': y,
          'w_mm': w,
          'd_mm': d
        });
        // A room mostly under the stair hall is entered from there.
        final beside = (x + w < inner ? x + w : inner) - x;
        doors.add({'room': id, 'to': two && beside < 1200 ? 'sth' : 'cor'});
        if (type == 'hall') doors.add({'room': id, 'side': side, 'main': true});
        if (type == 'dining' && counts['living'] != null) {
          open.add(['living1', id]);
        }
        if (const ['living', 'bedroom', 'kitchen', 'dining'].contains(type)) {
          windows.add({'room': id, 'side': side, 'count': w >= 4200 ? 2 : 1});
        }
        if ((type == 'bathroom' || type == 'boiler') && w >= 2000) {
          windows.add({'room': id, 'side': side, 'width_mm': 600});
        }
        furniture.addAll([
          if (type == 'living' && w >= 3300 && d >= 3000) ...[
            {'room': id, 'kind': 'sofa'},
            {'room': id, 'kind': 'tvStand'}
          ],
          if (type == 'bedroom' && w >= 2900 && d >= 3000) ...[
            {'room': id, 'kind': 'bed'},
            {'room': id, 'kind': 'wardrobe'}
          ],
          if (type == 'dining' && w >= 2900 && d >= 3000)
            {'room': id, 'kind': 'diningTable'},
        ]);
        x += w;
      }
    }

    row(day, rows ? width : inner, 0, south, 'south');
    if (rows) row(night, inner, south + corridor, north, 'north');
    rooms.add({
      'id': 'cor',
      'type': 'corridor',
      if (names['corridor'] != null) 'name': names['corridor'],
      'x_mm': 0,
      'y_mm': south,
      'w_mm': inner,
      'd_mm': corridor
    });
    if (two) {
      // The stair's own hall at the east end; the flight takes its far
      // part and starts from the part beside the corridor.
      rooms.add({
        'id': 'sth',
        'type': 'corridor',
        if (names['stair'] != null) 'name': names['stair'],
        'x_mm': inner,
        'y_mm': rows ? south : 0,
        'w_mm': stairWidth,
        'd_mm': rows ? corridor + north : depth
      });
      open.add(['cor', 'sth']);
    }
    if (ground && !hall) {
      // Into the corridor's end, clear of the living room's windows.
      doors.add({'room': 'cor', 'side': 'west', 'main': true});
    }
    floorSpecs.add({
      'rooms': rooms,
      'doors': doors,
      'windows': windows,
      'open': open,
      'furniture': furniture
    });
  }
  final flight = rows
      ? (north > 3600 ? 3600 : north)
      : (depth - corridor > 3600 ? 3600 : depth - corridor);
  return {
    'name': name,
    'width_mm': width,
    'depth_mm': depth,
    'roof': 'gable',
    'floors': floorSpecs,
    if (two)
      'stairs': [
        {
          'floor': 1,
          'x_mm': inner,
          'y_mm': rows ? depth - flight : 0,
          'w_mm': stairWidth,
          'd_mm': flight
        }
      ]
  };
}

/// Whether a draft squeezes a room people live in below 2 m, or a small
/// one below 1 m: the house is too small for what was asked.
bool wishTooSmall(Map<String, Object?> spec) {
  for (final floor in spec['floors']! as List)
    for (final room in (floor as Map)['rooms'] as List) {
      final w = (room as Map)['w_mm'] as int;
      final d = room['d_mm'] as int;
      final lived = const ['living', 'bedroom', 'kitchen', 'dining']
          .contains(room['type']);
      if (w < (lived ? 2000 : 1000) || d < (lived ? 2000 : 1000)) return true;
    }
  return false;
}
