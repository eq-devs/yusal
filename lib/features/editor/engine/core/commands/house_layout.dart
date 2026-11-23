import 'dart:convert';
import 'dart:math' as math;

import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/house_spec.dart';
import 'package:yusal/features/editor/engine/core/commands/house_wish.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';

/// What a house must have, before anyone has drawn it. Sizes are
/// millimetres.
class HouseBrief {
  const HouseBrief(
      {required this.width,
      required this.depth,
      this.floors = 1,
      this.bedrooms = 3,
      this.bathrooms = 1,
      this.hall = true,
      this.boiler = true,
      this.storage = false,
      this.dining = false,
      this.entrance});

  final int width;
  final int depth;
  final int floors;
  final int bedrooms;
  final int bathrooms;
  final bool hall;
  final bool boiler;
  final bool storage;
  final bool dining;

  /// The side the main entrance should face: north, east, south or west.
  final String? entrance;
}

/// One way to lay a brief out, built and marked.
class HousePlan {
  const HousePlan(this.layout, this.spec, this.document, this.entrance,
      this.score, this.marks);

  /// `rows` (two rows of rooms along an east-west corridor), `hub` (no
  /// corridor: the rooms open off the living room), or either with
  /// `_turned`: the same turned a quarter, the corridor north-south.
  final String layout;
  final Map<String, Object?> spec;
  final HouseDocument document;

  /// The side the main entrance faces.
  final String entrance;

  /// Higher is better; only comparable between plans of one brief.
  final int score;

  /// What the score is made of, by rule.
  final Map<String, int> marks;
}

/// The best ways this file knows to lay [brief] out, best first, at most
/// [count]. Different layouts come before the same layout mirrored, so
/// that "another one" shows a different house. Empty when the house is too
/// small for what was asked.
///
/// The same brief always gives the same plans. A plan the building rules
/// find an error in is left out; the rest are ranked by [HousePlan.marks].
List<HousePlan> housePlans(HouseBrief brief,
    {required String name,
    required String timestamp,
    required String Function() newId,
    Map<String, String> names = const {},
    int count = 3}) {
  Map<String, Object?> rows(HouseBrief b) => wishSpec(
      name: name,
      width: b.width,
      depth: b.depth,
      floors: b.floors,
      bedrooms: b.bedrooms,
      bathrooms: b.bathrooms,
      hall: b.hall,
      boiler: b.boiler,
      storage: b.storage,
      dining: b.dining,
      names: names);
  final turned = _swapped(brief);
  final drafts = <(String, Map<String, Object?>)>[
    ('rows', rows(brief)),
    ('rows_turned', _turned(rows(turned))),
    if (_hub(brief, name, names) case final hub?) ('hub', hub),
    if (_hub(turned, name, names) case final hub?) ('hub_turned', _turned(hub)),
  ];
  // Each layout four ways round, the likeliest first. Building a plan is
  // the slow part, so only as many are built as are asked for.
  final ways = <List<(String, Map<String, Object?>, int)>>[];
  for (final (layout, draft) in drafts) {
    if (wishTooSmall(draft)) continue;
    final four = [
      for (final spec in [
        draft,
        _mirrored(draft, east: true),
        _mirrored(draft, east: false),
        _mirrored(_mirrored(draft, east: true), east: false)
      ])
        (layout, spec, _total(_marks(spec, brief, warnings: 0)))
    ];
    ways.add(_sorted(four, (w) => w.$3));
  }
  final queue = [
    for (var turn = 0; turn < 4; turn++)
      ..._sorted([for (final w in ways) w[turn]], (w) => w.$3)
  ];
  final plans = <HousePlan>[];
  for (final (layout, spec, _) in queue) {
    if (plans.length == count) break;
    final built = buildHouseFromSpec(spec, timestamp, newId);
    final doc = built.document;
    if (doc == null || built.errors.isNotEmpty || built.notes.isNotEmpty) {
      continue;
    }
    final checks = runChecks(doc, deriveHouse(doc));
    if (checks.any((c) => c.level == 'error')) continue;
    final marks = _marks(spec, brief,
        warnings: checks.where((c) => c.level == 'warning').length);
    plans.add(
        HousePlan(layout, spec, doc, _entrance(spec), _total(marks), marks));
  }
  return _sorted(plans, (p) => p.score);
}

int _total(Map<String, int> marks) => marks.values.fold(0, (a, b) => a + b);

/// [items] with the highest [score] first; equals keep their order, so
/// the result never depends on the sort.
List<T> _sorted<T>(List<T> items, int Function(T) score) {
  final order = [for (var i = 0; i < items.length; i++) i]..sort((a, b) =>
      score(items[a]) != score(items[b])
          ? score(items[b]).compareTo(score(items[a]))
          : a.compareTo(b));
  return [for (final i in order) items[i]];
}

HouseBrief _swapped(HouseBrief b) => HouseBrief(
    width: b.depth,
    depth: b.width,
    floors: b.floors,
    bedrooms: b.bedrooms,
    bathrooms: b.bathrooms,
    hall: b.hall,
    boiler: b.boiler,
    storage: b.storage,
    dining: b.dining,
    entrance: b.entrance);

/// A one-storey house with no corridor: bedrooms down the west side, the
/// kitchen, bathroom and entrance down the east side, and between them a
/// living room every room opens off. Null when [b] does not fit that.
Map<String, Object?>? _hub(
    HouseBrief b, String name, Map<String, String> names) {
  if (b.floors != 1) return null;
  int snap(num v) => (v / 100).round() * 100;
  final bedWidth = snap((b.width * 0.3).clamp(2700, 4200));
  final sideWidth = snap((b.width * 0.25).clamp(2100, 3600));
  final midWidth = b.width - bedWidth - sideWidth;
  if (midWidth < 3300) return null;
  // The bedrooms that do not fit down the west side end the east one.
  final west = math.min(b.bedrooms, b.depth ~/ 2900);
  if (west == 0) return null;
  final westTypes = [for (var i = 0; i < west; i++) 'bedroom'];
  final eastTypes = [
    if (b.hall) 'hall',
    // The kitchen beside the dining room when there is one.
    if (!b.dining) 'kitchen',
    for (var i = 0; i < b.bathrooms; i++) 'bathroom',
    if (b.boiler) 'boiler',
    if (b.storage) 'storage',
    if (b.dining) 'kitchen',
    for (var i = west; i < b.bedrooms; i++) 'bedroom',
  ];
  // Each room its least depth, the rest shared out by weight.
  List<int>? stack(List<String> types) {
    final least = types.fold(0, (sum, t) => sum + wishRoom(t).least);
    final total = types.fold(0, (sum, t) => sum + wishRoom(t).weight);
    if (least > b.depth) return null;
    var used = 0;
    return [
      for (final (i, t) in types.indexed)
        if (i == types.length - 1)
          b.depth - used
        else
          () {
            final d = (wishRoom(t).least +
                    (b.depth - least) * wishRoom(t).weight / total) ~/
                100 *
                100;
            used += d;
            return d;
          }()
    ];
  }

  final westDepths = stack(westTypes);
  final eastDepths = stack(eastTypes);
  if (westDepths == null || eastDepths == null) return null;
  final dining = b.dining ? snap(b.depth * 0.38) : 0;
  if (b.dining && (dining < 2400 || b.depth - dining < 3300)) return null;
  final split = b.depth - dining;

  final rooms = <Map<String, Object?>>[];
  final doors = <Map<String, Object?>>[];
  final windows = <Map<String, Object?>>[];
  final furniture = <Map<String, Object?>>[];
  final counts = <String, int>{};
  final all = [...westTypes, ...eastTypes];
  String add(String type, int x, int y, int w, int d) {
    final n = counts[type] = (counts[type] ?? 0) + 1;
    final id = '$type$n';
    final label = names[type];
    rooms.add({
      'id': id,
      'type': type,
      if (label != null)
        'name': all.where((t) => t == type).length > 1 ? '$label $n' : label,
      'x_mm': x,
      'y_mm': y,
      'w_mm': w,
      'd_mm': d
    });
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
    return id;
  }

  final living = add('living', bedWidth, 0, midWidth, split);
  final two = midWidth >= 4200 ? 2 : 1;
  windows.add({'room': living, 'side': 'south', 'count': two});
  String? dine;
  if (b.dining) {
    dine = add('dining', bedWidth, split, midWidth, dining);
    windows.add({'room': dine, 'side': 'north', 'count': two});
  } else {
    windows.add({'room': living, 'side': 'north', 'count': two});
  }
  void column(List<String> types, List<int> depths, int x, int w, String side) {
    var y = 0;
    for (final (i, type) in types.indexed) {
      final d = depths[i];
      final id = add(type, x, y, w, d);
      // Into whichever of the two middle rooms most of it lies beside.
      doors.add({
        'room': id,
        'to': dine != null && y + d / 2 > split ? dine : living
      });
      if (type == 'hall') {
        doors.add({'room': id, 'side': 'south', 'main': true});
      }
      if (type == 'bedroom' || type == 'kitchen') {
        windows.add({'room': id, 'side': side, 'count': d >= 4200 ? 2 : 1});
      }
      if ((type == 'bathroom' || type == 'boiler') && d >= 2000) {
        windows.add({'room': id, 'side': side, 'width_mm': 600});
      }
      y += d;
    }
  }

  column(westTypes, westDepths, 0, bedWidth, 'west');
  column(eastTypes, eastDepths, bedWidth + midWidth, sideWidth, 'east');
  if (!b.hall) doors.add({'room': living, 'side': 'south', 'main': true});
  return {
    'name': name,
    'width_mm': b.width,
    'depth_mm': b.depth,
    'roof': 'gable',
    'floors': [
      {
        'rooms': rooms,
        'doors': doors,
        'windows': windows,
        'open': [
          if (dine != null) [living, dine]
        ],
        'furniture': furniture
      }
    ]
  };
}

Map<String, Object?> _copy(Map<String, Object?> spec) =>
    (jsonDecode(jsonEncode(spec)) as Map).cast<String, Object?>();

/// Every rectangle of [spec] (rooms and stairs) and every side named in it
/// (doors and windows), handed to [rect] and [side] to change in place.
void _each(Map<String, Object?> spec, void Function(Map<String, Object?>) rect,
    String Function(String) side) {
  for (final floor in spec['floors']! as List) {
    for (final room in (floor as Map)['rooms'] as List) {
      rect((room as Map).cast());
    }
    for (final key in ['doors', 'windows']) {
      for (final item in (floor[key] as List?) ?? const []) {
        if ((item as Map)['side'] case final String s) item['side'] = side(s);
      }
    }
  }
  for (final stair in (spec['stairs'] as List?) ?? const []) {
    rect((stair as Map).cast());
  }
}

/// [spec] as seen in a mirror: east and west trade places with [east],
/// north and south without.
Map<String, Object?> _mirrored(Map<String, Object?> spec,
    {required bool east}) {
  final out = _copy(spec);
  final (at, size, across) =
      east ? ('x_mm', 'w_mm', 'width_mm') : ('y_mm', 'd_mm', 'depth_mm');
  final pair = east ? const ['east', 'west'] : const ['north', 'south'];
  _each(out, (r) {
    r[at] = (out[across]! as int) - (r[at]! as int) - (r[size]! as int);
  }, (s) => pair.contains(s) ? pair[1 - pair.indexOf(s)] : s);
  return out;
}

/// [spec] with east-west and north-south exchanged: what lay along the
/// south wall lies along the west one.
Map<String, Object?> _turned(Map<String, Object?> spec) {
  final out = _copy(spec);
  void swap(Map<String, Object?> m, String a, String b) {
    final v = m[a];
    m[a] = m[b];
    m[b] = v;
  }

  swap(out, 'width_mm', 'depth_mm');
  _each(out, (r) {
    swap(r, 'x_mm', 'y_mm');
    swap(r, 'w_mm', 'd_mm');
  },
      (s) => const {
            'south': 'west',
            'west': 'south',
            'north': 'east',
            'east': 'north'
          }[s]!);
  return out;
}

/// The side the main entrance of [spec] faces.
String _entrance(Map<String, Object?> spec) {
  for (final door
      in ((spec['floors']! as List).first as Map)['doors'] as List) {
    if ((door as Map)['main'] == true) return door['side'] as String;
  }
  return '';
}

/// The marks of a plan, by rule. These are a first guess at what makes a
/// plan good and are meant to be tuned by someone who builds houses here.
Map<String, int> _marks(Map<String, Object?> spec, HouseBrief brief,
    {required int warnings}) {
  const lived = ['living', 'bedroom', 'kitchen', 'dining'];
  var area = 0;
  var passage = 0;
  var shape = 0;
  var size = 0;
  var privacy = 0;
  var wet = 0;
  var sun = 0;
  for (final (f, floor) in (spec['floors']! as List).indexed) {
    final rooms = [
      for (final r in (floor as Map)['rooms'] as List)
        (r as Map).cast<String, Object?>()
    ];
    final byId = {for (final r in rooms) r['id']: r};
    for (final r in rooms) {
      final w = r['w_mm']! as int;
      final d = r['d_mm']! as int;
      final type = r['type'];
      area += w * d;
      if (type == 'corridor') passage += w * d;
      if (lived.contains(type)) {
        // Long thin rooms are hard to furnish.
        final ratio = math.max(w, d) / math.min(w, d);
        if (ratio > 2) shape -= math.min(15, ((ratio - 2) * 10).round());
      }
      final m2 = w * d / 1e6;
      if (type == 'bedroom' && m2 < 9) size -= 8;
      if (type == 'living' && m2 < 16) size -= 10;
      if (type == 'kitchen' && m2 < 6) size -= 5;
    }
    for (final door in (floor['doors'] as List?) ?? const []) {
      final from = byId[(door as Map)['room']]?['type'];
      final to = byId[door['to']]?['type'];
      final pair = {from, to};
      // A bathroom should not open onto where people eat and sit, and a
      // bedroom is quieter off a corridor.
      if (pair.contains('bathroom') &&
          pair.intersection({'living', 'dining', 'kitchen'}).isNotEmpty) {
        privacy -= 5;
      }
      if (pair.containsAll(['bedroom', 'living'])) privacy -= 2;
    }
    // Rooms with water next to each other share pipes.
    final pipes = [
      for (final r in rooms)
        if (const ['kitchen', 'bathroom', 'boiler'].contains(r['type'])) r
    ];
    for (final (i, a) in pipes.indexed) {
      for (final b in pipes.skip(i + 1)) {
        if (_touch(a, b)) wet = math.min(8, wet + 4);
      }
    }
    if (f == 0) {
      for (final w in (floor['windows'] as List?) ?? const []) {
        if (byId[(w as Map)['room']]?['type'] != 'living') continue;
        final marks = switch (w['side']) { 'south' => 8, 'north' => 0, _ => 4 };
        sun = math.max(sun, marks);
      }
    }
  }
  return {
    'base': 100,
    'passage': -(passage * 100 / area).round(),
    'shape': shape,
    'size': size,
    'privacy': privacy,
    'wet': wet,
    'sun': sun,
    'warnings': -3 * warnings,
    if (brief.entrance != null)
      'entrance': _entrance(spec) == brief.entrance ? 30 : 0,
  };
}

/// Whether two rooms share a stretch of wall.
bool _touch(Map<String, Object?> a, Map<String, Object?> b) {
  int v(Map<String, Object?> m, String k) => m[k]! as int;
  final overlapX =
      math.min(v(a, 'x_mm') + v(a, 'w_mm'), v(b, 'x_mm') + v(b, 'w_mm')) -
          math.max(v(a, 'x_mm'), v(b, 'x_mm'));
  final overlapY =
      math.min(v(a, 'y_mm') + v(a, 'd_mm'), v(b, 'y_mm') + v(b, 'd_mm')) -
          math.max(v(a, 'y_mm'), v(b, 'y_mm'));
  return overlapX == 0 && overlapY > 0 || overlapY == 0 && overlapX > 0;
}
