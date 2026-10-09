import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../core/document/house_document.dart';
import '../core/geometry/floor_base.dart';

/// Result of snapping the free end of a wall that is being drawn or resized.
/// [connected] is true when the end lands on another physical wall, so the
/// editor can tell the user that the new wall joins the existing layout.
class WallEndSnap {
  const WallEndSnap(this.end,
      {required this.horizontal, this.connected = false});
  final Offset end;
  final bool horizontal;
  final bool connected;
}

double _along(WallSegment w, Offset p) => w.axis.dir == AxisDir.H ? p.dx : p.dy;
double _cross(WallSegment w, Offset p) => w.axis.dir == AxisDir.H ? p.dy : p.dx;

/// Whether [p] (world millimetres) lies on a physical wall, ignoring
/// collinear walls that would simply overlap the wall being drawn.
bool endJoinsWall(FloorBase base, Offset p,
    {required bool horizontal, bool Function(WallSegment)? ignore}) {
  for (final w in base.wallSegments) {
    if (ignore?.call(w) ?? false) continue;
    final along = _along(w, p), cross = _cross(w, p);
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
WallEndSnap snapWallEnd(FloorBase base, Offset origin, Offset raw,
    {required double connectRadius,
    required double alignRadius,
    bool? forceHorizontal,
    bool Function(WallSegment)? ignore,
    Set<int> skipAlong = const {}}) {
  final horizontal = forceHorizontal ??
      (raw.dx - origin.dx).abs() >= (raw.dy - origin.dy).abs();
  final carrier = horizontal ? origin.dy : origin.dx;
  final start = horizontal ? origin.dx : origin.dy;
  final limit =
      (horizontal ? base.axes.v.last.pos : base.axes.h.last.pos).toDouble();
  final along = (horizontal ? raw.dx : raw.dy).clamp(0.0, limit).toDouble();
  Offset at(double value) =>
      horizontal ? Offset(value, carrier) : Offset(carrier, value);

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
  final end = at(value.toDouble());
  return WallEndSnap(end,
      horizontal: horizontal,
      connected:
          endJoinsWall(base, end, horizontal: horizontal, ignore: ignore));
}

/// The physical wall nearest to [p] within [tolerance] (world millimetres).
/// At junctions several walls are equally close; inner walls win over the
/// outer footprint and shorter walls over longer ones, because short and
/// inner walls are otherwise the hardest to pick with a finger.
WallSegment? nearestWall(FloorBase base, Offset p, double tolerance,
    {bool innerOnly = false}) {
  WallSegment? best;
  var bestScore = double.infinity;
  for (final w in base.wallSegments) {
    if (innerOnly && w.axis.kind == 'boundary') continue;
    final along = _along(w, p), cross = _cross(w, p);
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

/// Distance in canvas-local pixels from [p] to the segment [a]–[b].
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (length2 == 0) return (p - a).distance;
  final t =
      (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
