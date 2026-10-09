import 'package:flutter/widgets.dart';
import '../core/document/house_document.dart';
import '../core/geometry/floor_base.dart';
import '../core/geometry/derived_house.dart';

/// Stable, model-based extension points. Occupied corners and opening holes
/// are excluded; screen-density filtering is applied separately by the editor.
List<Offset> wallAttachmentPoints(
    FloorBase base, List<OpeningPlacement> openings) {
  final endpoints = <Offset>{}, middle = <Offset>{};
  Offset point(WallSegment w, double along) => w.axis.dir == AxisDir.H
      ? Offset(along, w.axis.pos.toDouble())
      : Offset(w.axis.pos.toDouble(), along);
  for (final w in base.wallSegments) {
    endpoints.add(point(w, w.start.pos.toDouble()));
    endpoints.add(point(w, w.end.pos.toDouble()));
    middle.add(point(w, (w.start.pos + w.end.pos) / 2));
  }
  bool available(Offset p) => canExtendWallFrom(base, openings, p);

  return [...endpoints, ...middle.difference(endpoints)]
      .where(available)
      .toList();
}

/// Whether a new wall of at least 0.30 m can start at [p]: not inside a door
/// or window, and at least one orthogonal direction is free and indoors.
bool canExtendWallFrom(
    FloorBase base, List<OpeningPlacement> openings, Offset p) {
  for (final o in openings.where((o) => o.status == 'ok')) {
    final along = o.axis.dir == AxisDir.H ? p.dx : p.dy;
    final cross = o.axis.dir == AxisDir.H ? p.dy : p.dx;
    if (cross == o.axis.pos && along >= o.start && along <= o.end) return false;
  }
  for (final d in [
    const Offset(300, 0),
    const Offset(-300, 0),
    const Offset(0, 300),
    const Offset(0, -300)
  ]) {
    final end = p + d;
    if (end.dx < 0 ||
        end.dy < 0 ||
        end.dx > base.axes.v.last.pos ||
        end.dy > base.axes.h.last.pos) continue;
    final horizontal = d.dx != 0;
    final cross = horizontal ? p.dy : p.dx;
    if (cross == 0 ||
        cross == (horizontal ? base.axes.h.last.pos : base.axes.v.last.pos))
      continue;
    final start = horizontal ? p.dx : p.dy;
    final stop = horizontal ? end.dx : end.dy;
    final lo = start < stop ? start : stop, hi = start > stop ? start : stop;
    if (!base.wallSegments.any((w) =>
        w.axis.dir == (horizontal ? AxisDir.H : AxisDir.V) &&
        w.axis.pos == cross &&
        w.start.pos < hi &&
        w.end.pos > lo)) return true;
  }
  return false;
}
