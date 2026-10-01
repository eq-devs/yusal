import 'dart:math' as math;
import '../axis/axis_resolver.dart';
import '../canonicalization/room_canonicalizer.dart';
import '../document/house_document.dart';

class PlanRect {
  const PlanRect(this.left, this.bottom, this.right, this.top);
  final double left, bottom, right, top;
  double get area => math.max(0, right - left) * math.max(0, top - bottom);
  bool contains(double x, double y) =>
      x >= left && x <= right && y >= bottom && y <= top;
}

class WallRef {
  const WallRef(this.floorId, this.carrierId, this.startAxisId, this.endAxisId);
  final String floorId, carrierId, startAxisId, endAxisId;
  BoundaryAnchor get anchor => BoundaryAnchor(
      axisId: carrierId, startAxisId: startAxisId, endAxisId: endAxisId);
  @override
  bool operator ==(Object o) =>
      o is WallRef &&
      floorId == o.floorId &&
      carrierId == o.carrierId &&
      startAxisId == o.startAxisId &&
      endAxisId == o.endAxisId;
  @override
  int get hashCode => Object.hash(floorId, carrierId, startAxisId, endAxisId);
}

class UnitEdge {
  UnitEdge(this.axis, this.start, this.end, this.negative, this.positive,
      this.kind, this.thickness);
  final ResolvedAxis axis, start, end;
  final Cell? negative, positive;
  final String kind;
  final double thickness;
  bool get hasWall =>
      kind == 'exterior' || kind == 'interior' || kind == 'temporary';
}

class WallSegment {
  WallSegment(this.ref, this.axis, this.start, this.end, this.kind,
      this.thickness, this.edges);
  final WallRef ref;
  final ResolvedAxis axis, start, end;
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
  final double nominalArea, clearArea, minClearSpan;
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
      this.unassignedNominalArea);
  final ResolvedAxes axes;
  final Map<Cell, String?> owners;
  final List<UnitEdge> edges;
  final List<WallSegment> wallSegments;
  final List<PlanRect> wallRects;
  final List<SpaceGeometry> roomGeometry, stairGeometryBase;
  final List<Cell> unassignedCells;
  final double unassignedNominalArea;
}

FloorBase deriveFloorBase(HouseDocument doc, String floorId) {
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  final axes = resolveFloorAxes(doc, floorId)!;
  final owners = <Cell, String?>{
    for (var j = 0; j < axes.ny; j++)
      for (var i = 0; i < axes.nx; i++) Cell(i, j): null
  };
  final spaces = <String, Set<Cell>>{};
  for (final room in floor.rooms) {
    final cells = regionCells(axes, room.regions).cells;
    spaces[room.id] = cells;
    for (final c in cells) owners[c] = room.id;
  }
  for (final stair in floor.stairs) {
    final cells = cellsOfRect(resolveRect(axes, stair.region).rect!).toSet();
    spaces[stair.id] = cells;
    for (final c in cells) owners[c] = stair.id;
  }
  final edges = <UnitEdge>[];
  void edge(
      ResolvedAxis a, ResolvedAxis s, ResolvedAxis e, Cell? neg, Cell? pos) {
    final n = owners[neg], p = owners[pos];
    final kind = neg == null || pos == null
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
    for (final override in floor.wallOverrides) {
      final chain = resolveAnchor(axes, override.anchor).chain!;
      if (chain.carrier.id == a.id &&
          s.pos >= chain.startPos &&
          e.pos <= chain.endPos) {
        if (override is SolidWall) {
          wall = UnitEdge(
              a, s, e, neg, pos, 'interior', override.value.toDouble());
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

  for (var j = 0; j <= axes.ny; j++)
    for (var i = 0; i < axes.nx; i++)
      edge(axes.h[j], axes.v[i], axes.v[i + 1], j == 0 ? null : Cell(i, j - 1),
          j == axes.ny ? null : Cell(i, j));
  for (var i = 0; i <= axes.nx; i++)
    for (var j = 0; j < axes.ny; j++)
      edge(axes.v[i], axes.h[j], axes.h[j + 1], i == 0 ? null : Cell(i - 1, j),
          i == axes.nx ? null : Cell(i, j));
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
    final first = pending.first, last = pending.last;
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
          junction(e, e.start.pos)) flush();
    }
    pending.add(e);
  }
  flush();
  ({double low, double high}) cross(WallSegment s) {
    final p = s.axis.pos.toDouble(), t = s.thickness;
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
      _ => (low: p - t / 2, high: p + t / 2)
    };
  }

  final rects = <PlanRect>[];
  for (final s in segments) {
    final c = cross(s);
    var start = s.start.pos.toDouble(), end = s.end.pos.toDouble();
    for (final p in segments) {
      if (p.axis.dir == s.axis.dir ||
          p.start.pos > s.axis.pos ||
          p.end.pos < s.axis.pos) continue;
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
    for (var j = 0; j < ys.length - 1; j++)
      for (var i = 0; i < xs.length - 1; i++) {
        final x = (xs[i] + xs[i + 1]) / 2, y = (ys[j] + ys[j + 1]) / 2;
        if (nominal.any((r) => r.contains(x, y)) &&
            !rects.any((r) => r.contains(x, y))) clear.add(Cell(i, j));
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
        while (i < xs.length - 1 && clear.contains(Cell(i, j))) i++;
        ranges.add((start, i));
      }
      for (final key in open.keys.toList())
        if (!ranges.contains(key)) close(key);
      for (final key in ranges) open[key] = (j0: open[key]?.j0 ?? j, j1: j + 1);
    }
    for (final key in open.keys.toList()) close(key);
    merged.sort((a, b) {
      for (final c in [
        a.bottom.compareTo(b.bottom),
        a.left.compareTo(b.left),
        a.top.compareTo(b.top),
        a.right.compareTo(b.right)
      ]) if (c != 0) return c;
      return 0;
    });
    var span = double.infinity;
    for (final c in clear) {
      var left = c.i, right = c.i + 1, bottom = c.j, top = c.j + 1;
      while (clear.contains(Cell(left - 1, c.j))) left--;
      while (clear.contains(Cell(right, c.j))) right++;
      while (clear.contains(Cell(c.i, bottom - 1))) bottom--;
      while (clear.contains(Cell(c.i, top))) top++;
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

  final unassigned = owners.keys.where((c) => owners[c] == null).toList();
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
                  (axes.h[c.j + 1].pos - axes.h[c.j].pos)));
}
