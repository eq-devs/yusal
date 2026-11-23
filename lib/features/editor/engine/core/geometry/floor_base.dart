import 'package:meta/meta.dart';
import 'dart:math' as math;
import 'package:yusal/features/editor/engine/core/perf/engine_perf.dart';
import 'package:yusal/features/editor/engine/core/axis/axis_resolver.dart';
import 'package:yusal/features/editor/engine/core/canonicalization/room_canonicalizer.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';

class PlanRect {
  const PlanRect(this.left, this.bottom, this.right, this.top);
  final double left;
  final double bottom;
  final double right;
  final double top;
  double get area => math.max(0, right - left) * math.max(0, top - bottom);
  bool contains(double x, double y) =>
      x >= left && x <= right && y >= bottom && y <= top;
}

@immutable
class WallRef {
  const WallRef(this.floorId, this.carrierId, this.startAxisId, this.endAxisId);
  final String floorId;
  final String carrierId;
  final String startAxisId;
  final String endAxisId;
  BoundaryAnchor get anchor => BoundaryAnchor(
      axisId: carrierId, startAxisId: startAxisId, endAxisId: endAxisId);
  @override
  bool operator ==(Object other) =>
      other is WallRef &&
      floorId == other.floorId &&
      carrierId == other.carrierId &&
      startAxisId == other.startAxisId &&
      endAxisId == other.endAxisId;
  @override
  int get hashCode => Object.hash(floorId, carrierId, startAxisId, endAxisId);
}

class UnitEdge {
  UnitEdge(this.axis, this.start, this.end, this.negative, this.positive,
      this.kind, this.thickness);
  final ResolvedAxis axis;
  final ResolvedAxis start;
  final ResolvedAxis end;
  final Cell? negative;
  final Cell? positive;
  final String kind;
  final double thickness;
  bool get hasWall =>
      kind == 'exterior' || kind == 'interior' || kind == 'temporary';
}

class WallSegment {
  WallSegment(this.ref, this.axis, this.start, this.end, this.kind,
      this.thickness, this.edges);
  final WallRef ref;
  final ResolvedAxis axis;
  final ResolvedAxis start;
  final ResolvedAxis end;
  final String kind;
  final double thickness;
  final List<UnitEdge> edges;
}

class SpaceGeometry {
  const SpaceGeometry(
      this.id,
      this.cells,
      this.nominalArea,
      this.clearArea,
      this.clearRects,
      this.minClearSpan,
      this.collapsedCells,
      this.labelAnchor);
  final String id;
  final Set<Cell> cells;
  final double nominalArea;
  final double clearArea;
  final double minClearSpan;
  final List<PlanRect> clearRects;
  final List<Cell> collapsedCells;
  final ({double x, double y}) labelAnchor;
  bool get hasCollapsedCell => collapsedCells.isNotEmpty;
}

class FloorBase {
  const FloorBase(
      this.axes,
      this.owners,
      this.edges,
      this.wallSegments,
      this.wallRects,
      this.roomGeometry,
      this.stairGeometryBase,
      this.unassignedCells,
      this.unassignedNominalArea,
      [this.outside = const {}]);
  final ResolvedAxes axes;
  final Map<Cell, String?> owners;
  final List<UnitEdge> edges;
  final List<WallSegment> wallSegments;
  final List<PlanRect> wallRects;
  final List<SpaceGeometry> roomGeometry;
  final List<SpaceGeometry> stairGeometryBase;
  final List<Cell> unassignedCells;
  final double unassignedNominalArea;

  /// Cells cut out of the footprint on this floor: outside the building.
  final Set<Cell> outside;

  /// Whether the plan point is inside the footprint and not cut out.
  bool inside(double x, double y) {
    final i = axes.v.indexWhere((a) => a.pos > x) - 1;
    final j = axes.h.indexWhere((a) => a.pos > y) - 1;
    return i >= 0 && j >= 0 && !outside.contains(Cell(i, j));
  }
}

/// The last few results of [deriveFloorBase] and `deriveHouse`, by document
/// identity. Documents and derived geometry are immutable, so the same
/// document always gives the same result; widgets that derive in `build`
/// then pay for it once, not on every rebuild. Small and bounded, so the
/// undo history does not keep a derived copy of every past state alive.
class DerivedCache<K extends Object, V> {
  DerivedCache([this.capacity = 6]);
  final int capacity;
  final _entries = <(HouseDocument, K, V)>[];

  V get(HouseDocument doc, K key, V Function() compute) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final e = _entries[i];
      if (identical(e.$1, doc) && e.$2 == key) {
        if (i != _entries.length - 1) {
          _entries
            ..removeAt(i)
            ..add(e);
        }
        return e.$3;
      }
    }
    final value = compute();
    if (_entries.length >= capacity) _entries.removeAt(0);
    _entries.add((doc, key, value));
    return value;
  }

  void clear() => _entries.clear();
}

final _floorBases = DerivedCache<String, FloorBase>(8);

FloorBase deriveFloorBase(HouseDocument doc, String floorId) =>
    _floorBases.get(doc, floorId, () {
      final floor = doc.floors.firstWhere((f) => f.id == floorId);
      final kept = _floorShapes.find(doc, floor);
      if (kept != null) return kept;
      final base =
          timed('derive.floorBase', () => _deriveFloorBase(doc, floorId));
      _floorShapes.keep(doc, floor, base);
      return base;
    });

final _floorShapes = _FloorShapeCache(16);

/// Forgets every floor geometry kept, so the next one is derived afresh;
/// for measuring what derivation costs.
void clearFloorBases() {
  _floorBases.clear();
  _floorShapes._entries.clear();
}

/// The plan geometry of floors lately derived, found again by what the
/// geometry is made from rather than by the document it came from.
///
/// A floor's geometry reads only its rooms' and stairs' places, its wall
/// pieces and cut-outs, the axes, the footprint's size and the two default
/// wall thicknesses. An edit that leaves those alone on a floor (a rename,
/// a door moved, anything on another floor) makes a new document whose
/// floor has the same geometry, and this finds it instead of deriving it
/// again.
class _FloorShapeCache {
  _FloorShapeCache(this.capacity);
  final int capacity;
  final _entries = <(_FloorShape, FloorBase)>[];

  FloorBase? find(HouseDocument doc, Floor floor) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final e = _entries[i];
      if (!e.$1.matches(doc, floor)) continue;
      if (i != _entries.length - 1) {
        _entries
          ..removeAt(i)
          ..add(e);
      }
      return e.$2;
    }
    return null;
  }

  void keep(HouseDocument doc, Floor floor, FloorBase base) {
    if (_entries.length >= capacity) _entries.removeAt(0);
    _entries.add((_FloorShape(doc, floor), base));
  }
}

/// Everything [_deriveFloorBase] reads of a document for one floor.
class _FloorShape {
  _FloorShape(HouseDocument doc, this.floor)
      : axes = doc.axes,
        width = doc.footprint.width,
        depth = doc.footprint.depth,
        outerWall = doc.defaults.outerWallThickness,
        innerWall = doc.defaults.innerWallThickness;
  final Floor floor;
  final AxisSystem axes;
  final int width;
  final int depth;
  final int outerWall;
  final int innerWall;

  bool matches(HouseDocument doc, Floor other) {
    if (width != doc.footprint.width ||
        depth != doc.footprint.depth ||
        outerWall != doc.defaults.outerWallThickness ||
        innerWall != doc.defaults.innerWallThickness ||
        floor.id != other.id ||
        floor.explicitWalls != other.explicitWalls) {
      return false;
    }
    if (!identical(axes, doc.axes) && axes != doc.axes) return false;
    if (identical(floor, other)) return true;
    return _same<Room>(floor.rooms, other.rooms,
            (a, b) => a.id == b.id && _same(a.regions, b.regions)) &&
        _same<Stair>(floor.stairs, other.stairs,
            (a, b) => a.id == b.id && a.region == b.region) &&
        _same(floor.wallOverrides, other.wallOverrides) &&
        _same(floor.outside, other.outside);
  }

  static bool _same<T>(List<T> a, List<T> b, [bool Function(T, T)? equal]) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      if (equal == null ? x != y : !equal(x, y)) return false;
    }
    return true;
  }
}

FloorBase _deriveFloorBase(HouseDocument doc, String floorId) {
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  final axes = resolveFloorAxes(doc, floorId)!;
  final owners = <Cell, String?>{
    for (var j = 0; j < axes.ny; j++)
      for (var i = 0; i < axes.nx; i++) Cell(i, j): null
  };
  final outside = <Cell>{
    for (final r in floor.outside) ...cellsOfRect(resolveRect(axes, r).rect!)
  };
  final spaces = <String, Set<Cell>>{};
  for (final room in floor.rooms) {
    final cells = regionCells(axes, room.regions).cells;
    spaces[room.id] = cells;
    for (final c in cells) {
      owners[c] = room.id;
    }
  }
  for (final stair in floor.stairs) {
    final cells = cellsOfRect(resolveRect(axes, stair.region).rect!).toSet();
    spaces[stair.id] = cells;
    for (final c in cells) {
      owners[c] = stair.id;
    }
  }
  final edges = <UnitEdge>[];
  // Where each wall piece runs, worked out once: every unit edge below asks.
  final overrides = [
    for (final override in floor.wallOverrides)
      (override, resolveAnchor(axes, override.anchor).chain!)
  ];
  void edge(
      ResolvedAxis a, ResolvedAxis s, ResolvedAxis e, Cell? neg, Cell? pos) {
    final n = owners[neg];
    final p = owners[pos];
    final outN = neg == null || outside.contains(neg);
    final outP = pos == null || outside.contains(pos);
    // Between two cut-out cells (or a cut-out and the edge) nothing is built.
    if (outN && outP) {
      edges.add(UnitEdge(a, s, e, neg, pos, 'none', 0));
      return;
    }
    final kind = outN || outP
        ? 'exterior'
        : floor.explicitWalls || n == p
            ? 'none'
            : n == null || p == null
                ? 'temporary'
                : 'interior';
    var wall = UnitEdge(
        a,
        s,
        e,
        neg,
        pos,
        kind,
        (kind == 'exterior'
                ? doc.defaults.outerWallThickness
                : kind == 'none'
                    ? 0
                    : doc.defaults.innerWallThickness)
            .toDouble());
    for (final (override, chain) in overrides) {
      if (chain.carrier.id == a.id &&
          s.pos >= chain.startPos &&
          e.pos <= chain.endPos) {
        if (override is SolidWall) {
          // A drawn wall on the outline stays an outside wall.
          if (wall.kind != 'exterior') {
            wall = UnitEdge(
                a, s, e, neg, pos, 'interior', override.value.toDouble());
          }
        } else if (override is OpenWall) {
          wall = UnitEdge(a, s, e, neg, pos, 'open', 0);
        } else if (override is ThicknessWall && wall.hasWall) {
          wall =
              UnitEdge(a, s, e, neg, pos, wall.kind, override.value.toDouble());
        }
      }
    }
    edges.add(wall);
  }

  for (var j = 0; j <= axes.ny; j++) {
    for (var i = 0; i < axes.nx; i++) {
      edge(axes.h[j], axes.v[i], axes.v[i + 1], j == 0 ? null : Cell(i, j - 1),
          j == axes.ny ? null : Cell(i, j));
    }
  }
  for (var i = 0; i <= axes.nx; i++) {
    for (var j = 0; j < axes.ny; j++) {
      edge(axes.v[i], axes.h[j], axes.h[j + 1], i == 0 ? null : Cell(i - 1, j),
          i == axes.nx ? null : Cell(i, j));
    }
  }

  /// Which side of an outside wall is outdoors: the negative one or not.
  bool outdoorsBelow(UnitEdge e) =>
      e.negative == null || outside.contains(e.negative);
  bool junction(UnitEdge a, int position) => edges.any((b) =>
      b.hasWall &&
      b.axis.dir != a.axis.dir &&
      b.axis.pos == position &&
      b.start.pos <= a.axis.pos &&
      b.end.pos >= a.axis.pos);
  final segments = <WallSegment>[];
  var pending = <UnitEdge>[];
  void flush() {
    if (pending.isEmpty) return;
    final first = pending.first;
    final last = pending.last;
    segments.add(WallSegment(
        WallRef(floorId, first.axis.id, first.start.id, last.end.id),
        first.axis,
        first.start,
        last.end,
        first.kind,
        first.thickness,
        List.unmodifiable(pending)));
    pending = [];
  }

  for (final e in edges) {
    if (!e.hasWall) {
      flush();
      continue;
    }
    if (pending.isNotEmpty) {
      final prev = pending.last;
      if (prev.axis.id != e.axis.id ||
          prev.end.pos != e.start.pos ||
          prev.kind != e.kind ||
          prev.thickness != e.thickness ||
          (e.kind == 'exterior' && outdoorsBelow(prev) != outdoorsBelow(e)) ||
          junction(e, e.start.pos)) {
        flush();
      }
    }
    pending.add(e);
  }
  flush();
  ({double low, double high}) cross(WallSegment s) {
    final p = s.axis.pos.toDouble();
    final t = s.thickness;
    return switch (s.axis.id) {
      '@left' || '@bottom' => (low: 0, high: t),
      '@right' => (
          low: doc.footprint.width - t,
          high: doc.footprint.width.toDouble()
        ),
      '@top' => (
          low: doc.footprint.depth - t,
          high: doc.footprint.depth.toDouble()
        ),
      // Outside walls along a cut-out stand on the building's side.
      _ when s.kind == 'exterior' => outdoorsBelow(s.edges.first)
          ? (low: p, high: p + t)
          : (low: p - t, high: p),
      _ => (low: p - t / 2, high: p + t / 2)
    };
  }

  final rects = <PlanRect>[];
  for (final s in segments) {
    final c = cross(s);
    var start = s.start.pos.toDouble();
    var end = s.end.pos.toDouble();
    for (final p in segments) {
      if (p.axis.dir == s.axis.dir ||
          p.start.pos > s.axis.pos ||
          p.end.pos < s.axis.pos) {
        continue;
      }
      final pc = cross(p);
      if (p.axis.pos == s.start.pos) start = math.min(start, pc.low);
      if (p.axis.pos == s.end.pos) end = math.max(end, pc.high);
    }
    start = math.max(0, start);
    end = math.min(
        s.axis.dir == AxisDir.H
            ? doc.footprint.width.toDouble()
            : doc.footprint.depth.toDouble(),
        end);
    rects.add(s.axis.dir == AxisDir.H
        ? PlanRect(start, c.low, end, c.high)
        : PlanRect(c.low, start, c.high, end));
  }
  SpaceGeometry space(String id) {
    final cells = spaces[id]!;
    PlanRect cellRect(Cell c) => PlanRect(
        axes.v[c.i].pos.toDouble(),
        axes.h[c.j].pos.toDouble(),
        axes.v[c.i + 1].pos.toDouble(),
        axes.h[c.j + 1].pos.toDouble());
    final nominal = cells.map(cellRect).toList();
    final xs = {
      <double>{
        for (final r in nominal) ...[r.left, r.right],
        for (final r in rects) ...[r.left, r.right]
      }
    }.first.toList()
      ..sort();
    final ys = {
      <double>{
        for (final r in nominal) ...[r.bottom, r.top],
        for (final r in rects) ...[r.bottom, r.top]
      }
    }.first.toList()
      ..sort();
    final clear = <Cell>{};
    for (var j = 0; j < ys.length - 1; j++) {
      for (var i = 0; i < xs.length - 1; i++) {
        final x = (xs[i] + xs[i + 1]) / 2;
        final y = (ys[j] + ys[j + 1]) / 2;
        if (nominal.any((r) => r.contains(x, y)) &&
            !rects.any((r) => r.contains(x, y))) {
          clear.add(Cell(i, j));
        }
      }
    }
    // Merge row intervals and identical intervals on consecutive rows.
    final open = <(int, int), ({int j0, int j1})>{};
    final merged = <PlanRect>[];
    void close((int, int) k) {
      final r = open.remove(k)!;
      merged.add(PlanRect(xs[k.$1], ys[r.j0], xs[k.$2], ys[r.j1]));
    }

    for (var j = 0; j < ys.length - 1; j++) {
      final ranges = <(int, int)>{};
      var i = 0;
      while (i < xs.length - 1) {
        if (!clear.contains(Cell(i, j))) {
          i++;
          continue;
        }
        final start = i;
        while (i < xs.length - 1 && clear.contains(Cell(i, j))) {
          i++;
        }
        ranges.add((start, i));
      }
      for (final key in open.keys.toList()) {
        if (!ranges.contains(key)) close(key);
      }
      for (final key in ranges) {
        open[key] = (j0: open[key]?.j0 ?? j, j1: j + 1);
      }
    }
    for (final key in open.keys.toList()) {
      close(key);
    }
    merged.sort((a, b) {
      for (final c in [
        a.bottom.compareTo(b.bottom),
        a.left.compareTo(b.left),
        a.top.compareTo(b.top),
        a.right.compareTo(b.right)
      ]) {
        if (c != 0) return c;
      }
      return 0;
    });
    var span = double.infinity;
    for (final c in clear) {
      var left = c.i;
      var right = c.i + 1;
      var bottom = c.j;
      var top = c.j + 1;
      while (clear.contains(Cell(left - 1, c.j))) {
        left--;
      }
      while (clear.contains(Cell(right, c.j))) {
        right++;
      }
      while (clear.contains(Cell(c.i, bottom - 1))) {
        bottom--;
      }
      while (clear.contains(Cell(c.i, top))) {
        top++;
      }
      span =
          math.min(span, math.min(xs[right] - xs[left], ys[top] - ys[bottom]));
    }
    final collapsed = cells.where((c) {
      final r = cellRect(c);
      return !clear.any((s) =>
          r.contains((xs[s.i] + xs[s.i + 1]) / 2, (ys[s.j] + ys[s.j + 1]) / 2));
    }).toList()
      ..sort((a, b) => a.j != b.j ? a.j.compareTo(b.j) : a.i.compareTo(b.i));
    final largest = merged.isEmpty
        ? nominal.first
        : merged.reduce((a, b) => b.area > a.area ? b : a);
    return SpaceGeometry(
        id,
        Set.unmodifiable(cells),
        nominal.fold<double>(0, (a, r) => a + r.area),
        merged.fold<double>(0, (a, r) => a + r.area),
        List.unmodifiable(merged),
        span.isFinite ? span : 0,
        List.unmodifiable(collapsed), (
      x: (largest.left + largest.right) / 2,
      y: (largest.bottom + largest.top) / 2
    ));
  }

  final unassigned = owners.keys
      .where((c) => owners[c] == null && !outside.contains(c))
      .toList();
  return FloorBase(
      axes,
      Map.unmodifiable(owners),
      List.unmodifiable(edges),
      List.unmodifiable(segments),
      List.unmodifiable(rects),
      List.unmodifiable(floor.rooms.map((r) => space(r.id))),
      List.unmodifiable(floor.stairs.map((s) => space(s.id))),
      List.unmodifiable(unassigned),
      unassigned.fold<double>(
          0,
          (sum, c) =>
              sum +
              (axes.v[c.i + 1].pos - axes.v[c.i].pos) *
                  (axes.h[c.j + 1].pos - axes.h[c.j].pos)),
      Set.unmodifiable(outside));
}

/// Plan area of the building on [base]'s floor, mm², cut-outs left out.
double footprintArea(FloorBase base) {
  var area = 0.0;
  for (final c in base.owners.keys) {
    if (!base.outside.contains(c)) {
      area += (base.axes.v[c.i + 1].pos - base.axes.v[c.i].pos) *
          (base.axes.h[c.j + 1].pos - base.axes.h[c.j].pos).toDouble();
    }
  }
  return area;
}

/// Length of the building's outline on [base]'s floor, mm.
double outlineLength(FloorBase base) => base.edges
    .where((e) =>
        e.kind == 'exterior' || (e.kind == 'open' && _onOutline(base, e)))
    .fold(0.0, (s, e) => s + e.end.pos - e.start.pos);

bool _onOutline(FloorBase base, UnitEdge e) =>
    e.negative == null ||
    e.positive == null ||
    base.outside.contains(e.negative) ||
    base.outside.contains(e.positive);

/// The building's cells on [base]'s floor merged into rectangles: runs
/// along each row, joined with identical runs on the rows above.
List<PlanRect> insideRects(FloorBase base) {
  final axes = base.axes;
  final open = <(int, int), int>{};
  final out = <PlanRect>[];
  void close((int, int) run, int j0, int j1) => out.add(PlanRect(
      axes.v[run.$1].pos.toDouble(),
      axes.h[j0].pos.toDouble(),
      axes.v[run.$2].pos.toDouble(),
      axes.h[j1].pos.toDouble()));
  for (var j = 0; j <= axes.ny; j++) {
    final runs = <(int, int)>{};
    if (j < axes.ny) {
      var i = 0;
      while (i < axes.nx) {
        if (base.outside.contains(Cell(i, j))) {
          i++;
          continue;
        }
        final start = i;
        while (i < axes.nx && !base.outside.contains(Cell(i, j))) {
          i++;
        }
        runs.add((start, i));
      }
    }
    for (final run in open.keys.toList()) {
      if (!runs.contains(run)) close(run, open.remove(run)!, j);
    }
    for (final run in runs) {
      open.putIfAbsent(run, () => j);
    }
  }
  return out;
}
