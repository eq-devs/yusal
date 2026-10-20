import 'dart:math' as math;
import '../document/house_document.dart';
import '../geometry/derived_house.dart';
import '../geometry/floor_base.dart';
import 'house_analysis.dart';

/// Electrical, water and heating points: a first layout room by room, and
/// the cable and pipe they need. Lengths follow the walls (right-angled
/// runs from the panel, inlet, sewer sleeve or boiler) with drops to each
/// point and 15% for bends. Pure Dart; millimetres in, metres out.

/// Electrical points per room type before the room size is considered.
const socketsPerRoom = {
  RoomType.living: 5,
  RoomType.bedroom: 4,
  RoomType.kitchen: 4,
  RoomType.dining: 3,
  RoomType.bathroom: 1,
  RoomType.custom: 2,
};

/// Furniture that needs water and a drain.
const wetFurniture = {
  FurnitureKind.sink,
  FurnitureKind.toilet,
  FurnitureKind.basin,
  FurnitureKind.shower,
  FurnitureKind.bathtub,
  FurnitureKind.washer,
};

typedef UtilitySpot = ({UtilityKind kind, int x, int y});

PlanRect? _largest(SpaceGeometry g) => g.clearRects.isEmpty
    ? null
    : g.clearRects.reduce((a, b) => a.area >= b.area ? a : b);

/// Point [inset] mm into the room from where [p] crosses its wall, at
/// [along] on the wall line.
({double x, double y}) _inside(OpeningPlacement p, FloorBase base,
    String roomId, double along, double inset) {
  final (neg, pos) = roomsBeside(p, base);
  final sign = pos == roomId ? 1.0 : neg == roomId ? -1.0 : 1.0;
  final cross = p.axis.pos + sign * ((p.host?.thickness ?? 240) / 2 + inset);
  return p.axis.dir == AxisDir.H
      ? (x: along, y: cross)
      : (x: cross, y: along);
}

/// A first layout for floor [floorIndex]: lights, switches by the doors,
/// sockets round the walls, water and drains at wet furniture, vents in
/// kitchens and bathrooms, radiators under windows and the panel by the
/// entrance. Points close to existing ones of the same kind are left out.
List<UtilitySpot> suggestUtilities(
    HouseDocument doc, DerivedHouse derived, int floorIndex) {
  final floor = doc.floors[floorIndex], g = derived.floors[floorIndex];
  final base = g.base;
  final out = <UtilitySpot>[];
  void add(UtilityKind kind, double x, double y) =>
      out.add((kind: kind, x: x.round(), y: y.round()));
  for (final room in floor.rooms) {
    final geometry = base.roomGeometry.firstWhere((r) => r.id == room.id);
    final r = _largest(geometry);
    if (r == null) continue;
    final w = r.right - r.left, d = r.top - r.bottom;
    final cx = (r.left + r.right) / 2, cy = (r.bottom + r.top) / 2;
    // Lights: two along a large room's long side; a little up from the
    // middle, where the room's name is written on the plan.
    final lift = math.min(600.0, d * 0.2);
    if (geometry.clearArea > 25e6 && math.max(w, d) > 5000) {
      for (final f in [0.25, 0.75])
        w >= d
            ? add(UtilityKind.light, r.left + w * f, cy + lift)
            : add(UtilityKind.light, cx + math.min(600.0, w * 0.2),
                r.bottom + d * f);
    } else {
      add(UtilityKind.light, cx, cy + lift);
    }
    final touching = g.openings
        .where((p) => p.status == 'ok' && openingTouches(p, base, room.id))
        .toList();
    final doors =
        touching.where((p) => p.opening.kind != OpeningKind.window).toList();
    // Switch on the latch side of the first door, inside the room.
    if (doors.isNotEmpty) {
      final p = doors.first, o = p.opening;
      final latchAtEnd = o is! DoorOpening || o.hinge == Hinge.start;
      final low = p.axis.dir == AxisDir.H ? r.left : r.bottom,
          high = p.axis.dir == AxisDir.H ? r.right : r.top;
      var along = latchAtEnd ? p.end + 150 : p.start - 150;
      if (along < low + 50 || along > high - 50)
        along = latchAtEnd ? p.start - 150 : p.end + 150;
      final at = _inside(p, base, room.id, along.clamp(low + 50, high - 50), 80);
      add(UtilityKind.lightSwitch, at.x, at.y);
    }
    // Sockets spread round the walls, clear of corners and door swings.
    var sockets = socketsPerRoom[room.type]!;
    if (geometry.clearArea < 4e6) sockets = math.min(sockets, 1);
    const inset = 100.0, step = 300.0;
    final candidates = <({double x, double y})>[];
    final edges = [
      (r.left, r.bottom + inset, r.right, r.bottom + inset),
      (r.right - inset, r.bottom, r.right - inset, r.top),
      (r.right, r.top - inset, r.left, r.top - inset),
      (r.left + inset, r.top, r.left + inset, r.bottom),
    ];
    for (final (x0, y0, x1, y1) in edges) {
      final length = (x1 - x0).abs() + (y1 - y0).abs();
      for (var s = 400.0; s <= length - 400; s += step) {
        final x = x0 + (x1 - x0) * s / length, y = y0 + (y1 - y0) * s / length;
        final blocked = doors.any((p) {
          final along = p.axis.dir == AxisDir.H ? x : y,
              cross = p.axis.dir == AxisDir.H ? y : x;
          return along > p.start - 300 &&
              along < p.end + 300 &&
              (cross - p.axis.pos).abs() < 600;
        });
        if (!blocked) candidates.add((x: x, y: y));
      }
    }
    if (candidates.isNotEmpty)
      for (var k = 0; k < sockets; k++) {
        final c = candidates[((k + 0.5) * candidates.length / sockets)
            .floor()
            .clamp(0, candidates.length - 1)];
        add(UtilityKind.socket, c.x, c.y);
      }
    // Water and drains at wet furniture, else a default pair.
    final wet = room.type == RoomType.kitchen || room.type == RoomType.bathroom;
    final fixtures = doc.extras.furniture.where((f) =>
        f.floorId == floor.id &&
        wetFurniture.contains(f.kind) &&
        geometry.clearRects.any(
            (c) => c.contains(f.x + f.width / 2, f.y + f.depth / 2)));
    for (final f in fixtures) {
      final fx = f.x + f.width / 2, fy = f.y + f.depth / 2;
      add(UtilityKind.water, fx - 100, fy);
      add(UtilityKind.drain, fx + 100, fy);
    }
    if (wet && fixtures.isEmpty) {
      final pairs = room.type == RoomType.bathroom ? 2 : 1;
      for (var k = 0; k < pairs; k++) {
        final x = k == 0 ? r.left + 400 : r.right - 400;
        add(UtilityKind.water, x, r.top - 300);
        add(UtilityKind.drain, x, r.top - 500);
      }
    }
    if (wet) add(UtilityKind.vent, r.right - 300, r.top - 300);
    // Radiators under windows in outside walls; towel rail in bathrooms.
    final windows = touching.where((p) =>
        p.opening.kind != OpeningKind.door && p.host?.kind == 'exterior');
    for (final p in windows) {
      final at = _inside(p, base, room.id, (p.start + p.end) / 2, 120);
      add(UtilityKind.radiator, at.x, at.y);
    }
    if (windows.isEmpty && room.type == RoomType.bathroom)
      add(UtilityKind.radiator, r.left + 300, cy);
  }
  // The panel inside the main entrance on the ground floor.
  if (floorIndex == 0 &&
      !doc.extras.utilities.any((u) => u.kind == UtilityKind.panel)) {
    final entrance = g.openings
        .where((p) => p.opening.id == doc.mainEntranceOpeningId)
        .firstOrNull;
    final owner = entrance == null ? null : roomsBeside(entrance, base);
    final room = owner?.$1 ?? owner?.$2;
    if (entrance != null && room != null) {
      final at = _inside(entrance, base, room, entrance.start - 400, 80);
      add(UtilityKind.panel, at.x, at.y);
    } else {
      // Inside a corner, or in the largest room when that corner is cut.
      final t = doc.defaults.outerWallThickness + 300.0;
      final rooms = [for (final g in base.roomGeometry) ...g.clearRects];
      if (base.inside(t, t) || rooms.isEmpty) {
        add(UtilityKind.panel, t, t);
      } else {
        final r = rooms.reduce((a, b) => a.area >= b.area ? a : b);
        add(UtilityKind.panel, r.left + 300, r.bottom + 300);
      }
    }
  }
  final existing = doc.extras.utilities.where((u) => u.floorId == floor.id);
  return [
    for (final s in out)
      if (!existing.any((u) =>
          u.kind == s.kind &&
          (u.x - s.x).abs() + (u.y - s.y).abs() < 300))
        s
  ];
}

class UtilityTakeoff {
  const UtilityTakeoff(
      {required this.counts,
      required this.lightCable,
      required this.powerCable,
      required this.waterPipe,
      required this.drainPipe,
      required this.heatingPipe});
  final Map<UtilityKind, int> counts;

  /// Metres: 3×1.5 mm² for lights, switches and vents; 3×2.5 mm² for
  /// sockets; cold plus hot water; drains; radiator supply plus return.
  final double lightCable, powerCable, waterPipe, drainPipe, heatingPipe;
  int count(UtilityKind k) => counts[k] ?? 0;
  int get electrical =>
      count(UtilityKind.socket) +
      count(UtilityKind.lightSwitch) +
      count(UtilityKind.light) +
      count(UtilityKind.vent);
  bool get isEmpty => counts.isEmpty;
}

UtilityTakeoff utilityTakeoff(HouseDocument doc) {
  final points = doc.extras.utilities;
  final elevation = <String, double>{};
  var z = 0.0;
  for (final f in doc.floors) {
    elevation[f.id] = z;
    z += f.height;
  }
  final height = {for (final f in doc.floors) f.id: f.height.toDouble()};
  ({double x, double y, double z}) at(String floorId, num x, num y) =>
      (x: x.toDouble(), y: y.toDouble(), z: elevation[floorId] ?? 0);
  final firstFloor = doc.floors.first.id;
  final t = doc.defaults.outerWallThickness;
  final panel = points.where((u) => u.kind == UtilityKind.panel).firstOrNull;
  final panelAt = panel == null
      ? at(firstFloor, t + 300, t + 300)
      : at(panel.floorId, panel.x, panel.y);
  final water = doc.extras.sleeves
      .where((s) => s.kind == SleeveKind.water)
      .firstOrNull;
  final sewer = doc.extras.sleeves
      .where((s) => s.kind == SleeveKind.sewer)
      .firstOrNull;
  final boiler = doc.extras.furniture
      .where((f) => f.kind == FurnitureKind.boiler)
      .firstOrNull;
  final waterAt = water == null ? panelAt : at(firstFloor, water.x, water.y),
      sewerAt = sewer == null
          ? at(firstFloor, doc.footprint.width / 2, 0)
          : at(firstFloor, sewer.x, sewer.y),
      boilerAt = boiler == null
          ? panelAt
          : at(boiler.floorId, boiler.x + boiler.width / 2,
              boiler.y + boiler.depth / 2);
  double run(({double x, double y, double z}) from, UtilityPoint u,
          double drop) =>
      (((from.x - u.x).abs() +
                  (from.y - u.y).abs() +
                  ((elevation[u.floorId] ?? 0) - from.z).abs()) *
              1.15 +
          drop) /
      1000;
  final counts = <UtilityKind, int>{};
  var light = 0.0, power = 0.0, cold = 0.0, drain = 0.0, heat = 0.0;
  for (final u in points) {
    counts[u.kind] = (counts[u.kind] ?? 0) + 1;
    final h = height[u.floorId] ?? 3000;
    switch (u.kind) {
      case UtilityKind.light || UtilityKind.vent:
        light += run(panelAt, u, 300);
      case UtilityKind.lightSwitch:
        light += run(panelAt, u, h - 1300);
      case UtilityKind.socket:
        power += run(panelAt, u, h - 300);
      case UtilityKind.water:
        cold += 2 * run(waterAt, u, 1000);
      case UtilityKind.drain:
        drain += run(sewerAt, u, 500);
      case UtilityKind.radiator:
        heat += 2 * run(boilerAt, u, 600);
      case UtilityKind.panel:
        break;
    }
  }
  return UtilityTakeoff(
      counts: Map.unmodifiable(counts),
      lightCable: light,
      powerCable: power,
      waterPipe: cold,
      drainPipe: drain,
      heatingPipe: heat);
}
