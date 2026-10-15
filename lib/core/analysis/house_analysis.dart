import 'dart:math' as math;
import '../document/house_document.dart';
import '../geometry/floor_base.dart';
import '../geometry/derived_house.dart';

/// Construction reading of a derived house: which walls carry load, where
/// the foundation strips run, what each opening faces, and the quantities.
/// Pure Dart; every length is in millimetres.

enum WallRole { exterior, bearing, partition, temporary }

enum Facing { north, east, south, west }

class WallInfo {
  const WallInfo(this.segment, this.rect, this.role);
  final WallSegment segment;
  final PlanRect rect;
  final WallRole role;
  bool get horizontal => segment.axis.dir == AxisDir.H;
  double get length =>
      horizontal ? rect.right - rect.left : rect.top - rect.bottom;
  double get thickness => segment.thickness;
  bool get carriesLoad => role == WallRole.exterior || role == WallRole.bearing;
}

List<WallInfo> wallsOf(FloorBase base, FoundationSpec spec) => [
      for (var i = 0; i < base.wallSegments.length; i++)
        WallInfo(
            base.wallSegments[i],
            base.wallRects[i],
            switch (base.wallSegments[i]) {
              final s when s.kind == 'exterior' => WallRole.exterior,
              final s when s.kind == 'temporary' => WallRole.temporary,
              final s when s.thickness >= spec.bearingMin => WallRole.bearing,
              _ => WallRole.partition
            })
    ];

/// Area covered by [rects], overlaps counted once.
double unionArea(List<PlanRect> rects) {
  if (rects.isEmpty) return 0;
  final xs = {for (final r in rects) ...[r.left, r.right]}.toList()..sort();
  final ys = {for (final r in rects) ...[r.bottom, r.top]}.toList()..sort();
  var area = 0.0;
  for (var i = 0; i < xs.length - 1; i++)
    for (var j = 0; j < ys.length - 1; j++) {
      final x = (xs[i] + xs[i + 1]) / 2, y = (ys[j] + ys[j + 1]) / 2;
      if (rects.any((r) => r.contains(x, y)))
        area += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
    }
  return area;
}

/// Room ids on the two sides of an opening (null outside the house).
(String?, String?) roomsBeside(OpeningPlacement p, FloorBase base) {
  final mid = (p.start + p.end) / 2;
  for (final e in base.edges) {
    if (e.axis.id != p.axis.id || e.start.pos > mid || e.end.pos < mid)
      continue;
    return (
      e.negative == null ? null : base.owners[e.negative],
      e.positive == null ? null : base.owners[e.positive]
    );
  }
  return (null, null);
}

/// Compass side an exterior opening looks to. North on the plan points
/// along (sin a, cos a) in plan coordinates, a = [northAngleDeg].
Facing? facingOf(OpeningPlacement p, FloorBase base, int northAngleDeg) {
  final (neg, pos) = roomsBeside(p, base);
  if (p.host?.kind != 'exterior' && !(p.axis.kind == 'boundary')) return null;
  // Outward normal in plan coordinates.
  final out = switch (p.axis.id) {
    '@left' => (-1.0, 0.0),
    '@right' => (1.0, 0.0),
    '@bottom' => (0.0, -1.0),
    '@top' => (0.0, 1.0),
    _ => p.axis.dir == AxisDir.V
        ? (neg == null ? -1.0 : 1.0, 0.0)
        : (0.0, neg == null ? -1.0 : 1.0)
  };
  if (neg != null && pos != null) return null;
  final a = northAngleDeg * math.pi / 180;
  final n = (math.sin(a), math.cos(a)), e = (math.cos(a), -math.sin(a));
  final dn = out.$1 * n.$1 + out.$2 * n.$2, de = out.$1 * e.$1 + out.$2 * e.$2;
  if (dn.abs() >= de.abs()) return dn >= 0 ? Facing.north : Facing.south;
  return de >= 0 ? Facing.east : Facing.west;
}

class RoomStats {
  const RoomStats(this.room, this.geometry, this.clearWidth, this.clearDepth,
      this.windows, this.windowArea, this.volume);
  final Room room;
  final SpaceGeometry geometry;

  /// Net size of the largest clear rectangle.
  final double clearWidth, clearDepth;
  final List<OpeningPlacement> windows;
  final double windowArea, volume;
  double get area => geometry.clearArea;

  /// Floor area per unit of window area: 7 means 1 : 7.
  double? get floorPerWindow => windowArea <= 0 ? null : area / windowArea;
}

bool openingTouches(OpeningPlacement p, FloorBase base, String roomId) =>
    base.edges.any((e) =>
        e.axis.id == p.axis.id &&
        e.start.pos < p.end &&
        p.start < e.end.pos &&
        (base.owners[e.negative] == roomId ||
            base.owners[e.positive] == roomId));

RoomStats roomStats(Room room, DerivedFloor floor, int floorHeight) {
  final base = floor.base;
  final g = base.roomGeometry.firstWhere((x) => x.id == room.id);
  final largest = g.clearRects.isEmpty
      ? null
      : g.clearRects.reduce((a, b) => a.area >= b.area ? a : b);
  final windows = floor.openings
      .where((p) =>
          p.status == 'ok' &&
          p.opening.kind != OpeningKind.door &&
          openingTouches(p, base, room.id))
      .toList();
  return RoomStats(
      room,
      g,
      largest == null ? 0 : largest.right - largest.left,
      largest == null ? 0 : largest.top - largest.bottom,
      windows,
      windows.fold(
          0.0, (s, p) => s + p.opening.width * p.opening.height.toDouble()),
      g.clearArea * floorHeight);
}

class FoundationStrip {
  const FoundationStrip(this.wall, this.rect, this.cushion, this.width,
      this.height, this.exists);
  final WallInfo wall;
  final PlanRect rect, cushion;
  final int width, height;

  /// Partition strips only exist when the spec includes them.
  final bool exists;
  bool get main => wall.carriesLoad;
}

class FoundationTakeoff {
  const FoundationTakeoff({
    required this.strips,
    required this.mainLength,
    required this.partitionLength,
    required this.concrete,
    required this.mainBarLength,
    required this.partitionBarLength,
    required this.stirrups,
    required this.stirrupLength,
    required this.partitionStirrups,
    required this.partitionStirrupLength,
    required this.excavation,
    required this.cushion,
    required this.formwork,
    required this.xps,
    required this.blinding,
    required this.waterproofing,
  });
  final List<FoundationStrip> strips;

  /// Lengths in mm; areas in mm²; volumes in mm³.
  final double mainLength,
      partitionLength,
      concrete,
      mainBarLength,
      partitionBarLength,
      stirrupLength,
      partitionStirrupLength,
      excavation,
      cushion,
      formwork,
      xps,
      blinding,
      waterproofing;
  final int stirrups, partitionStirrups;
}

/// Weight of reinforcing bar per metre, kg: 0.00617 × d².
double barKgPerM(int diameter) => 0.00617 * diameter * diameter;

FoundationTakeoff foundationTakeoff(HouseDocument doc, DerivedHouse derived) {
  final spec = doc.extras.foundation;
  final w = doc.footprint.width.toDouble(), d = doc.footprint.depth.toDouble();
  final strips = <FoundationStrip>[];
  for (final wall in wallsOf(derived.floors.first.base, spec)) {
    if (wall.role == WallRole.temporary) continue;
    final main = wall.carriesLoad;
    final b = (main ? spec.width : spec.partitionWidth).toDouble();
    final r = wall.rect;
    final grow = math.max(0.0, (b - wall.thickness) / 2);
    PlanRect strip(double half) {
      if (wall.horizontal) {
        final c = (r.bottom + r.top) / 2;
        final x0 = r.left <= 0 ? r.left - grow : r.left,
            x1 = r.right >= w ? r.right + grow : r.right;
        return PlanRect(x0, c - half, x1, c + half);
      }
      final c = (r.left + r.right) / 2;
      final y0 = r.bottom <= 0 ? r.bottom - grow : r.bottom,
          y1 = r.top >= d ? r.top + grow : r.top;
      return PlanRect(c - half, y0, c + half, y1);
    }

    strips.add(FoundationStrip(
        wall,
        strip(b / 2),
        strip(b / 2 + spec.cushionExtra),
        b.round(),
        main ? spec.height : spec.partitionHeight,
        main || spec.partitions));
  }
  final mainStrips = strips.where((s) => s.main).toList(),
      partStrips = strips.where((s) => !s.main && s.exists).toList();
  final lm = unionArea([for (final s in mainStrips) s.rect]) / spec.width,
      lp = partStrips.isEmpty
          ? 0.0
          : unionArea([for (final s in partStrips) s.rect]) /
              spec.partitionWidth;
  const lap = 1.08;
  final nSt = (lm / spec.stirrupStep).ceil(),
      nSp = (lp / spec.stirrupStep).ceil();
  final stL = 2 *
          ((spec.width - 2 * spec.cover + 20) +
              (spec.height - 2 * spec.cover + 20)) +
      200.0;
  final spL = 2 *
          ((spec.partitionWidth - 2 * spec.cover) +
              (spec.partitionHeight - 2 * spec.cover)) +
      150.0;
  final depth = spec.height - spec.plinth + spec.cushion;
  final perimeter = 2 * (w + d);
  return FoundationTakeoff(
      strips: List.unmodifiable(strips),
      mainLength: lm,
      partitionLength: lp,
      concrete: lm * spec.width * spec.height +
          lp * spec.partitionWidth * spec.partitionHeight,
      mainBarLength: lm * (spec.topBars + spec.bottomBars) * lap,
      partitionBarLength: lp * spec.partitionBars * lap,
      stirrups: nSt,
      stirrupLength: nSt * stL,
      partitionStirrups: nSp,
      partitionStirrupLength: nSp * spL,
      excavation: (lm + lp) * (spec.width + 600) * depth,
      cushion: lm * (spec.width + 2 * spec.cushionExtra) * spec.cushion +
          lp * (spec.partitionWidth + 2 * spec.cushionExtra) * spec.cushion,
      formwork: 2 * (lm * spec.height + lp * spec.partitionHeight),
      xps: perimeter * math.max(0, spec.height - 100),
      blinding: perimeter * 1000 + 4 * 1000 * 1000,
      waterproofing:
          (lm * spec.width + lp * spec.partitionWidth) * 2);
}

class WallTakeoff {
  const WallTakeoff(
      {required this.exteriorLength,
      required this.bearingLength,
      required this.partitionLength,
      required this.exteriorOpenings,
      required this.bearingOpenings,
      required this.partitionOpenings,
      required this.exteriorVolume,
      required this.bearingVolume,
      required this.partitionVolume,
      required this.exteriorGross,
      required this.height});
  final double exteriorLength,
      bearingLength,
      partitionLength,
      exteriorOpenings,
      bearingOpenings,
      partitionOpenings,
      exteriorVolume,
      bearingVolume,
      partitionVolume,
      exteriorGross,
      height;
}

/// Masonry over all floors: centreline lengths, openings and volumes.
WallTakeoff wallTakeoff(HouseDocument doc, DerivedHouse derived) {
  final spec = doc.extras.foundation;
  var el = 0.0, bl = 0.0, pl = 0.0, eo = 0.0, bo = 0.0, po = 0.0;
  var ev = 0.0, bv = 0.0, pv = 0.0, height = 0.0;
  for (var f = 0; f < doc.floors.length; f++) {
    final h = doc.floors[f].height.toDouble();
    height += h;
    final g = derived.floors[f];
    for (final wall in wallsOf(g.base, spec)) {
      if (wall.role == WallRole.temporary) continue;
      final openings = g.openings
          .where((p) => p.status == 'ok' && p.host?.ref == wall.segment.ref)
          .fold(0.0,
              (s, p) => s + p.opening.width * p.opening.height.toDouble());
      // Centreline length: the rect runs to the outer faces of cross walls.
      final along = wall.segment.end.pos - wall.segment.start.pos.toDouble();
      final volume = (along * h - openings) * wall.thickness;
      switch (wall.role) {
        case WallRole.exterior:
          el += along;
          eo += openings;
          ev += volume;
        case WallRole.bearing:
          bl += along;
          bo += openings;
          bv += volume;
        default:
          pl += along;
          po += openings;
          pv += volume;
      }
    }
  }
  final w = doc.footprint.width.toDouble(), d = doc.footprint.depth.toDouble();
  return WallTakeoff(
      exteriorLength: el / math.max(1, doc.floors.length),
      bearingLength: bl,
      partitionLength: pl,
      exteriorOpenings: eo,
      bearingOpenings: bo,
      partitionOpenings: po,
      exteriorVolume: ev,
      bearingVolume: bv,
      partitionVolume: pv,
      exteriorGross: 2 * (w + d) * height,
      height: height);
}
