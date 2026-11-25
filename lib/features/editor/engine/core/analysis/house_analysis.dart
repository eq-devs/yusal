import 'dart:math' as math;
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';

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
  final xs = {
    for (final r in rects) ...[r.left, r.right]
  }.toList()
    ..sort();
  final ys = {
    for (final r in rects) ...[r.bottom, r.top]
  }.toList()
    ..sort();
  var area = 0.0;
  for (var i = 0; i < xs.length - 1; i++) {
    for (var j = 0; j < ys.length - 1; j++) {
      final x = (xs[i] + xs[i + 1]) / 2;
      final y = (ys[j] + ys[j + 1]) / 2;
      if (rects.any((r) => r.contains(x, y))) {
        area += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
      }
    }
  }
  return area;
}

/// Room ids on the two sides of an opening (null outside the house).
(String?, String?) roomsBeside(OpeningPlacement p, FloorBase base) {
  final mid = (p.start + p.end) / 2;
  for (final e in base.edgesOnAxis(p.axis.id)) {
    if (e.start.pos > mid || e.end.pos < mid) {
      continue;
    }
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
  final n = (math.sin(a), math.cos(a));
  final e = (math.cos(a), -math.sin(a));
  final dn = out.$1 * n.$1 + out.$2 * n.$2;
  final de = out.$1 * e.$1 + out.$2 * e.$2;
  if (dn.abs() >= de.abs()) return dn >= 0 ? Facing.north : Facing.south;
  return de >= 0 ? Facing.east : Facing.west;
}

class RoomStats {
  const RoomStats(this.room, this.geometry, this.clearWidth, this.clearDepth,
      this.windows, this.windowArea, this.volume);
  final Room room;
  final SpaceGeometry geometry;

  /// Net size of the largest clear rectangle.
  final double clearWidth;
  final double clearDepth;
  final List<OpeningPlacement> windows;
  final double windowArea;
  final double volume;
  double get area => geometry.clearArea;

  /// Floor area per unit of window area: 7 means 1 : 7.
  double? get floorPerWindow => windowArea <= 0 ? null : area / windowArea;
}

bool openingTouches(OpeningPlacement p, FloorBase base, String roomId) =>
    base.edgesOnAxis(p.axis.id).any((e) =>
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
  const FoundationStrip(
      this.wall, this.rect, this.cushion, this.width, this.height, this.exists);
  final WallInfo wall;
  final PlanRect rect;
  final PlanRect cushion;
  final int width;
  final int height;

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
    this.slabRects = const [],
    this.piles = const [],
    this.pileDia = 0,
    this.pileConcrete = 0,
    this.pileBarLength = 0,
  });
  final List<FoundationStrip> strips;

  /// A slab foundation's plan, empty for the other kinds.
  final List<PlanRect> slabRects;

  /// Centres of the piles of a pile foundation, with their concrete (mm³)
  /// and the length of their bars (mm).
  final List<({double x, double y})> piles;
  final int pileDia;
  final double pileConcrete;
  final double pileBarLength;

  /// Lengths in mm; areas in mm²; volumes in mm³.
  final double mainLength;
  final double partitionLength;
  final double concrete;
  final double mainBarLength;
  final double partitionBarLength;
  final double stirrupLength;
  final double partitionStirrupLength;
  final double excavation;
  final double cushion;
  final double formwork;
  final double xps;
  final double blinding;
  final double waterproofing;
  final int stirrups;
  final int partitionStirrups;
}

/// Weight of reinforcing bar per metre, kg: 0.00617 × d².
double barKgPerM(int diameter) => 0.00617 * diameter * diameter;

FoundationTakeoff foundationTakeoff(HouseDocument doc, DerivedHouse derived) {
  final spec = doc.extras.foundation;
  final w = doc.footprint.width.toDouble();
  final d = doc.footprint.depth.toDouble();
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
        final x0 = r.left <= 0 ? r.left - grow : r.left;
        final x1 = r.right >= w ? r.right + grow : r.right;
        return PlanRect(x0, c - half, x1, c + half);
      }
      final c = (r.left + r.right) / 2;
      final y0 = r.bottom <= 0 ? r.bottom - grow : r.bottom;
      final y1 = r.top >= d ? r.top + grow : r.top;
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
  final mainStrips = strips.where((s) => s.main).toList();
  final partStrips = strips.where((s) => !s.main && s.exists).toList();
  final lm = unionArea([for (final s in mainStrips) s.rect]) / spec.width;
  final lp = partStrips.isEmpty
      ? 0.0
      : unionArea([for (final s in partStrips) s.rect]) / spec.partitionWidth;
  const lap = 1.08;
  final perimeter = outlineLength(derived.floors.first.base);
  if (spec.type == FoundationType.slab) {
    // One slab under the whole house, 100 mm proud of the walls, with a
    // mesh of bars near each face.
    final rects = [
      for (final r in insideRects(derived.floors.first.base))
        PlanRect(r.left - 100, r.bottom - 100, r.right + 100, r.top + 100)
    ];
    final area = unionArea(rects);
    final edge = perimeter + 800;
    final t = spec.slabThickness.toDouble();
    return FoundationTakeoff(
        strips: const [],
        slabRects: List.unmodifiable(rects),
        mainLength: 0,
        partitionLength: 0,
        concrete: area * t,
        mainBarLength: area * 4 / math.max(50, spec.slabBarStep) * lap,
        partitionBarLength: 0,
        stirrups: 0,
        stirrupLength: 0,
        partitionStirrups: 0,
        partitionStirrupLength: 0,
        excavation: area * math.max(0, t - spec.plinth + spec.cushion),
        cushion: area * spec.cushion,
        formwork: edge * t,
        xps: area,
        blinding: perimeter * 1000 + 4 * 1000 * 1000,
        waterproofing: area);
  }
  final nSt = (lm / spec.stirrupStep).ceil();
  final nSp = (lp / spec.stirrupStep).ceil();
  final stL = 2 *
          ((spec.width - 2 * spec.cover + 20) +
              (spec.height - 2 * spec.cover + 20)) +
      200.0;
  final spL = 2 *
          ((spec.partitionWidth - 2 * spec.cover) +
              (spec.partitionHeight - 2 * spec.cover)) +
      150.0;
  final depth = spec.height - spec.plinth + spec.cushion;
  final concrete = lm * spec.width * spec.height +
      lp * spec.partitionWidth * spec.partitionHeight;
  if (spec.type == FoundationType.pile) {
    // Bored piles under the load-bearing strips, which become the ring of
    // beams: one at each end of a strip and then every [pileStep].
    final piles = <({double x, double y})>[];
    void pile(double x, double y) {
      if (!piles.any((p) => (p.x - x).abs() < 300 && (p.y - y).abs() < 300)) {
        piles.add((x: x, y: y));
      }
    }

    final step = math.max(500, spec.pileStep);
    for (final s in mainStrips) {
      final r = s.rect;
      final horizontal = s.wall.horizontal;
      final a0 = (horizontal ? r.left : r.bottom) + spec.width / 2;
      final a1 = (horizontal ? r.right : r.top) - spec.width / 2;
      final c = horizontal ? (r.bottom + r.top) / 2 : (r.left + r.right) / 2;
      final n = math.max(1, ((a1 - a0) / step).ceil());
      for (var i = 0; i <= n; i++) {
        final a = a0 + (a1 - a0) * i / n;
        horizontal ? pile(a, c) : pile(c, a);
      }
    }
    final radius = spec.pileDia / 2;
    final pileConcrete =
        piles.length * math.pi * radius * radius * spec.pileDepth;
    return FoundationTakeoff(
        strips: List.unmodifiable(strips),
        piles: List.unmodifiable(piles),
        pileDia: spec.pileDia,
        pileConcrete: pileConcrete,
        pileBarLength: piles.length * 4 * (spec.pileDepth + 400.0),
        mainLength: lm,
        partitionLength: lp,
        concrete: concrete + pileConcrete,
        mainBarLength: lm * (spec.topBars + spec.bottomBars) * lap +
            piles.length * 4 * (spec.pileDepth + 400.0),
        partitionBarLength: lp * spec.partitionBars * lap,
        stirrups: nSt,
        stirrupLength: nSt * stL,
        partitionStirrups: nSp,
        partitionStirrupLength: nSp * spL,
        // The beams sit in a shallow trench; the piles are drilled.
        excavation: pileConcrete +
            (lm + lp) *
                (spec.width + 600) *
                math.max(0, spec.height - spec.plinth),
        cushion: 0,
        formwork: 2 * (lm * spec.height + lp * spec.partitionHeight),
        xps: perimeter * math.max(0, spec.height - 100),
        blinding: perimeter * 1000 + 4 * 1000 * 1000,
        waterproofing: (lm * spec.width + lp * spec.partitionWidth) * 2);
  }
  return FoundationTakeoff(
      strips: List.unmodifiable(strips),
      mainLength: lm,
      partitionLength: lp,
      concrete: concrete,
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
      waterproofing: (lm * spec.width + lp * spec.partitionWidth) * 2);
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
  final double exteriorLength;
  final double bearingLength;
  final double partitionLength;
  final double exteriorOpenings;
  final double bearingOpenings;
  final double partitionOpenings;
  final double exteriorVolume;
  final double bearingVolume;
  final double partitionVolume;
  final double exteriorGross;
  final double height;
}

/// Masonry over all floors: centreline lengths, openings and volumes.
WallTakeoff wallTakeoff(HouseDocument doc, DerivedHouse derived) {
  final spec = doc.extras.foundation;
  var el = 0.0;
  var bl = 0.0;
  var pl = 0.0;
  var eo = 0.0;
  var bo = 0.0;
  var po = 0.0;
  var ev = 0.0;
  var bv = 0.0;
  var pv = 0.0;
  var height = 0.0;
  var gross = 0.0;
  for (var f = 0; f < doc.floors.length; f++) {
    final h = doc.floors[f].height.toDouble();
    height += h;
    final g = derived.floors[f];
    gross += outlineLength(g.base) * h;
    for (final wall in wallsOf(g.base, spec)) {
      if (wall.role == WallRole.temporary) continue;
      final openings = g.openings
          .where((p) => p.status == 'ok' && p.host?.ref == wall.segment.ref)
          .fold(
              0.0, (s, p) => s + p.opening.width * p.opening.height.toDouble());
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
      exteriorGross: gross,
      height: height);
}

/// Thickness of the load-bearing layers of the outside wall, mm: the block
/// and concrete layers of the build-up, or the wall as drawn without them.
double structuralThickness(HouseDocument doc) {
  final layers = doc.extras.wallLayers
      .where((l) =>
          l.material == LayerMaterial.block || l.material == LayerMaterial.conc)
      .fold(0, (s, l) => s + l.thickness);
  return (layers > 0 ? layers : doc.defaults.outerWallThickness).toDouble();
}

/// Height of the reinforced belt poured on top of each floor's walls and
/// of a lintel, and how far a lintel rests on the wall each side, mm.
const ringBeamHeight = 200;
const lintelHeight = 200;
const lintelBearing = 250;

/// Reinforced concrete inside the masonry, and the masonry of the gables.
class StructureTakeoff {
  const StructureTakeoff(
      {required this.beltExterior,
      required this.beltBearing,
      required this.beltExteriorVolume,
      required this.beltBearingVolume,
      required this.lintels,
      required this.lintelLength,
      required this.lintelVolume,
      required this.gableArea});

  /// Length of the belt over outside and over inner load-bearing walls on
  /// all floors, mm, and its concrete, mm³.
  final double beltExterior;
  final double beltBearing;
  final double beltExteriorVolume;
  final double beltBearingVolume;
  double get beltLength => beltExterior + beltBearing;
  double get beltVolume => beltExteriorVolume + beltBearingVolume;

  /// Lintels over the openings: their number, total length (mm) and
  /// concrete (mm³).
  final int lintels;
  final double lintelLength;
  final double lintelVolume;

  /// Wall above the eaves under a gable roof, mm²; zero for other roofs.
  final double gableArea;
}

StructureTakeoff structureTakeoff(HouseDocument doc, DerivedHouse derived) {
  final spec = doc.extras.foundation;
  final outer = structuralThickness(doc);
  var be = 0.0;
  var bb = 0.0;
  var bbv = 0.0;
  var n = 0;
  var ll = 0.0;
  var lv = 0.0;
  for (final g in derived.floors) {
    for (final wall in wallsOf(g.base, spec)) {
      final along = wall.segment.end.pos - wall.segment.start.pos.toDouble();
      if (wall.role == WallRole.exterior) {
        be += along;
      } else if (wall.role == WallRole.bearing) {
        bb += along;
        bbv += along * wall.thickness * ringBeamHeight;
      }
    }
    for (final p in g.openings) {
      final host = p.host;
      if (p.status != 'ok' || host == null || host.kind == 'temporary') {
        continue;
      }
      final length = p.opening.width + 2.0 * lintelBearing;
      n++;
      ll += length;
      lv += length *
          (host.kind == 'exterior' ? outer : host.thickness) *
          lintelHeight;
    }
  }
  var gable = 0.0;
  final roof = doc.roof;
  if (roof.type == RoofType.gable) {
    final span =
        (roof.ridgeDir == AxisDir.V ? doc.footprint.width : doc.footprint.depth)
            .toDouble();
    gable = span * span / 2 * math.tan(roof.pitchDeg! * math.pi / 180);
  }
  return StructureTakeoff(
      beltExterior: be,
      beltBearing: bb,
      beltExteriorVolume: be * outer * ringBeamHeight,
      beltBearingVolume: bbv,
      lintels: n,
      lintelLength: ll,
      lintelVolume: lv,
      gableArea: gable);
}

/// A pitched roof measured for its timber and trim; lengths in metres,
/// the area in m².
class RoofTakeoff {
  const RoofTakeoff(
      {required this.area,
      required this.eaves,
      required this.ridge,
      required this.hips,
      required this.verges,
      required this.slope});

  /// Slope area with the overhangs.
  final double area;

  /// Eaves, where the gutters hang; the ridge; the four hips of a hip
  /// roof; and the sloping edges at the gables.
  final double eaves;
  final double ridge;
  final double hips;
  final double verges;

  /// Length of one rafter from the ridge to the eaves.
  final double slope;

  /// Rafters every 600 mm and battens every 350 mm, total metres.
  double get rafterLength => area / 0.6;
  double get battenLength => area / 0.35;
}

/// Null for a flat roof.
RoofTakeoff? roofTakeoff(HouseDocument doc) {
  final roof = doc.roof;
  if (!roof.pitched) return null;
  final o = roof.overhang! / 1000;
  final w = doc.footprint.width / 1000 + 2 * o;
  final d = doc.footprint.depth / 1000 + 2 * o;
  final a = roof.pitchDeg! * math.pi / 180;
  final area = w * d / math.cos(a);
  if (roof.type == RoofType.gable) {
    final vertical = roof.ridgeDir == AxisDir.V;
    final span = vertical ? w : d;
    final run = vertical ? d : w;
    final slope = span / 2 / math.cos(a);
    return RoofTakeoff(
        area: area,
        eaves: 2 * run,
        ridge: run,
        hips: 0,
        verges: 4 * slope,
        slope: slope);
  }
  final short = math.min(w, d);
  final long = math.max(w, d);
  final rise = short / 2 * math.tan(a);
  return RoofTakeoff(
      area: area,
      eaves: 2 * (w + d),
      ridge: long - short,
      hips: 4 * math.sqrt(short * short / 2 + rise * rise),
      verges: 0,
      slope: short / 2 / math.cos(a));
}

/// Masonry to lay, m³: the outside walls with the gables, and the inner
/// walls; the reinforced belts take the place of masonry.
({double exterior, double interior}) masonryVolumes(
    HouseDocument doc, WallTakeoff wt, StructureTakeoff st) {
  final net = math.max(0.0, wt.exteriorGross - wt.exteriorOpenings);
  return (
    exterior: math.max(
        0.0,
        ((net + st.gableArea) * structuralThickness(doc) -
                st.beltExteriorVolume) /
            1e9),
    interior: math.max(0.0,
        (wt.bearingVolume + wt.partitionVolume - st.beltBearingVolume) / 1e9)
  );
}
