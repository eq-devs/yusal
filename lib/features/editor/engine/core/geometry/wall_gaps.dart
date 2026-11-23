import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';

/// A wall that stops short of the next wall, so that the two sides of it
/// are still one room: from the wall's free end at ([x0], [y0]) to the
/// wall it would meet if drawn on, at ([x1], [y1]). Millimetres.
class WallGap {
  const WallGap(this.x0, this.y0, this.x1, this.y1, this.roomId);
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  /// The room on both sides of the gap; null where no room is drawn yet.
  final String? roomId;

  double get length => (x1 - x0).abs() + (y1 - y0).abs();

  /// The gap as an area of the plan, for pointing at it.
  PlanRect get area => PlanRect(x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1,
      x0 < x1 ? x1 : x0, y0 < y1 ? y1 : y0);
}

/// A gap wider than this is taken as meant: an open plan, not a wall left
/// unfinished. Wide enough for a double door.
const widestWallGap = 1800.0;

final _kept = Expando<List<WallGap>>('wallGaps');

/// Where the walls of [base] fail to close: every wall end that stands
/// free in the floor with another wall straight ahead of it, no farther
/// than [widest], and the same room on both sides of the way there. What a
/// CAD program marks when it reports "room not enclosed".
///
/// A boundary that is open on purpose is not a gap: an edge of kind `open`
/// separates two rooms without a wall, and is left alone.
List<WallGap> findWallGaps(FloorBase base, {double widest = widestWallGap}) {
  if (widest == widestWallGap) {
    final kept = _kept[base];
    if (kept != null) return kept;
  }
  // Wall edges at each grid point, and every edge by where it starts and
  // which way it runs.
  final walls = <(int, int), List<UnitEdge>>{};
  final from = <(int, int, AxisDir), UnitEdge>{};
  final to = <(int, int, AxisDir), UnitEdge>{};
  (int, int) startOf(UnitEdge e) => e.axis.dir == AxisDir.V
      ? (e.axis.pos, e.start.pos)
      : (e.start.pos, e.axis.pos);
  (int, int) endOf(UnitEdge e) => e.axis.dir == AxisDir.V
      ? (e.axis.pos, e.end.pos)
      : (e.end.pos, e.axis.pos);
  for (final e in base.edges) {
    final a = startOf(e);
    final b = endOf(e);
    from[(a.$1, a.$2, e.axis.dir)] = e;
    to[(b.$1, b.$2, e.axis.dir)] = e;
    if (e.hasWall) {
      (walls[a] ??= []).add(e);
      (walls[b] ??= []).add(e);
    }
  }
  final gaps = <WallGap>[];
  for (final MapEntry(key: at, value: meeting) in walls.entries) {
    if (meeting.length != 1) continue;
    // A free end: the wall arrives here and nothing carries on.
    final wall = meeting.single;
    final dir = wall.axis.dir;
    final forward = endOf(wall) == at;
    var here = at;
    var length = 0.0;
    String? room;
    var same = true;
    var met = false;
    while (true) {
      final next =
          forward ? from[(here.$1, here.$2, dir)] : to[(here.$1, here.$2, dir)];
      if (next == null || next.hasWall || next.kind == 'open') break;
      final a = base.owners[next.negative];
      final b = base.owners[next.positive];
      if (next.negative == null ||
          next.positive == null ||
          a != b ||
          base.outside.contains(next.negative) ||
          base.outside.contains(next.positive)) {
        same = false;
        break;
      }
      room = a;
      length += (next.end.pos - next.start.pos).abs();
      if (length > widest) break;
      here = forward ? endOf(next) : startOf(next);
      if (walls.containsKey(here)) {
        met = true;
        break;
      }
    }
    if (!met || !same || length <= 0 || length > widest) continue;
    gaps.add(WallGap(at.$1.toDouble(), at.$2.toDouble(), here.$1.toDouble(),
        here.$2.toDouble(), room));
  }
  // Two free ends facing each other describe one gap.
  final seen = <(double, double, double, double)>{};
  final out = <WallGap>[];
  for (final g in gaps) {
    final r = g.area;
    if (seen.add((r.left, r.bottom, r.right, r.top))) out.add(g);
  }
  out.sort((a, b) {
    final c = a.area.left.compareTo(b.area.left);
    return c != 0 ? c : a.area.bottom.compareTo(b.area.bottom);
  });
  final result = List<WallGap>.unmodifiable(out);
  if (widest == widestWallGap) _kept[base] = result;
  return result;
}
