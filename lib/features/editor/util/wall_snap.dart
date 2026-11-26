import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';

/// Result of snapping the free end of a wall that is being drawn or resized.
/// [connected] is true when the end lands on another physical wall, so the
/// editor can tell the user that the new wall joins the existing layout.
class WallEndSnap {
  const WallEndSnap(this.end,
      {required this.horizontal, this.connected = false, this.aligned});
  final Offset end;
  final bool horizontal;
  final bool connected;

  /// Position (mm) of the existing wall line the free end lined up with,
  /// when it snapped by alignment rather than by joining a wall or to the
  /// grid; the editor draws it as a dashed guide, like the tracking lines
  /// of SketchUp, Space Designer 3D and Houzz Pro.
  final double? aligned;
}

double _along(WallSegment w, Offset p) => w.axis.dir == AxisDir.H ? p.dx : p.dy;
double _cross(WallSegment w, Offset p) => w.axis.dir == AxisDir.H ? p.dy : p.dx;

/// Whether [p] (world millimetres) lies on a physical wall, ignoring
/// collinear walls that would simply overlap the wall being drawn.
bool endJoinsWall(FloorBase base, Offset p,
    {required bool horizontal, bool Function(WallSegment)? ignore}) {
  for (final w in base.wallSegments) {
    if (ignore?.call(w) ?? false) continue;
    final along = _along(w, p);
    final cross = _cross(w, p);
    if (cross != w.axis.pos) continue;
    final perpendicular = (w.axis.dir == AxisDir.H) != horizontal;
    if (perpendicular) {
      if (along >= w.start.pos && along <= w.end.pos) return true;
    } else if (along == w.start.pos || along == w.end.pos) {
      return true;
    }
  }
  return false;
}

/// Snap the free end of an orthogonal wall that starts at [origin].
///
/// Priority: join a wall within [connectRadius] (crossing perpendicular walls
/// or the ends of collinear walls), then align with existing wall coordinates
/// within [alignRadius], then a 100 mm grid. Radii are world millimetres so
/// callers can derive them from a constant on-screen distance. The result is
/// clamped to the footprint so dragging past the house stops on the outer wall.
///
/// [previous] is the snap of the last move of the same stroke. It makes the
/// snap sticky, as CAD inference is: the direction stays until the other
/// component is [release] times larger, and a join or alignment holds
/// until the finger is [release] times its radius away, so the end does
/// not flicker between candidates near a boundary.
WallEndSnap snapWallEnd(FloorBase base, Offset origin, Offset raw,
    {required double connectRadius,
    required double alignRadius,
    bool? forceHorizontal,
    bool Function(WallSegment)? ignore,
    Set<int> skipAlong = const {},
    WallEndSnap? previous,
    double release = 1.5}) {
  final dx = (raw.dx - origin.dx).abs();
  final dy = (raw.dy - origin.dy).abs();
  final horizontal = forceHorizontal ??
      switch (previous?.horizontal) {
        true => dy <= dx * release,
        false => dx > dy * release,
        null => dx >= dy,
      };
  final carrier = horizontal ? origin.dy : origin.dx;
  final start = horizontal ? origin.dx : origin.dy;
  final limit =
      (horizontal ? base.axes.v.last.pos : base.axes.h.last.pos).toDouble();
  final along = (horizontal ? raw.dx : raw.dy).clamp(0.0, limit);
  Offset at(double value) =>
      horizontal ? Offset(value, carrier) : Offset(carrier, value);

  // Hold on to what the end snapped to while the finger stays near it.
  if (previous != null &&
      previous.horizontal == horizontal &&
      (previous.connected || previous.aligned != null) &&
      (horizontal ? previous.end.dy : previous.end.dx) == carrier) {
    final held = horizontal ? previous.end.dx : previous.end.dy;
    final reach =
        (previous.connected ? connectRadius : alignRadius) * release;
    if (held != start && (held - along).abs() <= reach) {
      final end = at(held);
      return WallEndSnap(end,
          horizontal: horizontal,
          connected:
              endJoinsWall(base, end, horizontal: horizontal, ignore: ignore),
          aligned: previous.aligned);
    }
  }

  double? best;
  var bestDistance = connectRadius;
  void consider(double value) {
    if (value == start) return;
    final distance = (value - along).abs();
    if (distance <= bestDistance) {
      best = value;
      bestDistance = distance;
    }
  }

  for (final w in base.wallSegments) {
    if (ignore?.call(w) ?? false) continue;
    final perpendicular = (w.axis.dir == AxisDir.H) != horizontal;
    if (perpendicular) {
      if (carrier >= w.start.pos && carrier <= w.end.pos) {
        consider(w.axis.pos.toDouble());
      }
    } else if (w.axis.pos == carrier) {
      consider(w.start.pos.toDouble());
      consider(w.end.pos.toDouble());
    }
  }
  if (best != null) {
    return WallEndSnap(at(best!), horizontal: horizontal, connected: true);
  }

  double? aligned;
  var alignDistance = alignRadius;
  for (final axis in horizontal ? base.axes.v : base.axes.h) {
    if (axis.pos == start || skipAlong.contains(axis.pos)) continue;
    final distance = (axis.pos - along).abs();
    if (distance < alignDistance) {
      aligned = axis.pos.toDouble();
      alignDistance = distance;
    }
  }
  final value = aligned ?? ((along / 100).round() * 100.0).clamp(0.0, limit);
  final end = at(value);
  return WallEndSnap(end,
      horizontal: horizontal,
      connected:
          endJoinsWall(base, end, horizontal: horizontal, ignore: ignore),
      aligned: aligned);
}

/// Where a wall that runs on from [from] along [heading] (a unit step on
/// one axis, world millimetres) first meets another wall: the nearest
/// wall crossing its line, or the near end of a wall already on that
/// line. Null when nothing lies ahead.
Offset? wallAhead(FloorBase base, Offset from, Offset heading) {
  final horizontal = heading.dx != 0;
  final sign = horizontal ? heading.dx.sign : heading.dy.sign;
  final carrier = horizontal ? from.dy : from.dx;
  final start = horizontal ? from.dx : from.dy;
  double? best;
  void consider(double value) {
    final ahead = (value - start) * sign;
    if (ahead <= 0) return;
    if (best == null || ahead < (best! - start) * sign) best = value;
  }

  for (final w in base.wallSegments) {
    final perpendicular = (w.axis.dir == AxisDir.H) != horizontal;
    if (perpendicular) {
      if (carrier >= w.start.pos && carrier <= w.end.pos) {
        consider(w.axis.pos.toDouble());
      }
    } else if (w.axis.pos == carrier) {
      consider(w.start.pos.toDouble());
      consider(w.end.pos.toDouble());
    }
  }
  if (best == null) return null;
  return horizontal ? Offset(best!, carrier) : Offset(carrier, best!);
}

/// The physical wall nearest to [p] within [tolerance] (world millimetres).
/// At junctions several walls are equally close; inner walls win over the
/// outer footprint and shorter walls over longer ones, because short and
/// inner walls are otherwise the hardest to pick with a finger.
WallSegment? nearestWall(FloorBase base, Offset p, double tolerance,
    {bool innerOnly = false}) {
  WallSegment? best;
  var bestScore = double.infinity;
  for (final w in base.allWallSegments) {
    if (innerOnly && w.axis.kind == 'boundary') continue;
    final along = _along(w, p);
    final cross = _cross(w, p);
    final outside = along < w.start.pos
        ? w.start.pos - along
        : along > w.end.pos
            ? along - w.end.pos
            : 0.0;
    final distance = math.max((cross - w.axis.pos).abs(), outside);
    if (distance > tolerance) continue;
    final score = distance +
        (w.axis.kind == 'boundary' ? tolerance * 0.01 : 0) +
        (w.end.pos - w.start.pos) * 1e-9;
    if (score < bestScore) {
      best = w;
      bestScore = score;
    }
  }
  return best;
}

/// Where a measuring point at [p] (world millimetres) lands: on a wall
/// corner within [radius], else on the nearest wall face within [radius]
/// (so measuring between two faces gives a room's clear size), else on
/// the 50 mm grid. [rects] are the wall rectangles of the floor, low walls
/// included.
Offset snapMeasurePoint(List<PlanRect> rects, Offset p, double radius) {
  Offset? corner;
  var cornerDistance = radius;
  for (final r in rects) {
    for (final c in [
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
      Offset(r.left, r.top),
      Offset(r.right, r.top),
    ]) {
      final d = (c - p).distance;
      if (d <= cornerDistance) {
        corner = c;
        cornerDistance = d;
      }
    }
  }
  if (corner != null) return corner;
  Offset? face;
  var faceDistance = radius;
  void consider(Offset q) {
    final d = (q - p).distance;
    if (d <= faceDistance) {
      face = q;
      faceDistance = d;
    }
  }

  for (final r in rects) {
    final x = p.dx.clamp(r.left, r.right);
    final y = p.dy.clamp(r.bottom, r.top);
    consider(Offset(r.left, y));
    consider(Offset(r.right, y));
    consider(Offset(x, r.bottom));
    consider(Offset(x, r.top));
  }
  if (face != null) {
    // Along the face, to the 10 mm: the face itself fixes the other axis.
    final f = face!;
    final onVertical = rects.any((r) =>
        (f.dx == r.left || f.dx == r.right) && f.dy > r.bottom && f.dy < r.top);
    return onVertical
        ? Offset(f.dx, (f.dy / 10).roundToDouble() * 10)
        : Offset((f.dx / 10).roundToDouble() * 10, f.dy);
  }
  return Offset((p.dx / 50).roundToDouble() * 50, (p.dy / 50).roundToDouble() * 50);
}

/// Distance in canvas-local pixels from [p] to the segment [a]–[b].
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (length2 == 0) return (p - a).distance;
  final t =
      (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
