import 'dart:math' as math;

import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/axis/axis_resolver.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';

/// The open design as a few lines of text for the language model: the
/// house, then the floor being edited with one line per room (where it
/// is, how big, which sides are outer walls, its doors, windows and
/// furniture), which rooms touch, the other floors, what is selected and
/// what the checks found.
///
/// Positions are plan millimetres from the south-west corner, x to the
/// east and y to the north, as in a house spec. [aliases] maps ids to the
/// short names the model uses (r1, o3, u2); things without one are left
/// out.
///
/// ```
/// house 10000x13000 mm, 1 floor, roof flat
/// floor f1 "1 қабат" height 3000
///  r1 living "Қонақ бөлме" x4200 y7700 5800x5300 26.1m2 | outer north,east | doors o11>r6 | windows o1 north w1600 | furniture sofa u1, cushion u2 u3
/// beside: r1-r2 west, r1-r6 south
/// selected: r1
/// ```
String designScene({
  required HouseDocument doc,
  required DerivedHouse derived,
  required int floorIndex,
  required Map<String, String> aliases,
  String? selectedId,
}) {
  final floor = doc.floors[floorIndex];
  final level = derived.floors[floorIndex];
  final base = level.base;
  final north = doc.footprint.northAngleDeg;
  final out = StringBuffer()
    ..writeln('house ${doc.footprint.width}x${doc.footprint.depth} mm, '
        '${doc.floors.length} ${doc.floors.length == 1 ? 'floor' : 'floors'}, '
        'roof ${doc.roof.type.name}')
    ..writeln('floor ${aliases[floor.id]} "${floor.name}" '
        'height ${floor.height}');

  final v = base.axes.v;
  final h = base.axes.h;
  String? roomAt(double x, double y) {
    final i = v.indexWhere((a) => a.pos > x) - 1;
    final j = h.indexWhere((a) => a.pos > y) - 1;
    return i < 0 || j < 0 ? null : base.owners[Cell(i, j)];
  }

  // Rooms that share a wall, and on which side the second lies.
  final beside = <String>{};
  final outer = <String, Set<Facing>>{};
  for (final e in base.edges) {
    final a = e.negative == null ? null : base.owners[e.negative];
    final b = e.positive == null ? null : base.owners[e.positive];
    // From the negative side to the positive one, in plan coordinates.
    final (dx, dy) = e.axis.dir == AxisDir.V ? (1.0, 0.0) : (0.0, 1.0);
    if (e.kind == 'exterior') {
      if (a != null) (outer[a] ??= {}).add(_facing(dx, dy, north));
      if (b != null) (outer[b] ??= {}).add(_facing(-dx, -dy, north));
    } else if (a != null && b != null && a != b) {
      final x = aliases[a];
      final y = aliases[b];
      if (x != null && y != null) {
        beside.add('$x-$y ${_facing(dx, dy, north).name}');
      }
    }
  }

  for (final room in floor.rooms) {
    final name = aliases[room.id];
    final cells = [
      for (final e in base.owners.entries)
        if (e.value == room.id) e.key
    ];
    if (name == null || cells.isEmpty) continue;
    final x0 = cells.map((c) => v[c.i].pos).reduce(math.min);
    final y0 = cells.map((c) => h[c.j].pos).reduce(math.min);
    final x1 = cells.map((c) => v[c.i + 1].pos).reduce(math.max);
    final y1 = cells.map((c) => h[c.j + 1].pos).reduce(math.max);
    var area = 0.0;
    for (final c in cells) {
      area += (v[c.i + 1].pos - v[c.i].pos) * (h[c.j + 1].pos - h[c.j].pos);
    }
    final box = (x1 - x0) * (y1 - y0);
    out.write(' $name ${room.type.name} "${room.name}" '
        'x$x0 y$y0 ${x1 - x0}x${y1 - y0} '
        '${(area / 1e6).toStringAsFixed(1)}m2');
    // The numbers are the box around a room that is not a rectangle.
    if (area < box * 0.99) out.write(' (L-shaped, box given)');
    final sides = [
      for (final f in Facing.values)
        if (outer[room.id]?.contains(f) ?? false) f.name
    ];
    out.write(' | outer ${sides.isEmpty ? 'none' : sides.join(',')}');

    final doors = <String>[];
    final windows = <String>[];
    for (final p in level.openings) {
      final o = aliases[p.opening.id];
      if (o == null || !openingTouches(p, base, room.id)) continue;
      final (neg, pos) = roomsBeside(p, base);
      final other = neg == room.id ? pos : neg;
      final facing = facingOf(p, base, north);
      final where = other != null
          ? '>${aliases[other] ?? '?'}'
          : facing == null
              ? ''
              : ' ${facing.name}';
      final main = p.opening.id == doc.mainEntranceOpeningId ? ' main' : '';
      (p.opening is WindowOpening ? windows : doors)
          .add('$o$where w${p.opening.width}$main');
    }
    if (doors.isNotEmpty) out.write(' | doors ${doors.join(', ')}');
    if (windows.isNotEmpty) out.write(' | windows ${windows.join(', ')}');

    // Furniture by kind, so six cushions are one entry.
    final kinds = <String, List<String>>{};
    for (final f in doc.extras.furniture) {
      final u = aliases[f.id];
      if (u == null ||
          f.floorId != floor.id ||
          roomAt(f.x + f.width / 2, f.y + f.depth / 2) != room.id) {
        continue;
      }
      (kinds[f.kind.name] ??= []).add(u);
    }
    if (kinds.isNotEmpty) {
      out.write(' | furniture ${[
        for (final e in kinds.entries) '${e.key} ${e.value.join(' ')}'
      ].join(', ')}');
    }
    out.writeln();
  }
  // Stairs stand in a room and stay open to it; the hole they come up
  // through on the floor above has to stay clear of walls and furniture.
  for (final stair in floor.stairs) {
    final name = aliases[stair.id];
    final r = resolveRect(base.axes, stair.region).rect;
    if (name == null || r == null) continue;
    final fits =
        level.stairs.where((s) => s.stairId == stair.id).firstOrNull?.fits ??
            true;
    out.writeln(' $name stair ${stair.type.name} x${r.left} y${r.bottom} '
        '${r.right - r.left}x${r.top - r.bottom}'
        '${fits ? '' : ' (too small to climb)'}');
  }
  if (floorIndex > 0) {
    for (final s in derived.floors[floorIndex - 1].stairs) {
      final o = s.opening;
      out.writeln(' stair opening from the floor below x${o.left.round()} '
          'y${o.bottom.round()} ${(o.right - o.left).round()}x'
          '${(o.top - o.bottom).round()} (keep clear)');
    }
  }
  if (base.unassignedNominalArea > 0) {
    out.writeln('no room yet on '
        '${(base.unassignedNominalArea / 1e6).toStringAsFixed(1)}m2');
  }
  if (beside.isNotEmpty) out.writeln('beside: ${beside.join(', ')}');
  for (final (i, other) in doc.floors.indexed) {
    if (i == floorIndex) continue;
    out.writeln('other floor ${aliases[other.id]} "${other.name}": '
        '${other.rooms.length} rooms');
  }
  if (aliases[selectedId] case final selected?) {
    out.writeln('selected: $selected');
  }
  final issues = [
    for (final c in runChecks(doc, derived))
      if (c.level != 'info') '${c.ruleId} ${c.level}: ${c.message}'
  ];
  if (issues.isNotEmpty) {
    out.writeln('issues (${issues.length}): ${issues.take(5).join('; ')}');
  }
  return out.toString().trimRight();
}

/// The compass side the plan direction ([dx], [dy]) points to; north on
/// the plan is (sin a, cos a), a = [northAngleDeg].
Facing _facing(double dx, double dy, int northAngleDeg) {
  final a = northAngleDeg * math.pi / 180;
  final dn = dx * math.sin(a) + dy * math.cos(a);
  final de = dx * math.cos(a) - dy * math.sin(a);
  return dn.abs() >= de.abs()
      ? (dn >= 0 ? Facing.north : Facing.south)
      : (de >= 0 ? Facing.east : Facing.west);
}
