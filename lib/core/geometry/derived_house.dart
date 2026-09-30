import 'dart:math' as math;
import '../document/house_document.dart';
import '../axis/axis_resolver.dart';
import 'floor_base.dart';
import 'source_ref.dart';
export 'source_ref.dart';

typedef Point3 = ({double x, double y, double z});

class SceneElement {
  const SceneElement(this.kind, this.floorIndex, this.source, this.materialRole,
      this.vertices, this.faces);
  final String kind, materialRole;
  final int floorIndex;
  final SourceRef? source;
  final List<Point3> vertices;
  final List<List<int>> faces;
}

class OpeningPlacement {
  const OpeningPlacement(
      this.opening, this.status, this.axis, this.start, this.end, this.host);
  final Opening opening;
  final String status;
  final ResolvedAxis axis;
  final double start, end;
  final WallSegment? host;
}

class StairGeometry {
  const StairGeometry(this.stairId, this.fits, this.opening, this.steps,
      this.landings, this.requiredA, this.requiredB);
  final String stairId;
  final bool fits;
  final PlanRect opening;
  final List<({PlanRect rect, double height})> steps, landings;
  final double requiredA, requiredB;
}

class DerivedFloor {
  const DerivedFloor(this.base, this.openings, this.stairs, this.elevation);
  final FloorBase base;
  final List<OpeningPlacement> openings;
  final List<StairGeometry> stairs;
  final double elevation;
}

class DerivedHouse {
  const DerivedHouse(
      this.floors, this.scene3d, this.width, this.depth, this.height);
  final List<DerivedFloor> floors;
  final List<SceneElement> scene3d;
  final double width, depth, height;
}

List<OpeningPlacement> deriveOpenings(
    HouseDocument doc, FloorBase base, String floorId) {
  final floor = doc.floors.firstWhere((f) => f.id == floorId);
  return List.unmodifiable(floor.openings.map((o) {
    final chain = resolveAnchor(base.axes, o.anchor).chain!;
    final length = chain.nominalLength.toDouble(), w = o.width.toDouble();
    final start = chain.startPos +
        switch (o.position) {
          CenterPosition() => length / 2 - w / 2,
          FromStartPosition(:final d) => d.toDouble(),
          FromEndPosition(:final d) => length - d - w
        };
    final end = start + w;
    final walls = base.wallSegments
        .where((s) =>
            s.axis.id == chain.carrier.id &&
            s.start.pos < end &&
            start < s.end.pos)
        .toList();
    final edges = base.edges
        .where((e) =>
            e.axis.id == chain.carrier.id &&
            e.start.pos < end &&
            start < e.end.pos)
        .toList();
    final status = start < chain.startPos ||
            end > chain.endPos ||
            walls.length > 1
        ? 'tooLong'
        : edges.any((e) => e.kind == 'open')
            ? 'onOpen'
            : edges.any((e) => e.kind == 'none') || walls.isEmpty
                ? 'noWall'
                : o.sill + o.height > floor.height - doc.defaults.slabThickness
                    ? 'exceedsHeight'
                    : 'ok';
    return OpeningPlacement(o, status, chain.carrier, start, end,
        status == 'ok' ? walls.single : null);
  }));
}

DerivedHouse deriveHouse(HouseDocument doc) {
  final elements = <SceneElement>[], floors = <DerivedFloor>[];
  final width = doc.footprint.width.toDouble(),
      depth = doc.footprint.depth.toDouble(),
      slab = doc.defaults.slabThickness.toDouble();
  void mesh(String kind, int index, SourceRef? source, String material,
      List<Point3> points, List<List<int>> faces) {
    elements.add(SceneElement(
        kind,
        index,
        source,
        material,
        List.unmodifiable(points),
        List.unmodifiable(faces.map((f) => List<int>.unmodifiable(f)))));
  }

  void box(String kind, int index, SourceRef? source, String material,
      PlanRect r, double z0, double z1) {
    if (r.area <= 0 || z1 <= z0) return;
    mesh(kind, index, source, material, [
      (x: r.left, y: r.bottom, z: z0),
      (x: r.right, y: r.bottom, z: z0),
      (x: r.right, y: r.top, z: z0),
      (x: r.left, y: r.top, z: z0),
      (x: r.left, y: r.bottom, z: z1),
      (x: r.right, y: r.bottom, z: z1),
      (x: r.right, y: r.top, z: z1),
      (x: r.left, y: r.top, z: z1)
    ], const [
      [0, 3, 2, 1],
      [4, 5, 6, 7],
      [0, 1, 5, 4],
      [1, 2, 6, 5],
      [2, 3, 7, 6],
      [3, 0, 4, 7]
    ]);
  }

  box('Slab', 0, null, 'slab', PlanRect(0, 0, width, depth), -slab, 0);
  var elevation = 0.0;
  for (var f = 0; f < doc.floors.length; f++) {
    final floor = doc.floors[f],
        height = floor.height.toDouble(),
        base = deriveFloorBase(doc, floor.id);
    final openings = deriveOpenings(doc, base, floor.id);
    for (var k = 0; k < base.wallSegments.length; k++) {
      final wall = base.wallSegments[k],
          r = base.wallRects[k],
          horizontal = wall.axis.dir == AxisDir.H;
      final holes = openings
          .where((p) => p.host?.ref == wall.ref && p.status == 'ok')
          .toList();
      final us = {
        <double>{
          horizontal ? r.left : r.bottom,
          horizontal ? r.right : r.top,
          for (final h in holes) ...[h.start, h.end]
        }
      }.first.toList()
        ..sort();
      final zs = {
        <double>{
          0,
          height,
          for (final h in holes) ...[
            h.opening.sill.toDouble(),
            (h.opening.sill + h.opening.height).toDouble()
          ]
        }
      }.first.toList()
        ..sort();
      for (var j = 0; j < zs.length - 1; j++)
        for (var i = 0; i < us.length - 1; i++) {
          final u = (us[i] + us[i + 1]) / 2, z = (zs[j] + zs[j + 1]) / 2;
          if (holes.any((h) =>
              u > h.start &&
              u < h.end &&
              z > h.opening.sill &&
              z < h.opening.sill + h.opening.height)) continue;
          box(
              'WallPiece',
              f,
              WallSource(wall.ref),
              wall.kind == 'temporary' ? 'wallTemporary' : 'wall',
              horizontal
                  ? PlanRect(us[i], r.bottom, us[i + 1], r.top)
                  : PlanRect(r.left, us[i], r.right, us[i + 1]),
              elevation + zs[j],
              elevation + zs[j + 1]);
        }
    }
    for (final p in openings.where((p) => p.status == 'ok')) {
      final o = p.opening,
          horizontal = p.axis.dir == AxisDir.H,
          pos = p.axis.pos.toDouble();
      var center = pos;
      if (p.axis.id == '@left' || p.axis.id == '@bottom')
        center = p.host!.thickness / 2;
      if (p.axis.id == '@right') center = width - p.host!.thickness / 2;
      if (p.axis.id == '@top') center = depth - p.host!.thickness / 2;
      final thickness = o is DoorOpening ? 40.0 : 4.0;
      final r = horizontal
          ? PlanRect(
              p.start, center - thickness / 2, p.end, center + thickness / 2)
          : PlanRect(
              center - thickness / 2, p.start, center + thickness / 2, p.end);
      if (o is! DoorOpening) {
        final z0 = elevation + o.sill, z1 = z0 + o.height;
        Point3 point(double u, double z) =>
            horizontal ? (x: u, y: center, z: z) : (x: center, y: u, z: z);
        mesh('Glass', f, OpeningSource(o.id), 'glass', [
          point(p.start, z0),
          point(p.end, z0),
          point(p.end, z1),
          point(p.start, z1)
        ], const [
          [0, 1, 2, 3]
        ]);
        continue;
      }
      box('DoorLeaf', f, OpeningSource(o.id), 'door', r, elevation + o.sill,
          elevation + o.sill + o.height);
    }
    final stairs = <StairGeometry>[];
    for (final stair in floor.stairs) {
      final resolved = resolveRect(base.axes, stair.region).rect!;
      var left = resolved.left.toDouble(),
          right = resolved.right.toDouble(),
          bottom = resolved.bottom.toDouble(),
          top = resolved.top.toDouble();
      double invasion(AxisDir dir, int pos, int start, int end) {
        var value = 0.0;
        for (final edge in base.edges) {
          if (edge.axis.dir == dir &&
              edge.axis.pos == pos &&
              edge.start.pos < end &&
              start < edge.end.pos &&
              edge.hasWall)
            value = math.max(value,
                edge.kind == 'exterior' ? edge.thickness : edge.thickness / 2);
        }
        return value;
      }

      left += invasion(AxisDir.V, resolved.left, resolved.bottom, resolved.top);
      right -=
          invasion(AxisDir.V, resolved.right, resolved.bottom, resolved.top);
      bottom +=
          invasion(AxisDir.H, resolved.bottom, resolved.left, resolved.right);
      top -= invasion(AxisDir.H, resolved.top, resolved.left, resolved.right);
      right = math.max(left, right);
      top = math.max(bottom, top);
      final r = PlanRect(left, bottom, right, top);
      final alongY = stair.startEdge == StairEdge.bottom ||
          stair.startEdge == StairEdge.top;
      final a = alongY ? r.top - r.bottom : r.right - r.left,
          b = alongY ? r.right - r.left : r.top - r.bottom;
      final n = math.max(2, (height / doc.defaults.stairRiserMax).ceil()),
          k = (n / 2).ceil(),
          t = doc.defaults.stairTread.toDouble(),
          riser = height / n,
          minWidth = doc.defaults.stairWidthMin.toDouble();
      final w = math.max(
          0.0,
          switch (stair.type) {
            StairType.straight => b,
            StairType.L => math.min(a - (k - 1) * t, b - (n - k - 1) * t),
            StairType.U => b / 2
          });
      final requiredA = switch (stair.type) {
        StairType.straight => (n - 1) * t,
        StairType.L => (k - 1) * t + minWidth,
        StairType.U => math.max(k - 1, n - k - 1) * t + minWidth
      };
      final requiredB = stair.type == StairType.L
          ? minWidth + (n - k - 1) * t
          : stair.type == StairType.U
              ? 2 * minWidth
              : minWidth;
      final fits = w >= minWidth && a >= requiredA && b >= requiredB;
      final steps = <({PlanRect rect, double height})>[],
          landings = <({PlanRect rect, double height})>[];
      // Local coordinates: u runs across the start edge, v goes upstairs.
      PlanRect local(double u0, double v0, double u1, double v1) {
        Point3 p(double u, double v) => switch (stair.startEdge) {
              StairEdge.bottom => (x: left + u, y: bottom + v, z: 0),
              StairEdge.top => (x: right - u, y: top - v, z: 0),
              StairEdge.left => (x: left + v, y: top - u, z: 0),
              StairEdge.right => (x: right - v, y: bottom + u, z: 0)
            };
        final p0 = p(u0, v0), p1 = p(u1, v1);
        return PlanRect(math.min(p0.x, p1.x), math.min(p0.y, p1.y),
            math.max(p0.x, p1.x), math.max(p0.y, p1.y));
      }

      if (w > 0) {
        if (stair.type == StairType.straight) {
          for (var i = 1; i < n; i++)
            steps.add(
                (rect: local(0, (i - 1) * t, w, i * t), height: i * riser));
        } else {
          final turn = (stair as TurnStair).turn,
              leftTurn = turn == StairTurn.left;
          final startU = leftTurn ? b - w : 0.0;
          for (var i = 1; i < k; i++)
            steps.add((
              rect: local(startU, (i - 1) * t, startU + w, i * t),
              height: i * riser
            ));
          final v = (k - 1) * t;
          if (stair.type == StairType.U) {
            landings.add((rect: local(0, v, b, v + w), height: k * riser));
            for (var i = k + 1; i < n; i++) {
              final u = leftTurn ? 0.0 : b - w;
              final start = v - (i - k) * t;
              steps.add(
                  (rect: local(u, start, u + w, start + t), height: i * riser));
            }
          } else {
            landings.add(
                (rect: local(startU, v, startU + w, v + w), height: k * riser));
            for (var i = k + 1; i < n; i++) {
              final u = leftTurn
                  ? startU - (i - k) * t
                  : startU + w + (i - k - 1) * t;
              steps.add((rect: local(u, v, u + t, v + w), height: i * riser));
            }
          }
        }
      }
      stairs.add(StairGeometry(stair.id, fits, r, List.unmodifiable(steps),
          List.unmodifiable(landings), requiredA, requiredB));
    }
    // A floor-top slab is split around the staircase openings.
    final xs = {
      <double>{
        0,
        width,
        for (final s in stairs) ...[
          s.opening.left.clamp(0, width),
          s.opening.right.clamp(0, width)
        ]
      }
    }.first.toList()
      ..sort();
    final ys = {
      <double>{
        0,
        depth,
        for (final s in stairs) ...[
          s.opening.bottom.clamp(0, depth),
          s.opening.top.clamp(0, depth)
        ]
      }
    }.first.toList()
      ..sort();
    for (var j = 0; j < ys.length - 1; j++)
      for (var i = 0; i < xs.length - 1; i++) {
        final x = (xs[i] + xs[i + 1]) / 2, y = (ys[j] + ys[j + 1]) / 2;
        if (stairs.any((s) => s.opening.contains(x, y))) continue;
        box(
            'Slab',
            f,
            null,
            'slab',
            PlanRect(xs[i], ys[j], xs[i + 1], ys[j + 1]),
            elevation + height - slab,
            elevation + height);
      }
    for (final stair in stairs) {
      for (final step in stair.steps)
        box('StairStep', f, StairSource(stair.stairId), 'stair', step.rect,
            elevation, elevation + step.height);
      for (final platform in stair.landings)
        box('Landing', f, StairSource(stair.stairId), 'stair', platform.rect,
            elevation, elevation + platform.height);
    }
    floors.add(
        DerivedFloor(base, openings, List.unmodifiable(stairs), elevation));
    elevation += height;
  }
  final roof = doc.roof;
  if (roof.type == RoofType.flat) {
    final t = doc.defaults.outerWallThickness.toDouble(),
        z = elevation + roof.parapetHeight!;
    for (final r in [
      PlanRect(0, 0, width, t),
      PlanRect(0, depth - t, width, depth),
      PlanRect(0, t, t, depth - t),
      PlanRect(width - t, t, width, depth - t)
    ]) box('Parapet', -1, null, 'wall', r, elevation, z);
  } else {
    final overhang = roof.overhang!.toDouble(),
        vertical = roof.ridgeDir == AxisDir.V;
    final span = vertical ? width : depth, run = vertical ? depth : width;
    final slope = math.tan(roof.pitchDeg! * math.pi / 180);
    Point3 point(double u, double v, double z) =>
        vertical ? (x: u, y: v, z: z) : (x: v, y: u, z: z);
    double z(double u) => elevation + (span / 2 - (u - span / 2).abs()) * slope;
    for (final (u0, u1) in [
      (-overhang, span / 2),
      (span / 2, span + overhang)
    ]) {
      final points = [
        point(u0, -overhang, z(u0) - slab),
        point(u1, -overhang, z(u1) - slab),
        point(u1, run + overhang, z(u1) - slab),
        point(u0, run + overhang, z(u0) - slab),
        point(u0, -overhang, z(u0)),
        point(u1, -overhang, z(u1)),
        point(u1, run + overhang, z(u1)),
        point(u0, run + overhang, z(u0))
      ];
      mesh('RoofPlane', -1, null, 'roof', points, const [
        [0, 3, 2, 1],
        [4, 5, 6, 7],
        [0, 1, 5, 4],
        [1, 2, 6, 5],
        [2, 3, 7, 6],
        [3, 0, 4, 7]
      ]);
    }
    final thickness = doc.defaults.outerWallThickness.toDouble();
    for (final (v0, v1) in [(0.0, thickness), (run - thickness, run)])
      mesh('GableWall', -1, null, 'wall', [
        point(0, v0, elevation),
        point(span, v0, elevation),
        point(span / 2, v0, z(span / 2)),
        point(0, v1, elevation),
        point(span, v1, elevation),
        point(span / 2, v1, z(span / 2))
      ], const [
        [0, 1, 2],
        [3, 5, 4],
        [0, 3, 4, 1],
        [1, 4, 5, 2],
        [2, 5, 3, 0]
      ]);
  }
  const ranks = {
    'WallPiece': 0,
    'Glass': 1,
    'DoorLeaf': 2,
    'Slab': 3,
    'StairStep': 4,
    'Landing': 4
  };
  final order = {for (var i = 0; i < elements.length; i++) elements[i]: i};
  elements.sort((a, b) {
    final fa = a.floorIndex < 0 ? doc.floors.length : a.floorIndex;
    final fb = b.floorIndex < 0 ? doc.floors.length : b.floorIndex;
    final floor = fa.compareTo(fb);
    if (floor != 0) return floor;
    final kind = (ranks[a.kind] ?? 5).compareTo(ranks[b.kind] ?? 5);
    return kind != 0 ? kind : order[a]!.compareTo(order[b]!);
  });
  final height = elements
      .expand((e) => e.vertices)
      .fold(elevation, (double top, p) => math.max(top, p.z));
  return DerivedHouse(List.unmodifiable(floors), List.unmodifiable(elements),
      width, depth, height);
}
