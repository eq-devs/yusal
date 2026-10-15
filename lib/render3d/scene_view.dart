import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../core/axis/axis_resolver.dart';
import '../core/document/house_document.dart';
import '../core/geometry/derived_house.dart';
import 'scene_model.dart';
import 'textures.dart';

/// What the 3D page shows; kept by the editor so it survives page changes.
class SceneSettings {
  const SceneSettings(
      {this.roof = true,
      this.furniture = true,
      this.foundation = false,
      this.cut = false,
      this.cutHeight = 1.4,
      this.hour = 11,
      this.maxFloor = 999,
      this.dark = false});
  final bool roof, furniture, foundation, cut, dark;
  final double cutHeight, hour;
  final int maxFloor;
  SceneSettings copyWith(
          {bool? roof,
          bool? furniture,
          bool? foundation,
          bool? cut,
          double? cutHeight,
          double? hour,
          int? maxFloor,
          bool? dark}) =>
      SceneSettings(
          roof: roof ?? this.roof,
          furniture: furniture ?? this.furniture,
          foundation: foundation ?? this.foundation,
          cut: cut ?? this.cut,
          cutHeight: cutHeight ?? this.cutHeight,
          hour: hour ?? this.hour,
          maxFloor: maxFloor ?? this.maxFloor,
          dark: dark ?? this.dark);
  bool get night => dark || hour < 6 || hour > 20.5;
}

class Camera {
  Camera(this.eye, this.forward, this.fov) {
    final up0 = forward.y.abs() > 0.999 ? const Vec3(0, 0, -1) : const Vec3(0, 1, 0);
    right = forward.cross(up0).unit;
    up = right.cross(forward).unit;
  }
  final Vec3 eye, forward;
  final double fov;
  late final Vec3 right, up;
  Vec3 toCamera(Vec3 p) {
    final d = p - eye;
    return Vec3(d.dot(right), d.dot(up), d.dot(forward));
  }
}

class _Item {
  _Item(this.path, this.color, this.depth, this.layer, this.source,
      {this.stroke = 0, this.vertices, this.image, this.tiled = false});
  final Path path;
  final Color color;
  final double depth;
  final int layer;
  final SourceRef? source;
  final double stroke;

  /// Textured faces: projected triangles with the pattern image.
  final ui.Vertices? vertices;
  final ui.Image? image;
  final bool tiled;
}

class ScenePainter extends CustomPainter {
  ScenePainter(
      {required this.model,
      required this.camera,
      required this.settings,
      required this.northAngleDeg,
      required this.walk,
      required this.labels,
      this.selected,
      super.repaint});
  final SceneModel model;
  final Camera camera;
  final SceneSettings settings;
  final int northAngleDeg;
  final bool walk, labels;
  final SourceRef? selected;
  List<_Item> items = [];

  /// Layer and source of each drawn item, for tests.
  List<(int, SourceRef?)> get debugItems =>
      [for (final i in items) (i.layer, i.source)];
  Path? groundPath;
  Paint? groundPaint;

  static const skyDay = Color(0xffDCE5E8), skyNight = Color(0xff0C1420);
  static const near = 0.05;

  Vec3 get sun {
    final a = northAngleDeg * math.pi / 180;
    final n = Vec3(math.sin(a), 0, -math.cos(a)),
        e = Vec3(math.cos(a), 0, math.sin(a));
    final tp = (settings.hour - 12) * math.pi / 12;
    final h = n * -math.cos(tp) + e * -math.sin(tp);
    final el = math.max(0.06, (58 * math.pi / 180) * math.cos(tp * 0.92));
    return (h * math.cos(el) + Vec3(0, math.sin(el), 0)).unit;
  }

  /// Whether the walker stands inside the house outline.
  bool get walkerInside =>
      camera.eye.x > 0 &&
      camera.eye.x < model.width &&
      camera.eye.z > 0 &&
      camera.eye.z < model.depth;

  SourceRef? pick(Offset p) {
    for (final i in items.reversed)
      if (i.stroke == 0 && i.source != null && i.path.contains(p))
        return i.source;
    return null;
  }

  Offset? project(Vec3 c, Size size, double focal) {
    // Points clipped onto the near plane are still drawable.
    if (c.z < near * 0.5) return null;
    return Offset(size.width / 2 + c.x / c.z * focal,
        size.height / 2 - c.y / c.z * focal);
  }

  /// Keep the part of a polygon in front of the camera (camera space).
  List<Vec3> clipNear(List<Vec3> poly) => clip(poly, (p) => p.z - near);

  static List<Vec3> clip(List<Vec3> poly, double Function(Vec3) inside) {
    final out = <Vec3>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final da = inside(a), db = inside(b);
      if (da >= 0) out.add(a);
      if ((da >= 0) != (db >= 0)) out.add(Vec3.lerp(a, b, da / (da - db)));
    }
    return out;
  }

  Color shade(Face3 f, Vec3 n, double distance, Vec3 light) {
    final night = settings.night;
    final sky = night ? skyNight : skyDay;
    if (f.glow && night) return const Color(0xffFFC46B);
    double r = f.color.r, g = f.color.g, b = f.color.b;
    final up = n.y * 0.5 + 0.5;
    double lr, lg, lb;
    if (night) {
      // Moonlight outside; warm lamps inside when walking through (seen
      // only through the windows while standing outside).
      final lamp = walk && (walkerInside || f.interior) ? 0.5 : 0.0;
      final moon = math.max(0.0, n.dot(const Vec3(-0.45, 0.82, 0.35).unit));
      lr = 0.16 + 0.08 * up + 0.08 * moon + lamp;
      lg = 0.19 + 0.10 * up + 0.09 * moon + lamp * 0.82;
      lb = 0.26 + 0.14 * up + 0.12 * moon + lamp * 0.6;
    } else {
      // Soft sky light everywhere, warmer sunlight on faces toward the sun.
      final el = math.asin(light.y.clamp(-1.0, 1.0));
      final warm = math.min(1.0, el / 0.6);
      final s = math.max(0.0, n.dot(light)) * (0.55 + 0.45 * warm);
      final base = walk ? 0.66 : 0.60;
      lr = base + 0.18 * up + 0.24 * s;
      lg = base + 0.18 * up + 0.24 * s * (0.86 + 0.12 * warm);
      lb = base + 0.19 * up + 0.24 * s * (0.70 + 0.25 * warm);
    }
    r = (r * lr).clamp(0, 1);
    g = (g * lg).clamp(0, 1);
    b = (b * lb).clamp(0, 1);
    if (f.source != null && f.source == selected) {
      r = r * 0.55 + 0.45 * (0xE5 / 255);
      g = g * 0.55 + 0.45 * (0x95 / 255);
      b = b * 0.55 + 0.45 * (0x2F / 255);
    }
    if (!walk) {
      final t = ((distance - 45) / 65).clamp(0.0, 1.0);
      r = r + (sky.r - r) * t;
      g = g + (sky.g - g) * t;
      b = b + (sky.b - b) * t;
    }
    return Color.from(alpha: 1, red: r, green: g, blue: b);
  }

  /// The roof shows when switched on and every floor is shown.
  bool get roofOn =>
      settings.roof && settings.maxFloor >= model.elevations.length - 1;

  bool visible(Face3 f) {
    if (f.roof && (!roofOn || settings.cut) && !walk) return false;
    if (f.furniture && !settings.furniture && !walk) return false;
    if (f.floorIndex > settings.maxFloor) return false;
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final night = settings.night;
    canvas.drawRect(Offset.zero & size, Paint()..color = night ? skyNight : skyDay);
    final focal = size.height / 2 / math.tan(camera.fov / 2);
    final light = sun;
    final cutY = settings.cut && !walk ? settings.cutHeight : double.infinity;
    final foundation = settings.foundation && !walk;
    items = [];
    groundPath = null;
    void addPoly(List<Vec3> world, Color color, double alpha, int layer,
        SourceRef? source) {
      final cam = clipNear([for (final p in world) camera.toCamera(p)]);
      if (cam.length < 3) return;
      final path = Path();
      var depth = 0.0;
      for (var i = 0; i < cam.length; i++) {
        final s = project(cam[i], size, focal)!;
        i == 0 ? path.moveTo(s.dx, s.dy) : path.lineTo(s.dx, s.dy);
        depth += cam[i].z;
      }
      path.close();
      items.add(_Item(path, color.withValues(alpha: alpha), depth / cam.length,
          layer, source));
    }

    // Ground: one large square, fading into the sky toward the horizon
    // (a screen-space gradient stands in for fog).
    final c = model.center;
    final g = model.groundLevel;
    const span = 70.0;
    final sky = night ? skyNight : skyDay;
    final ground = _lit(Mat.ground, night);
    final groundPoly = clipNear([
      for (final p in [
        Vec3(c.x - span, g, c.z - span),
        Vec3(c.x - span, g, c.z + span),
        Vec3(c.x + span, g, c.z + span),
        Vec3(c.x + span, g, c.z - span),
      ])
        camera.toCamera(p)
    ]);
    if (groundPoly.length >= 3) {
      final path = Path();
      for (var i = 0; i < groundPoly.length; i++) {
        final p = project(groundPoly[i], size, focal)!;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      var dir = Vec3(camera.forward.x, 0, camera.forward.z);
      dir = dir.length < 1e-3 ? const Vec3(0, 0, -1) : dir.unit;
      double screenY(double distance) {
        final q = camera.toCamera(Vec3(camera.eye.x + dir.x * distance, g,
            camera.eye.z + dir.z * distance));
        return project(q, size, focal)?.dy ?? 0;
      }

      final nearY = screenY(40), farY = screenY(110);
      final paint = Paint();
      if (!walk && (nearY - farY).abs() > 1) {
        paint.shader = ui.Gradient.linear(Offset(0, farY), Offset(0, nearY),
            [sky.withValues(alpha: foundation ? 0.28 : 1), ground.withValues(alpha: foundation ? 0.28 : 1)]);
      } else {
        paint.color = ground.withValues(alpha: foundation ? 0.28 : 1);
      }
      groundPaint = paint;
      groundPath = path;
    }

    // Sun shadows of the house on the ground.
    if (!night && light.y > 0.05 && !walk) {
      final shadow = Path()..fillType = PathFillType.nonZero;
      for (final f in model.faces) {
        if (!f.castsShadow || f.layer != Layer3.sorted || !visible(f)) continue;
        if (f.normal.dot(light) <= 0) continue;
        final pts = <Offset>[];
        var ok = true;
        for (final p in f.points) {
          if (p.y > cutY) {
            ok = false;
            break;
          }
          final t = (p.y - g) / light.y;
          final q = camera.toCamera(Vec3(p.x - light.x * t, g + 0.001, p.z - light.z * t));
          final s = project(q, size, focal);
          if (s == null) {
            ok = false;
            break;
          }
          pts.add(s);
        }
        if (ok && pts.length >= 3) shadow.addPolygon(pts, true);
      }
      items.add(_Item(shadow, Colors.black.withValues(alpha: 0.22), 0, 2, null));
    }

    for (final f in model.faces) {
      if (!visible(f)) continue;
      if (f.layer == Layer3.buried && !foundation) continue;
      if (f.layer == Layer3.ceiling && !walk) continue;
      var pts = f.points;
      if (cutY.isFinite && f.floorIndex >= 0) {
        if (pts.every((p) => p.y > cutY)) continue;
        if (pts.any((p) => p.y > cutY))
          pts = clip(pts, (p) => cutY - p.y);
        if (pts.length < 3) continue;
      } else if (cutY.isFinite && f.floorIndex < 0) {
        continue;
      }
      final toEye = camera.eye - pts.first;
      var n = f.normal;
      final facing = n.dot(toEye);
      if (facing <= 0) {
        if (!f.doubleSided && f.alpha >= 1 && !(cutY.isFinite)) continue;
        n = n * -1;
      }
      var centre = const Vec3(0, 0, 0);
      for (final p in pts) centre = centre + p;
      centre = centre * (1 / pts.length);
      // With the roof on, the inside is only seen through glass: draw it
      // before the shell so walls and roof always cover it.
      final shell = !walk && roofOn && !cutY.isFinite;
      final layer = switch (f.layer) {
        Layer3.buried => 0,
        Layer3.ground => 1,
        Layer3.floorSurface => 3,
        Layer3.covering => f.interior && shell ? 6 : 4,
        Layer3.ceiling => 5,
        Layer3.sorted => f.interior && shell ? 6 : 7,
      };
      final alpha = f.glow && night ? 0.62 : f.alpha;
      if (f.textile != null && f.uv != null && identical(pts, f.points)) {
        addTextured(f, pts, n, (centre - camera.eye).length, light, layer, size,
            focal);
        continue;
      }
      addPoly(pts, shade(f, n, (centre - camera.eye).length, light), alpha,
          layer, f.source);
    }
    if (foundation)
      for (final l in model.lines) {
        var a = camera.toCamera(l.a), b = camera.toCamera(l.b);
        if (a.z <= near && b.z <= near) continue;
        if (a.z <= near) a = Vec3.lerp(a, b, (near - a.z) / (b.z - a.z) + 1e-6);
        if (b.z <= near) b = Vec3.lerp(b, a, (near - b.z) / (a.z - b.z) + 1e-6);
        final p0 = project(a, size, focal), p1 = project(b, size, focal);
        if (p0 == null || p1 == null) continue;
        final path = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy);
        items.add(_Item(path, l.color, (a.z + b.z) / 2, 0, null,
            stroke: (l.width * 6 / math.max(1.0, (a.z + b.z) / 2))
                .clamp(0.6, 3.0)));
      }
    items.sort((a, b) {
      final l = a.layer.compareTo(b.layer);
      if (l != 0) return l;
      return b.depth.compareTo(a.depth);
    });
    final fill = Paint()..isAntiAlias = true;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    var groundDrawn = false;
    void drawGround() {
      if (groundDrawn) return;
      groundDrawn = true;
      if (groundPath != null) canvas.drawPath(groundPath!, groundPaint!);
    }

    for (final i in items) {
      if (i.layer >= 1) drawGround();
      if (i.stroke > 0) {
        canvas.drawPath(
            i.path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = i.stroke
              ..color = i.color);
        continue;
      }
      if (i.vertices != null) {
        canvas.drawVertices(
            i.vertices!,
            BlendMode.modulate,
            Paint()
              ..shader = ImageShader(
                  i.image!,
                  i.tiled ? TileMode.repeated : TileMode.clamp,
                  i.tiled ? TileMode.repeated : TileMode.clamp,
                  Matrix4.identity().storage));
        continue;
      }
      fill.color = i.color;
      canvas.drawPath(i.path, fill);
      // A hairline of the same colour closes anti-aliasing seams.
      if (i.color.a > 0.95) {
        edge.color = i.color;
        canvas.drawPath(i.path, edge);
      }
    }
    drawGround();
    if (labels && !walk && (settings.cut || !roofOn))
      for (final l in model.labels) {
        if (l.floorIndex > settings.maxFloor) continue;
        final at = Vec3(l.at.x, math.min(l.at.y, cutY - 0.2), l.at.z);
        final s = project(camera.toCamera(at), size, focal);
        if (s == null) continue;
        drawTag(canvas, s, l.title, l.subtitle);
      }
  }

  /// A face with a textile pattern, split into a small grid so the
  /// per-triangle (affine) texture mapping stays close to perspective;
  /// each cell is clipped with its texture coordinates and tinted by light.
  void addTextured(Face3 f, List<Vec3> pts, Vec3 n, double distance,
      Vec3 light, int layer, Size size, double focal) {
    final image = textileImage(f.textile!, f.textileVariant);
    final uv = f.uv!;
    final quad = pts.length == 4;
    final longest = quad
        ? math.max((pts[1] - pts[0]).length, (pts[3] - pts[0]).length)
        : 0.0;
    final cells = quad ? (longest / 0.5).ceil().clamp(1, 8) : 1;
    final tint = shade(
        Face3(f.points, const Color(0xffffffff),
            source: f.source, normal: f.normal),
        n,
        distance,
        light);
    final positions = <Offset>[], coords = <Offset>[];
    final outline = <Offset>[];
    var depth = 0.0, count = 0;
    (Vec3, Offset) at(double s, double t) {
      // Bilinear over the quad: s along p0→p3, t along p0→p1.
      final a = Vec3.lerp(pts[0], pts[3], s), b = Vec3.lerp(pts[1], pts[2], s);
      final ua = Offset.lerp(uv[0], uv[3], s)!, ub = Offset.lerp(uv[1], uv[2], s)!;
      return (camera.toCamera(Vec3.lerp(a, b, t)), Offset.lerp(ua, ub, t)!);
    }

    void cell(List<(Vec3, Offset)> poly) {
      final out = <(Vec3, Offset)>[];
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        final da = a.$1.z - near, db = b.$1.z - near;
        if (da >= 0) out.add(a);
        if ((da >= 0) != (db >= 0)) {
          final t = da / (da - db);
          out.add((Vec3.lerp(a.$1, b.$1, t), Offset.lerp(a.$2, b.$2, t)!));
        }
      }
      if (out.length < 3) return;
      final screen = [for (final p in out) project(p.$1, size, focal)!];
      for (var i = 1; i < out.length - 1; i++)
        for (final k in [0, i, i + 1]) {
          positions.add(screen[k]);
          coords.add(Offset(out[k].$2.dx * image.width, out[k].$2.dy * image.height));
        }
      for (final p in out) depth += p.$1.z;
      count += out.length;
    }

    if (quad) {
      for (var i = 0; i < cells; i++)
        for (var j = 0; j < cells; j++) {
          final s0 = i / cells, s1 = (i + 1) / cells, t0 = j / cells, t1 = (j + 1) / cells;
          cell([at(s0, t0), at(s0, t1), at(s1, t1), at(s1, t0)]);
        }
    } else {
      cell([for (var i = 0; i < pts.length; i++) (camera.toCamera(pts[i]), uv[i])]);
    }
    if (positions.isEmpty) return;
    // Outline for picking: the clipped face as a whole.
    for (final p in clipNear([for (final p in pts) camera.toCamera(p)]))
      outline.add(project(p, size, focal)!);
    final path = Path();
    if (outline.length >= 3) path.addPolygon(outline, true);
    items.add(_Item(path, tint, depth / count, layer, f.source,
        vertices: ui.Vertices(ui.VertexMode.triangles, positions,
            textureCoordinates: coords,
            colors: List.filled(positions.length, tint)),
        image: image,
        tiled: f.textile == Textile.kurak || f.textile == Textile.alasha));
  }

  static Color _lit(Color c, bool night) => night
      ? Color.from(alpha: 1, red: c.r * 0.22, green: c.g * 0.25, blue: c.b * 0.32)
      : Color.from(alpha: 1, red: c.r * 0.95, green: c.g * 0.95, blue: c.b * 0.92);

  void drawTag(Canvas canvas, Offset at, String title, String sub) {
    final t = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: title,
              style: const TextStyle(
                  fontFamily: 'NotoSans',
                  fontFamilyFallback: ['PingFang SC', 'Noto Sans SC'],
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          TextSpan(
              text: '\n$sub',
              style: const TextStyle(
                  fontFamily: 'PlexMono',
                  color: Color(0xffF2B867),
                  fontSize: 11)),
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr)
      ..layout();
    final box = Rect.fromCenter(
        center: at, width: t.width + 16, height: t.height + 8);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)),
        Paint()..color = const Color(0xd11C2326));
    t.paint(canvas, box.topLeft + const Offset(8, 4));
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => true;
}

/// Orbit and walk-through views of the house.
class SceneView extends StatefulWidget {
  const SceneView(
      {super.key,
      required this.doc,
      required this.derived,
      required this.roomName,
      required this.settings,
      required this.walk,
      this.view = 'iso',
      this.viewToken = 0,
      this.walkStart,
      this.walkFloor = 0,
      this.onPick,
      this.selected,
      this.outsideLabel = 'outside',
      this.inWallLabel = 'wall',
      this.areaUnit = 'm²'});
  final HouseDocument doc;
  final DerivedHouse derived;
  final String Function(Room) roomName;
  final SceneSettings settings;
  final bool walk;

  /// Camera preset (iso, front, back, side, top); a new token re-applies it.
  final String view;
  final int viewToken;

  /// Plan point (mm) and floor to stand at; a new token moves there.
  final ({int floorIndex, double x, double y, double yaw, int token})? walkStart;
  final int walkFloor;
  final ValueChanged<SourceRef?>? onPick;
  final SourceRef? selected;
  final String outsideLabel, inWallLabel, areaUnit;
  @override
  State<SceneView> createState() => SceneViewState();
}

class SceneViewState extends State<SceneView>
    with SingleTickerProviderStateMixin {
  late SceneModel model;
  Object? modelKey;
  double yaw = 0, pitch = 0, distance = 20;
  Vec3 target = const Vec3(0, 0, 0);
  double startDistance = 20;

  // Walk state: world position, look angles.
  double wx = 0, wz = 0, wYaw = 0, wPitch = 0;
  int floor = 0;
  Offset joy = Offset.zero;
  int? joyPointer;
  final keys = <LogicalKeyboardKey>{};
  late final Ticker ticker;
  Duration last = Duration.zero;
  ScenePainter? painter;
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    ticker = createTicker(tick);
    rebuild();
    applyView(widget.view);
    placeWalker();
    if (widget.walk)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusNode.requestFocus();
      });
  }

  @override
  void dispose() {
    ticker.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SceneView old) {
    super.didUpdateWidget(old);
    rebuild();
    if (old.viewToken != widget.viewToken || old.view != widget.view)
      applyView(widget.view);
    if (old.walkStart?.token != widget.walkStart?.token ||
        old.walkFloor != widget.walkFloor) placeWalker();
    if (!widget.walk && ticker.isActive) ticker.stop();
  }

  void rebuild() {
    final key = (
      widget.doc,
      widget.settings.furniture,
      widget.settings.foundation,
      widget.settings.roof,
      widget.walk,
      widget.areaUnit,
      widget.outsideLabel
    );
    if (key == modelKey) return;
    modelKey = key;
    model = buildScene(
        widget.doc,
        widget.derived,
        SceneOptions(
            roof: widget.settings.roof,
            furniture: widget.settings.furniture,
            foundation: widget.settings.foundation,
            walk: widget.walk),
        widget.roomName,
        areaUnit: widget.areaUnit);
  }

  void applyView(String view) {
    final size = math.max(model.width, model.depth) / 13;
    final c = model.center;
    final front = model.frontZ;
    final (x, y, z) = switch (view) {
      'front' => (1.5, 3.2, 25.0 * front),
      'back' => (2.0, 4.0, -21.0 * front),
      'side' => (24.0, 5.0, 2.0),
      'top' => (0.0, 34.0, 0.01),
      _ => (15.0, 12.0, 19.0 * front),
    };
    target = Vec3(c.x, view == 'top' ? 0 : 1.4, c.z);
    final offset = Vec3(x, y, z) * math.max(0.6, size);
    distance = offset.length;
    yaw = math.atan2(offset.x, offset.z);
    pitch = math.asin((offset.y / distance).clamp(-1.0, 1.0));
  }

  void placeWalker() {
    final start = widget.walkStart;
    if (start != null) {
      floor = start.floorIndex.clamp(0, model.elevations.length - 1);
      wx = start.x / 1000;
      wz = model.depth - start.y / 1000;
      wYaw = start.yaw;
      wPitch = 0;
      return;
    }
    floor = widget.walkFloor.clamp(0, model.elevations.length - 1);
    // Outside the front, looking at the house.
    wx = model.width / 2;
    wz = model.frontZ > 0 ? model.depth + 4 : -4;
    wYaw = model.frontZ > 0 ? 0 : math.pi;
    wPitch = 0;
  }

  /// Stand at a plan point (mm) facing [yaw].
  void standAt(double x, double y, double yawValue, int floorIndex) =>
      setState(() {
        floor = floorIndex;
        wx = x / 1000;
        wz = model.depth - y / 1000;
        wYaw = yawValue;
        wPitch = 0;
      });

  bool blocked(double x, double z) {
    const r = 0.22;
    for (final c in model.colliders) {
      if (c.floorIndex != floor) continue;
      final cx = x.clamp(c.x0, c.x1), cz = z.clamp(c.z0, c.z1);
      if ((x - cx) * (x - cx) + (z - cz) * (z - cz) < r * r) return true;
    }
    return false;
  }

  /// Run the movement loop while a key or the joystick is held.
  void move() {
    if (!widget.walk || ticker.isActive) return;
    last = Duration.zero;
    ticker.start();
  }

  void tick(Duration now) {
    final dt = math.min(0.05, (now - last).inMicroseconds / 1e6);
    last = now;
    var forward = -joy.dy, strafe = joy.dx;
    bool k(LogicalKeyboardKey key) => keys.contains(key);
    if (k(LogicalKeyboardKey.keyW) || k(LogicalKeyboardKey.arrowUp)) forward += 1;
    if (k(LogicalKeyboardKey.keyS) || k(LogicalKeyboardKey.arrowDown)) forward -= 1;
    if (k(LogicalKeyboardKey.keyA)) strafe -= 1;
    if (k(LogicalKeyboardKey.keyD)) strafe += 1;
    var turn = 0.0;
    if (k(LogicalKeyboardKey.arrowLeft)) turn += 1.8 * dt;
    if (k(LogicalKeyboardKey.arrowRight)) turn -= 1.8 * dt;
    if (forward == 0 && strafe == 0 && turn == 0) {
      // Idle: stop asking for frames until the next input.
      if (joyPointer == null && keys.isEmpty) ticker.stop();
      return;
    }
    final sp = 1.7 * dt, sy = math.sin(wYaw), cy = math.cos(wYaw);
    final dx = (-sy * forward + cy * strafe) * sp,
        dz = (-cy * forward - sy * strafe) * sp;
    setState(() {
      wYaw += turn;
      if (!blocked(wx + dx, wz)) wx += dx;
      if (!blocked(wx, wz + dz)) wz += dz;
    });
  }

  Camera get camera {
    if (widget.walk) {
      final eyeY = (floor < model.elevations.length ? model.elevations[floor] : 0) + 1.6;
      final f = Vec3(-math.sin(wYaw) * math.cos(wPitch), math.sin(wPitch),
          -math.cos(wYaw) * math.cos(wPitch));
      return Camera(Vec3(wx, eyeY, wz), f, 72 * math.pi / 180);
    }
    final eye = target +
        Vec3(math.cos(pitch) * math.sin(yaw), math.sin(pitch),
                math.cos(pitch) * math.cos(yaw)) *
            distance;
    return Camera(eye, (target - eye).unit, 42 * math.pi / 180);
  }

  /// Room name (or outside / in a wall) under the walker.
  String get whereAmI {
    final px = wx * 1000, py = (model.depth - wz) * 1000;
    if (px < 0 || py < 0 || wx > model.width || wz > model.depth || wz < 0)
      return widget.outsideLabel;
    final g = widget.derived.floors[floor].base;
    final i = g.axes.v.indexWhere((a) => a.pos > px) - 1,
        j = g.axes.h.indexWhere((a) => a.pos > py) - 1;
    final id = g.owners[Cell(i, j)];
    final room = widget.doc.floors[floor].rooms.where((r) => r.id == id).firstOrNull;
    return room == null ? widget.inWallLabel : widget.roomName(room);
  }

  @override
  Widget build(BuildContext context) {
    painter = ScenePainter(
        model: model,
        camera: camera,
        settings: widget.settings.copyWith(
            maxFloor: widget.walk ? floor : widget.settings.maxFloor),
        northAngleDeg: widget.doc.footprint.northAngleDeg,
        walk: widget.walk,
        labels: true,
        selected: widget.selected);
    final view = Listener(
        // Keys (W A S D, arrows) go to the view the user last touched.
        onPointerDown: (_) {
          if (widget.walk && !focusNode.hasFocus) focusNode.requestFocus();
        },
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && !widget.walk)
            setState(() => distance =
                (distance * (e.scrollDelta.dy > 0 ? 1.12 : 1 / 1.12))
                    .clamp(3.0, 90.0));
        },
        child: GestureDetector(
            onTapUp: (d) => widget.onPick?.call(painter?.pick(d.localPosition)),
            onScaleStart: (_) => startDistance = distance,
            onScaleUpdate: (d) => setState(() {
                  if (widget.walk) {
                    wYaw -= d.focalPointDelta.dx * 0.006;
                    wPitch = (wPitch - d.focalPointDelta.dy * 0.005)
                        .clamp(-1.2, 1.2);
                    return;
                  }
                  if (d.pointerCount == 1) {
                    yaw -= d.focalPointDelta.dx * 0.008;
                    pitch = (pitch + d.focalPointDelta.dy * 0.006)
                        .clamp(5 * math.pi / 180, 89.5 * math.pi / 180);
                  } else {
                    distance = (startDistance / d.scale).clamp(3.0, 90.0);
                    final cam = camera;
                    final k = distance / 600;
                    target = target -
                        cam.right * (d.focalPointDelta.dx * k) +
                        cam.up * (d.focalPointDelta.dy * k);
                  }
                }),
            child: CustomPaint(painter: painter, size: Size.infinite)));
    return KeyboardListener(
        focusNode: focusNode,
        autofocus: widget.walk,
        onKeyEvent: (e) {
          if (e is KeyDownEvent) {
            keys.add(e.logicalKey);
            move();
          }
          if (e is KeyUpEvent) keys.remove(e.logicalKey);
        },
        child: Stack(children: [
          Positioned.fill(child: view),
          if (widget.walk) ...[
            Positioned(
                right: 10,
                top: 10,
                child: IgnorePointer(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xffC8D0D2))),
                        child: Text(
                            '$whereAmI · x ${wx.toStringAsFixed(1)}  y ${(model.depth - wz).toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontFamily: 'PlexMono',
                                fontSize: 12,
                                color: Color(0xff1C2326)))))),
            Positioned(left: 18, bottom: 18, child: joystick()),
          ],
        ]));
  }

  Widget joystick() {
    const size = 116.0, reach = 44.0;
    void set(Offset local) {
      var d = local - const Offset(size / 2, size / 2);
      if (d.distance > reach) d = d / d.distance * reach;
      setState(() => joy = d / reach);
    }

    return Listener(
        onPointerDown: (e) {
          joyPointer = e.pointer;
          set(e.localPosition);
          move();
        },
        onPointerMove: (e) {
          if (e.pointer == joyPointer) set(e.localPosition);
        },
        onPointerUp: (e) {
          if (e.pointer != joyPointer) return;
          joyPointer = null;
          setState(() => joy = Offset.zero);
        },
        onPointerCancel: (e) {
          joyPointer = null;
          setState(() => joy = Offset.zero);
        },
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.5),
                border: Border.all(color: const Color(0xffC8D0D2))),
            child: Center(
                child: Transform.translate(
                    offset: joy * reach,
                    child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xffC2771A).withValues(alpha: 0.9)))))));
  }
}
