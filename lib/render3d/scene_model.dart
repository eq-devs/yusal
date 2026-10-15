import 'dart:math' as math;
import 'dart:ui' show Color, Offset;
import '../core/analysis/house_analysis.dart';
import '../core/document/house_document.dart';
import '../core/geometry/derived_house.dart';
import '../core/geometry/floor_base.dart';
import 'textures.dart';

/// World space for the 3D views, in metres: x to the right of the plan,
/// y up (0 = top of the ground-floor slab), z toward the bottom of the plan
/// (so the top of the drawing is −z).
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get unit {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }

  static Vec3 lerp(Vec3 a, Vec3 b, double t) => a + (b - a) * t;
}

/// Drawing order groups for the painter's algorithm: buried foundation,
/// ground, shadows, the ground-floor surface, rugs lying on it, ceilings,
/// then the rest sorted by depth, then overlays.
enum Layer3 { buried, ground, floorSurface, covering, ceiling, sorted }

class Face3 {
  Face3(this.points, this.color,
      {this.alpha = 1,
      this.layer = Layer3.sorted,
      this.source,
      this.doubleSided = false,
      this.glow = false,
      this.roof = false,
      this.furniture = false,
      this.floorIndex = 0,
      Vec3? normal,
      this.castsShadow = true,
      this.interior = false,
      this.textile,
      this.textileVariant = 0,
      this.uv})
      : normal = normal ?? _normal(points);
  final List<Vec3> points;
  final Vec3 normal;
  final Color color;
  final double alpha;
  final Layer3 layer;
  final SourceRef? source;
  final bool doubleSided, glow, roof, furniture, castsShadow;

  /// Inside the shell (inner walls, furniture, stairs, upper slabs): hidden
  /// by the outer walls and roof unless the roof is off or the house is cut.
  final bool interior;

  /// Kazakh textile pattern, mapped with [uv] (0–1 per point).
  final Textile? textile;
  final int textileVariant;
  final List<Offset>? uv;

  /// Floor the face belongs to; −1 for the roof above the top floor.
  final int floorIndex;

  static Vec3 _normal(List<Vec3> p) {
    var n = const Vec3(0, 0, 0);
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x),
          (a.x - b.x) * (a.y + b.y));
    }
    return n.unit;
  }
}

class Line3 {
  const Line3(this.a, this.b, this.color, this.width,
      {this.layer = Layer3.buried});
  final Vec3 a, b;
  final Color color;
  final double width;
  final Layer3 layer;
}

class Label3 {
  const Label3(this.at, this.title, this.subtitle, this.floorIndex);
  final Vec3 at;
  final String title, subtitle;
  final int floorIndex;
}

/// A 2D obstacle for walking, in world x / z.
class Collider {
  const Collider(this.x0, this.z0, this.x1, this.z1, this.floorIndex);
  final double x0, z0, x1, z1;
  final int floorIndex;
}

class WalkSpot {
  const WalkSpot(this.name, this.x, this.z, this.yaw, this.floorIndex);
  final String name;
  final double x, z, yaw;
  final int floorIndex;
}

class SceneOptions {
  const SceneOptions(
      {this.roof = true,
      this.furniture = true,
      this.foundation = false,
      this.walk = false,
      this.maxFloor = 999});
  final bool roof, furniture, foundation, walk;
  final int maxFloor;
}

class SceneModel {
  SceneModel(this.faces, this.lines, this.labels, this.colliders,
      this.elevations, this.width, this.depth, this.height, this.groundLevel,
      this.frontZ);
  final List<Face3> faces;
  final List<Line3> lines;
  final List<Label3> labels;
  final List<Collider> colliders;

  /// Base elevation of each floor, metres.
  final List<double> elevations;
  final double width, depth, height, groundLevel;

  /// +1 when the main entrance is on the bottom edge of the plan (+z side),
  /// −1 on the top edge; the "front" view looks at that side.
  final double frontZ;
  Vec3 get center => Vec3(width / 2, height / 3, depth / 2);
}

/// Palette after the drafting page's three.js materials.
class Mat {
  static const wall = Color(0xffEAE6DF),
      bear = Color(0xffE3DED5),
      part = Color(0xffF5F3EF),
      plinth = Color(0xff6E7472),
      roof = Color(0xff394247),
      glass = Color(0xff9EC3D2),
      frame = Color(0xffF1F1EF),
      door = Color(0xff8E6E4C),
      found = Color(0xffA9ABA7),
      cushion = Color(0xffC9B48A),
      rebar = Color(0xffB0502C),
      foundMiss = Color(0xffD9483E),
      ground = Color(0xff8E9C7F),
      wood = Color(0xffC4A177),
      tile = Color(0xffD3D6D4),
      deck = Color(0xff8A6A48),
      ceil = Color(0xffFAFAF8),
      slab = Color(0xff9C9F9A),
      coping = Color(0xff5B6468),
      membrane = Color(0xff4A5054),
      pipe = Color(0xff7A8287),
      stair = Color(0xffBABEB8),
      bed = Color(0xffDCD3C4),
      woodF = Color(0xff9F7F5A),
      sofa = Color(0xff5F7179),
      counter = Color(0xffCCC7BE),
      white = Color(0xffF4F4F2),
      table = Color(0xff7C5E40),
      appl = Color(0xffB8BEC1),
      dastTop = Color(0xff8A5A34);
  static const rugs = [Color(0xff8E1C1C), Color(0xff6E1630), Color(0xff1F3B5A)];
  static const rugBorders = [
    Color(0xff1D2A48),
    Color(0xff2C1A12),
    Color(0xff7A1B1B)
  ];
  static const wallRugs = [Color(0xff2B0E16), Color(0xff14233A), Color(0xff3B1A10)];
  static const korpe = [Color(0xffB0302A), Color(0xff7A2338), Color(0xff2E6A8E)];
  static const sandyq = [Color(0xff7A1E1E), Color(0xff1F5E63), Color(0xff5E3A1E)];
}

SceneModel buildScene(HouseDocument doc, DerivedHouse derived,
    SceneOptions options, String Function(Room) roomName,
    {String areaUnit = 'm²'}) {
  final faces = <Face3>[];
  final lines = <Line3>[];
  final labels = <Label3>[];
  final colliders = <Collider>[];
  final w = doc.footprint.width / 1000, d = doc.footprint.depth / 1000;
  final spec = doc.extras.foundation;
  final gl = -spec.plinth / 1000;
  double px(num v) => v / 1000;
  double pz(num v) => d - v / 1000;

  void box(double x0, double y0, double z0, double x1, double y1, double z1,
      Color color,
      {double alpha = 1,
      Layer3 layer = Layer3.sorted,
      SourceRef? source,
      bool roof = false,
      bool furniture = false,
      int floor = 0,
      bool shadow = true,
      bool top = true,
      bool bottom = false,
      bool glow = false,
      bool interior = false,
      Textile? textile,
      int variant = 0}) {
    if (x1 - x0 <= 1e-4 || y1 - y0 <= 1e-4 || z1 - z0 <= 1e-4) return;
    Vec3 p(double x, double y, double z) => Vec3(x, y, z);
    // Patchwork and runner stripes repeat at their real size; rugs, wall
    // hangings and chests show the whole pattern once per face.
    final tile = switch (textile) {
      Textile.kurak => 0.6,
      Textile.alasha => 1.0,
      _ => null
    };
    List<Offset>? uvFor(List<Vec3> pts) {
      if (textile == null) return null;
      if (tile == null)
        return const [Offset(0, 0), Offset(0, 1), Offset(1, 1), Offset(1, 0)];
      final v = (pts[1] - pts[0]).length / tile, u = (pts[3] - pts[0]).length / tile;
      return [Offset.zero, Offset(0, v), Offset(u, v), Offset(u, 0)];
    }

    void f(List<Vec3> pts, {Layer3? l}) => faces.add(Face3(pts, color,
        textile: textile,
        textileVariant: variant,
        uv: uvFor(pts),
        alpha: alpha,
        layer: l ?? layer,
        source: source,
        roof: roof,
        furniture: furniture,
        floorIndex: floor,
        castsShadow: shadow,
        glow: glow,
        interior: interior || furniture));
    // Counter-clockwise seen from outside.
    if (top)
      f([p(x0, y1, z0), p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0)]);
    if (bottom)
      f([p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1)]);
    f([p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1)]); // +z
    f([p(x1, y0, z0), p(x0, y0, z0), p(x0, y1, z0), p(x1, y1, z0)]); // −z
    f([p(x1, y0, z1), p(x1, y0, z0), p(x1, y1, z0), p(x1, y1, z1)]); // +x
    f([p(x0, y0, z0), p(x0, y0, z1), p(x0, y1, z1), p(x0, y1, z0)]); // −x
  }

  // Plan rect (mm) to world box.
  void planBox(PlanRect r, double y0, double y1, Color color,
          {double alpha = 1,
          Layer3 layer = Layer3.sorted,
          SourceRef? source,
          bool roof = false,
          bool furniture = false,
          int floor = 0,
          bool shadow = true,
          bool top = true,
          bool bottom = false,
          bool glow = false,
          bool interior = false}) =>
      box(px(r.left), y0, pz(r.top), px(r.right), y1, pz(r.bottom), color,
          alpha: alpha,
          layer: layer,
          source: source,
          roof: roof,
          furniture: furniture,
          floor: floor,
          shadow: shadow,
          top: top,
          bottom: bottom,
          glow: glow,
          interior: interior);

  final elevations = <double>[];
  var elevation = 0.0;
  final visibleFloors = math.min(options.maxFloor, doc.floors.length - 1);
  for (var f = 0; f < doc.floors.length; f++) {
    final floor = doc.floors[f], g = derived.floors[f];
    final h = floor.height / 1000;
    elevations.add(elevation);
    if (f > visibleFloors) {
      elevation += h;
      continue;
    }
    final slab = doc.defaults.slabThickness / 1000;
    // Floor slab under this floor (ground floor: on the plinth).
    planBox(PlanRect(0, 0, doc.footprint.width.toDouble(),
            doc.footprint.depth.toDouble()), elevation - slab, elevation, Mat.slab,
        layer: f == 0 ? Layer3.floorSurface : Layer3.sorted,
        floor: f,
        top: f != 0,
        interior: f != 0);
    // Room floors: wood in living spaces, tiles in wet rooms.
    for (final room in floor.rooms) {
      final s = g.base.roomGeometry.firstWhere((r) => r.id == room.id);
      final wet = room.type == RoomType.kitchen ||
          room.type == RoomType.bathroom ||
          room.type == RoomType.custom;
      for (final r in s.clearRects)
        faces.add(Face3([
          Vec3(px(r.left), elevation + 0.002, pz(r.top)),
          Vec3(px(r.left), elevation + 0.002, pz(r.bottom)),
          Vec3(px(r.right), elevation + 0.002, pz(r.bottom)),
          Vec3(px(r.right), elevation + 0.002, pz(r.top)),
        ], wet ? Mat.tile : Mat.wood,
            layer: f == 0 ? Layer3.floorSurface : Layer3.sorted,
            source: RoomSource(room.id),
            floorIndex: f,
            castsShadow: false,
            interior: f != 0));
      if (s.clearRects.isNotEmpty) {
        final l = s.labelAnchor;
        labels.add(Label3(
            Vec3(px(l.x), elevation + 1.2, pz(l.y)),
            roomName(room),
            '${(s.clearArea / 1e6).toStringAsFixed(1)} $areaUnit',
            f));
      }
    }
    // Walls, split around openings by the core.
    final walls = wallsOf(g.base, spec);
    for (final e in derived.scene3d
        .where((e) => e.floorIndex == f && e.kind == 'WallPiece')) {
      final xs = e.vertices.map((v) => v.x), ys = e.vertices.map((v) => v.y),
          zs = e.vertices.map((v) => v.z);
      final r = PlanRect(xs.reduce(math.min), ys.reduce(math.min),
          xs.reduce(math.max), ys.reduce(math.max));
      final z0 = zs.reduce(math.min) / 1000, z1 = zs.reduce(math.max) / 1000;
      final source = e.source as WallSource?;
      final info = walls
          .where((w) => w.segment.ref == source?.wall)
          .firstOrNull;
      final color = e.materialRole == 'wallTemporary'
          ? Mat.part
          : switch (info?.role) {
              WallRole.bearing => Mat.bear,
              WallRole.partition => Mat.part,
              _ => Mat.wall
            };
      planBox(r, z0, z1, color,
          alpha: e.materialRole == 'wallTemporary' ? 0.45 : 1,
          source: source,
          floor: f,
          interior: info?.role != WallRole.exterior);
      if (z0 - elevation < 0.3 && z1 - elevation > 0.3)
        colliders.add(Collider(px(r.left), pz(r.top), px(r.right), pz(r.bottom), f));
    }
    // Plinth under the exterior walls of the ground floor.
    if (f == 0)
      for (final wall in walls.where((w) => w.role == WallRole.exterior)) {
        final r = wall.rect;
        planBox(PlanRect(r.left - 45, r.bottom - 45, r.right + 45, r.top + 45),
            gl, 0, Mat.plinth,
            floor: f);
      }
    // Windows (glass + frame) and doors (leaf swung open).
    for (final p in g.openings.where((p) => p.status == 'ok')) {
      final o = p.opening, horizontal = p.axis.dir == AxisDir.H;
      final hostIndex = g.base.wallSegments.indexWhere((s) => s.ref == p.host!.ref);
      final host = g.base.wallRects[hostIndex];
      final c0 = horizontal ? host.bottom : host.left,
          c1 = horizontal ? host.top : host.right;
      final c = (c0 + c1) / 2;
      final y0 = elevation + o.sill / 1000, y1 = y0 + o.height / 1000;
      final source = OpeningSource(o.id);
      final inner = p.host?.kind != 'exterior';
      void along(double a0, double a1, double ya, double yb, double t,
          Color color,
          {double alpha = 1, bool glow = false, bool doubleSided = false}) {
        final r = horizontal
            ? PlanRect(a0, c - t / 2, a1, c + t / 2)
            : PlanRect(c - t / 2, a0, c + t / 2, a1);
        planBox(r, ya, yb, color,
            alpha: alpha, source: source, floor: f, glow: glow,
            bottom: true, shadow: !glow, interior: inner);
      }

      if (o is DoorOpening) {
        final len = p.end - p.start - 40;
        final sign = o.opensTo == OpeningSide.positiveSide ? 1.0 : -1.0;
        final face = sign > 0 ? c1 : c0;
        final hinge = o.hinge == Hinge.start ? p.start + 20 : p.end - 60;
        final leaf = horizontal
            ? PlanRect(hinge, sign > 0 ? face : face - len, hinge + 40,
                sign > 0 ? face + len : face)
            : PlanRect(sign > 0 ? face : face - len, hinge,
                sign > 0 ? face + len : face, hinge + 40);
        planBox(leaf, y0, y1 - 0.02, Mat.door,
            source: source, floor: f, interior: true);
        continue;
      }
      const ft = 70.0, fd = 100.0;
      final sliding = o is SlidingOpening;
      final mid = (p.start + p.end) / 2;
      along(p.start, sliding ? mid + 50 : p.end, y0, y1, 20, Mat.glass,
          alpha: 0.32, glow: true);
      if (sliding)
        along(mid - 50, p.end, y0, y1, 20, Mat.glass, alpha: 0.32, glow: true);
      along(p.start, p.end, y0, y0 + ft / 1000, fd, Mat.frame);
      along(p.start, p.end, y1 - ft / 1000, y1, fd, Mat.frame);
      along(p.start, p.start + ft, y0, y1, fd, Mat.frame);
      along(p.end - ft, p.end, y0, y1, fd, Mat.frame);
      if (!sliding && p.end - p.start > 1300)
        along(mid - ft / 2, mid + ft / 2, y0, y1, fd, Mat.frame);
      if (sliding) along(mid - ft, mid + ft, y0, y1, fd, Mat.frame);
      if (p.host?.kind == 'exterior' && o.sill > 0) {
        // Sill board on the outside face.
        final out = switch (p.axis.id) {
          '@left' || '@bottom' => -1.0,
          '@right' || '@top' => 1.0,
          _ => 1.0
        };
        final fz = out < 0 ? c0 : c1;
        final r = horizontal
            ? PlanRect(p.start - 50, out < 0 ? fz - 80 : fz, p.end + 50,
                out < 0 ? fz : fz + 80)
            : PlanRect(out < 0 ? fz - 80 : fz, p.start - 50, out < 0 ? fz : fz + 80,
                p.end + 50);
        planBox(r, y0 - 0.04, y0, Mat.plinth, floor: f);
      }
    }
    // Stairs.
    for (final s in g.stairs) {
      for (final step in [...s.steps, ...s.landings])
        planBox(step.rect, elevation, elevation + step.height / 1000, Mat.stair,
            source: StairSource(s.stairId), floor: f, interior: true);
    }
    // Ceiling of this floor for the walk-through.
    if (options.walk)
      faces.add(Face3([
        Vec3(0, elevation + h - slab - 0.005, 0),
        Vec3(w, elevation + h - slab - 0.005, 0),
        Vec3(w, elevation + h - slab - 0.005, d),
        Vec3(0, elevation + h - slab - 0.005, d),
      ], Mat.ceil, layer: Layer3.ceiling, floorIndex: f, castsShadow: false));
    // Furniture.
    if (options.furniture || options.walk)
      for (final item
          in doc.extras.furniture.where((i) => i.floorId == floor.id))
        furnitureFaces(item, elevation, f, box, faces, d);
    elevation += h;
  }

  // Roof over the top floor.
  final top = elevation;
  final showRoof = options.roof && visibleFloors >= doc.floors.length - 1;
  final roof = doc.roof;
  if (showRoof && !options.walk) {
    if (roof.type == RoofType.flat) {
      // Slab on the walls, insulation and membrane inside the parapet,
      // scuppers and downpipes at the back, a roof hatch.
      final slab = doc.defaults.slabThickness / 1000;
      final parT = doc.defaults.outerWallThickness / 1000;
      final parH = roof.parapetHeight! / 1000;
      final rs = top + slab, rt = rs + 0.25;
      box(0, top, 0, w, rs, d, Mat.wall, roof: true, floor: -1);
      box(parT, rs, parT, w - parT, rt, d - parT, Mat.membrane,
          roof: true, floor: -1);
      if (parH > slab)
        for (final (x0, z0, x1, z1) in [
          (0.0, 0.0, w, parT),
          (0.0, d - parT, w, d),
          (0.0, parT, parT, d - parT),
          (w - parT, parT, w, d - parT)
        ]) {
          box(x0, rs, z0, x1, top + parH, z1, Mat.bear, roof: true, floor: -1);
          box(x0 - 0.04, top + parH, z0 - 0.04, x1 + 0.04, top + parH + 0.05,
              z1 + 0.04, Mat.coping,
              roof: true, floor: -1);
        }
      for (final x in [1.5, w - 1.5]) {
        if (x < 0.5 || x > w - 0.5) continue;
        box(x - 0.15, rt, -0.18, x + 0.15, rt + 0.12, parT, Mat.coping,
            roof: true, floor: -1);
        box(x - 0.06, gl, -0.35, x + 0.06, rt + 0.1, -0.23, Mat.pipe,
            roof: true, floor: -1);
      }
      box(w / 2 - 0.4, rt, d / 2 - 0.4, w / 2 + 0.4, rt + 0.35, d / 2 + 0.4,
          Mat.coping,
          roof: true, floor: -1);
    } else {
      for (final e in derived.scene3d.where((e) => e.floorIndex == -1)) {
        final pts = [
          for (final v in e.vertices) Vec3(px(v.x), v.z / 1000, pz(v.y))
        ];
        for (final face in e.faces)
          faces.add(Face3([for (final i in face) pts[i]],
              e.kind == 'RoofPlane' ? Mat.roof : Mat.bear,
              roof: true, floorIndex: -1, doubleSided: e.kind == 'RoofPlane'));
      }
    }
  }

  // Site furniture (terrace, porch) sits outside the plan already.
  // Foundation strips with cushion and reinforcement.
  if (options.foundation && !options.walk) {
    final takeoff = foundationTakeoff(doc, derived);
    var stirrups = 0;
    for (final s in takeoff.strips) {
      final hh = s.height / 1000;
      final color = s.exists ? Mat.found : Mat.foundMiss;
      planBox(s.rect, -hh, -0.002, color,
          alpha: s.exists ? 0.5 : 0.55,
          layer: Layer3.buried,
          bottom: true,
          shadow: false);
      if (!s.exists) continue;
      planBox(s.cushion, -hh - spec.cushion / 1000, -hh, Mat.cushion,
          layer: Layer3.buried, bottom: true, shadow: false);
      final main = s.main;
      final cover = spec.cover / 1000 + 0.01;
      final r = s.rect;
      final horizontal = s.wall.horizontal;
      final a0 = horizontal ? px(r.left) : pz(r.top),
          a1 = horizontal ? px(r.right) : pz(r.bottom);
      final cc = horizontal ? pz((r.bottom + r.top) / 2) : px((r.left + r.right) / 2);
      final half = s.width / 2000 - cover;
      final bars = main ? math.max(spec.topBars, spec.bottomBars) : 2;
      for (final y in [-hh + cover, -cover])
        for (var i = 0; i < bars; i++) {
          final o = bars == 1 ? 0.0 : -half + i * 2 * half / (bars - 1);
          final a = horizontal ? Vec3(a0, y, cc + o) : Vec3(cc + o, y, a0);
          final b = horizontal ? Vec3(a1, y, cc + o) : Vec3(cc + o, y, a1);
          lines.add(Line3(a, b, Mat.rebar, 2.2));
        }
      final step = spec.stirrupStep / 1000;
      for (var a = a0 + 0.1; a < a1 - 0.05 && stirrups < 500; a += step) {
        stirrups++;
        final y0 = -hh + spec.cover / 1000, y1 = -spec.cover / 1000;
        final h0 = cc - half - 0.01, h1 = cc + half + 0.01;
        Vec3 v(double across, double y) =>
            horizontal ? Vec3(a, y, across) : Vec3(across, y, a);
        final loop = [v(h0, y0), v(h1, y0), v(h1, y1), v(h0, y1)];
        for (var k = 0; k < 4; k++)
          lines.add(Line3(loop[k], loop[(k + 1) % 4], Mat.rebar, 1));
      }
    }
  }

  // Walk spots: outside the front door and in every room.
  final entrance = derived.floors.first.openings
      .where((p) => p.opening.id == doc.mainEntranceOpeningId)
      .firstOrNull;
  var frontZ = 1.0;
  if (entrance != null && entrance.axis.id == '@top') frontZ = -1.0;
  return SceneModel(faces, lines, labels, colliders, elevations, w, d,
      math.max(top, 1), gl, frontZ);
}

typedef _BoxFn = void Function(double x0, double y0, double z0, double x1,
    double y1, double z1, Color color,
    {double alpha,
    Layer3 layer,
    SourceRef? source,
    bool roof,
    bool furniture,
    int floor,
    bool shadow,
    bool top,
    bool bottom,
    bool glow,
    bool interior,
    Textile? textile,
    int variant});

/// Simple shapes for each piece of furniture, coloured like the drafting
/// page (Kazakh textiles keep their reds, blues and golds).
void furnitureFaces(FurnitureItem item, double elevation, int floor, _BoxFn box,
    List<Face3> faces, double planDepth) {
  final w = item.width / 1000, dp = item.depth / 1000, h = item.height / 1000;
  final x0 = item.x / 1000 + 0.01;
  // Plan y grows up the drawing, world z grows down it.
  final v = item.variant % 3;
  final y0 = elevation + item.elevation / 1000;
  final z1 = planDepth - item.y / 1000 - 0.01, z0 = z1 - dp + 0.02;
  final x1 = x0 + w - 0.02;
  final source = FurnitureSource(item.id);
  void b(double ax0, double ay0, double az0, double ax1, double ay1, double az1,
          Color c,
          {bool shadow = true,
          Textile? textile,
          int variant = 0,
          bool covering = false}) =>
      box(ax0, ay0, az0, ax1, ay1, az1, c,
          source: source,
          furniture: true,
          floor: floor,
          shadow: shadow,
          textile: textile,
          variant: variant,
          // Rugs on the ground floor lie under everything else.
          layer: covering && floor == 0 ? Layer3.covering : Layer3.sorted);
  switch (item.kind) {
    case FurnitureKind.rug:
      b(x0, y0, z0, x1, y0 + 0.015, z1, Mat.rugs[v],
          shadow: false, textile: Textile.kilem, variant: v, covering: true);
    case FurnitureKind.alasha:
      b(x0, y0, z0, x1, y0 + 0.012, z1, const Color(0xff7E1E1E),
          shadow: false, textile: Textile.alasha, covering: true);
    case FurnitureKind.wallRug:
      b(x0, y0, z0, x1, y0 + h, z1, Mat.wallRugs[v],
          textile: Textile.tus, variant: v);
    case FurnitureKind.korpe || FurnitureKind.cushion:
      b(x0, y0, z0, x1, y0 + h, z1, Mat.korpe[v],
          textile: Textile.kurak, variant: v);
    case FurnitureKind.dastarkhan:
      final cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, r = math.min(w, dp) / 2;
      const n = 16;
      List<Vec3> ring(double y, double rr) => [
            for (var k = 0; k < n; k++)
              Vec3(cx + rr * math.cos(k * 2 * math.pi / n), y,
                  cz + rr * math.sin(k * 2 * math.pi / n))
          ];
      final topRing = ring(y0 + h, r), midRing = ring(y0 + h - 0.05, r);
      final legTop = ring(y0 + h - 0.05, r * 0.75), legBottom = ring(y0, r * 0.8);
      faces.add(Face3(topRing.reversed.toList(), Mat.dastTop,
          source: source, furniture: true, floorIndex: floor));
      for (var k = 0; k < n; k++) {
        final k1 = (k + 1) % n;
        faces.add(Face3([topRing[k], topRing[k1], midRing[k1], midRing[k]],
            Mat.dastTop, source: source, furniture: true, floorIndex: floor));
        faces.add(Face3([legTop[k], legTop[k1], legBottom[k1], legBottom[k]],
            Mat.table, source: source, furniture: true, floorIndex: floor));
      }
    case FurnitureKind.sandyq:
      b(x0, y0, z0, x1, y0 + h, z1, Mat.sandyq[v],
          textile: Textile.sandyq, variant: v);
      // Folded quilts stacked on the chest (жүк).
      for (var k = 0; k < 5; k++) {
        final ins = 0.03 + (k % 2) * 0.03;
        b(x0 + ins, y0 + h + k * 0.1, z0 + ins * 0.6, x1 - ins,
            y0 + h + k * 0.1 + 0.1, z1 - ins * 0.4, Mat.korpe[(k + v) % 3],
            textile: Textile.kurak, variant: k + v);
      }
    case FurnitureKind.bed || FurnitureKind.singleBed:
      b(x0, y0, z0, x1, y0 + h, z1, Mat.bed);
      final long = w >= dp;
      // Patchwork quilt and a pillow.
      if (long) {
        b(x0 + 0.04, y0 + h, z0 + 0.04, x1 - 0.42, y0 + h + 0.06, z1 - 0.04,
            Mat.korpe[2], textile: Textile.kurak, variant: 2);
        b(x1 - 0.38, y0 + h, z0 + 0.12, x1 - 0.06, y0 + h + 0.14, z1 - 0.12,
            Mat.korpe[1]);
      } else {
        b(x0 + 0.04, y0 + h, z0 + 0.42, x1 - 0.04, y0 + h + 0.06, z1 - 0.04,
            Mat.korpe[2], textile: Textile.kurak, variant: 2);
        b(x0 + 0.12, y0 + h, z0 + 0.06, x1 - 0.12, y0 + h + 0.14, z0 + 0.38,
            Mat.korpe[1]);
      }
    case FurnitureKind.sofa:
      b(x0, y0, z0, x1, y0 + h * 0.5, z1, Mat.sofa);
      final long = w >= dp;
      long
          ? b(x0, y0 + h * 0.5, z0, x1, y0 + h, z0 + 0.2, Mat.sofa)
          : b(x0, y0 + h * 0.5, z0, x0 + 0.2, y0 + h, z1, Mat.sofa);
    case FurnitureKind.table ||
          FurnitureKind.diningTable ||
          FurnitureKind.desk:
      b(x0, y0 + h - 0.04, z0, x1, y0 + h, z1, Mat.table);
      for (final (lx, lz) in [(x0, z0), (x1 - 0.05, z0), (x0, z1 - 0.05), (x1 - 0.05, z1 - 0.05)])
        b(lx, y0, lz, lx + 0.05, y0 + h - 0.04, lz + 0.05, Mat.table);
    case FurnitureKind.terrace || FurnitureKind.porch:
      b(x0, y0 - 0.25, z0, x1, y0 + h - 0.25, z1, Mat.deck);
    default:
      final color = switch (item.kind) {
        FurnitureKind.wardrobe ||
        FurnitureKind.pantry ||
        FurnitureKind.shelf ||
        FurnitureKind.shoeCabinet ||
        FurnitureKind.tvStand ||
        FurnitureKind.hooks =>
          Mat.woodF,
        FurnitureKind.counter => Mat.counter,
        FurnitureKind.bathtub ||
        FurnitureKind.toilet ||
        FurnitureKind.basin ||
        FurnitureKind.sink ||
        FurnitureKind.fridge ||
        FurnitureKind.shower =>
          Mat.white,
        FurnitureKind.stove ||
        FurnitureKind.washer ||
        FurnitureKind.boiler =>
          Mat.appl,
        FurnitureKind.chair || FurnitureKind.bench => Mat.table,
        _ => Mat.counter
      };
      b(x0, y0, z0, x1, y0 + h, z1, color);
  }
}
